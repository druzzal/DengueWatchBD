"""Parse one DGHS daily dengue press release into structured numbers.

The district table lives on the last pages. Its text is encoded with a legacy
Bengali font, so the district names come out mangled ("ফরিদপুর" reads as
"ফরিদপুি") and cannot be matched by name. `district_aliases.json` maps the
exact mangled strings to district codes; anything not in that map raises, so a
layout or font change fails loudly instead of silently dropping a district.

Every parse is reconciled against the national totals printed on page 1. If the
districts do not sum to the national figure, nothing is returned.
"""

from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path

import pdfplumber

LOG = logging.getLogger(__name__)

_ALIAS_PATH = Path(__file__).with_name("district_aliases.json")
DISTRICT_ALIASES: dict[str, str] = json.loads(_ALIAS_PATH.read_text(encoding="utf-8"))

BENGALI_DIGITS = str.maketrans("০১২৩৪৫৬৭৮৯", "0123456789")

# Columns of the district table, after the division / serial / name / institution cells.
COL_NEW_GOVT, COL_NEW_PRIVATE, COL_NEW_TOTAL = 0, 1, 2
COL_CUMULATIVE, COL_DEATHS, COL_DISCHARGED, COL_CURRENT = 3, 4, 5, 6
EXPECTED_COLUMNS = 11


class ParseError(RuntimeError):
    """The PDF did not look the way we expect. Never emit data after this."""


@dataclass
class DistrictRecord:
    code: str
    cumulative_cases: int
    deaths: int
    discharged: int
    currently_admitted: int


@dataclass
class DailyReport:
    """One day's cumulative-to-date picture, as published."""
    report_date: date
    national_cases: int
    national_deaths: int
    districts: dict[str, DistrictRecord] = field(default_factory=dict)

    @property
    def total_currently_admitted(self) -> int:
        return sum(d.currently_admitted for d in self.districts.values())


def _to_int(cell: str | None) -> int | None:
    if cell is None:
        return None
    text = cell.translate(BENGALI_DIGITS).replace(",", "").strip()
    return int(text) if text.isdigit() else None


def _clean(cell: str | None) -> str:
    return (cell or "").replace("\n", " ").strip()


# The summary page carries a run of four figures — week cases, week deaths,
# year-to-date cases, year-to-date deaths — beside an epidemiological-week
# label. Different PDF text extractors order the label and the numbers
# differently, so accept either arrangement.
_NUM = r"([\d,]+)"
_TOTALS_PATTERNS = (
    re.compile(rf"W\d+:\s*{_NUM}\s+{_NUM}\s+{_NUM}\s+{_NUM}"),
    re.compile(rf"{_NUM}\s+{_NUM}\s+{_NUM}\s+{_NUM}\s+W\d+:"),
)


def parse_national_totals(pdf: pdfplumber.PDF) -> tuple[int, int]:
    """Read the year-to-date national case and death totals from the summary page.

    The page order is not stable between releases — the English summary is
    sometimes the first page and sometimes the seventh, and the document is
    10 or 11 pages depending on the day — so every page is searched rather
    than assuming a position.
    """
    for page in pdf.pages:
        raw = (page.extract_text() or "").translate(BENGALI_DIGITS)
        text = " ".join(raw.split())
        for pattern in _TOTALS_PATTERNS:
            match = pattern.search(text)
            if match:
                cases = int(match.group(3).replace(",", ""))
                deaths = int(match.group(4).replace(",", ""))
                if cases >= deaths:
                    return cases, deaths

    raise ParseError(
        "could not find the national totals on any page — the summary layout "
        "may have changed"
    )


def parse_pdf(path: Path, report_date: date) -> DailyReport:
    with pdfplumber.open(path) as pdf:
        national_cases, national_deaths = parse_national_totals(pdf)

        totals: dict[str, list[int]] = {}
        city_row: list[int] | None = None
        unknown: set[str] = set()

        for page in pdf.pages:
            for table in page.extract_tables():
                for row in table:
                    cells = [_clean(c) for c in row]
                    if len(cells) < EXPECTED_COLUMNS:
                        continue
                    values = [_to_int(c) for c in cells[4:11]]
                    if any(v is None for v in values):
                        continue

                    name = cells[2]
                    if not name:
                        # Dhaka city corporation is labelled in the division column
                        # and reported separately from Dhaka district.
                        if cells[0] and city_row is None and values[COL_CUMULATIVE] > 0:
                            city_row = values
                        continue

                    code = DISTRICT_ALIASES.get(name)
                    if code is None:
                        unknown.add(name)
                        continue

                    bucket = totals.setdefault(code, [0] * 7)
                    for index, value in enumerate(values):
                        bucket[index] += value

        if unknown:
            raise ParseError(
                "unrecognised district names — the PDF layout or font may have "
                f"changed, add these to district_aliases.json: {sorted(unknown)}"
            )
        if city_row is not None:
            bucket = totals.setdefault("DHAKA", [0] * 7)
            for index, value in enumerate(city_row):
                bucket[index] += value

    districts = {
        code: DistrictRecord(
            code=code,
            cumulative_cases=v[COL_CUMULATIVE],
            deaths=v[COL_DEATHS],
            discharged=v[COL_DISCHARGED],
            currently_admitted=v[COL_CURRENT],
        )
        for code, v in totals.items()
    }

    report = DailyReport(report_date, national_cases, national_deaths, districts)
    _reconcile(report)
    return report


def _reconcile(report: DailyReport) -> None:
    """Refuse to emit data that does not agree with the PDF's own totals.

    The table lists only districts that have reported cases, so early in a
    season it is far shorter than 64 rows — on 1 January 2026 it had 28. A row
    count is therefore not a validity check; the totals are. What must hold is
    that every listed district was recognised (enforced in `parse_pdf`) and that
    the listed districts account for the whole national figure.
    """
    if not report.districts:
        raise ParseError("no district rows found — the table layout may have changed")

    summed_cases = sum(d.cumulative_cases for d in report.districts.values())
    summed_deaths = sum(d.deaths for d in report.districts.values())

    if summed_cases != report.national_cases:
        raise ParseError(
            f"district cases sum to {summed_cases:,} but the national total is "
            f"{report.national_cases:,}"
        )
    if summed_deaths != report.national_deaths:
        raise ParseError(
            f"district deaths sum to {summed_deaths} but the national total is "
            f"{report.national_deaths}"
        )

    # Internal identity: admitted - discharged - deaths = still in hospital.
    for record in report.districts.values():
        expected = record.cumulative_cases - record.discharged - record.deaths
        if expected != record.currently_admitted:
            raise ParseError(
                f"{record.code}: {record.cumulative_cases} admitted - "
                f"{record.discharged} discharged - {record.deaths} deaths = {expected}, "
                f"but the PDF reports {record.currently_admitted} currently admitted"
            )
