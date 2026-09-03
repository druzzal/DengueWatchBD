"""Turn a run of daily DGHS reports into the JSON the iOS app reads.

DGHS publishes cumulative year-to-date figures, while the app plots a daily
series, so daily values are the day-on-day difference of the cumulative
columns. `admitted` is different in kind: it is a census of how many people are
on a ward that day, which the PDF reports directly.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

from .districts import DISTRICTS
from .fetch import fetch_pdf
from .parse import DailyReport, ParseError, parse_pdf
from .validation import validate_daily

LOG = logging.getLogger(__name__)

# Fallback annual totals, used only when the dashboard cannot be reached.
# The live figures come from DGHS's own year-by-year chart — see
# `dghs.dashboard`. Note DGHS publishes 2023 as 321,017 and 2024 as 101,211,
# which differ slightly from the figures widely quoted in press coverage.
FALLBACK_ANNUAL_HISTORY = [
    {"year": 2019, "cases": 101_354, "deaths": 179},
    {"year": 2020, "cases": 1_405, "deaths": 7},
    {"year": 2021, "cases": 28_429, "deaths": 105},
    {"year": 2022, "cases": 62_382, "deaths": 281},
    {"year": 2023, "cases": 321_179, "deaths": 1_705},
    {"year": 2024, "cases": 101_214, "deaths": 575},
    {"year": 2025, "cases": 102_861, "deaths": 413},
]

DISCLAIMER = (
    "Figures are compiled from the Directorate General of Health Services "
    "(DGHS) daily dengue press releases. They count patients reported by "
    "hospitals, so they undercount anyone who never sought hospital care."
)
ATTRIBUTION = (
    "Source: DGHS Health Emergency Operation Center & Control Room, daily "
    "dengue press release (old.dghs.gov.bd)."
)


@dataclass
class BuildResult:
    payload: dict
    days_used: int
    days_missing: int
    # DGHS occasionally revises a district's cumulative figure downward. A daily
    # series cannot carry a negative count, so the drop is clamped to zero,
    # which leaves the district series summing slightly high. Both the count and
    # the exact magnitude are recorded so the discrepancy can be asserted rather
    # than tolerated.
    downward_revisions: int = 0
    revision_total: int = 0


@dataclass
class CollectionOutcome:
    reports: list[DailyReport]
    rejected: int = 0
    anomalies: int = 0


def collect_reports(start: date, end: date, cache_dir: Path) -> CollectionOutcome:
    """Fetch, parse and validate every published report in the range.

    Validation runs here rather than at write time so a bad record never
    reaches the series in the first place. Hard failures drop the day;
    anomalies (a genuine outbreak spike) are kept and counted.
    """
    reports: list[DailyReport] = []
    rejected = 0
    anomalies = 0
    previous: DailyReport | None = None

    day = start
    while day <= end:
        path = fetch_pdf(day, cache_dir)
        if path is not None:
            try:
                report = parse_pdf(path, day)
            except ParseError as exc:
                # One malformed day must not poison the series; skip it loudly.
                LOG.error("%s: skipped — %s", day, exc)
                day += timedelta(days=1)
                continue

            if previous is None:
                # The first report in a window has no predecessor, so there is
                # no daily delta to judge — its figure is a cumulative baseline.
                # Checking it as if it were one day's cases rejects the whole
                # season (38,280 "in a day"), which is how this went wrong once.
                result = validate_daily(
                    report.report_date,
                    cases=0,
                    deaths=0,
                    cumulative=report.national_cases,
                )
            else:
                result = validate_daily(
                    report.report_date,
                    cases=report.national_cases - previous.national_cases,
                    deaths=report.national_deaths - previous.national_deaths,
                    previous_date=previous.report_date,
                    previous_cumulative=previous.national_cases,
                    cumulative=report.national_cases,
                )

            for finding in result.anomalies:
                anomalies += 1
                LOG.warning("%s: anomaly — %s (%s)", day, finding.code, finding.detail)

            if not result.ok:
                rejected += 1
                for finding in result.rejections:
                    LOG.error("%s: rejected — %s (%s)", day, finding.code, finding.detail)
                # The report still parsed and reconciled, so its cumulative
                # remains a valid baseline for the next day. Not advancing here
                # made one rejection cascade into rejecting every later day.
                previous = report
                day += timedelta(days=1)
                continue

            reports.append(report)
            previous = report
        day += timedelta(days=1)

    return CollectionOutcome(reports=reports, rejected=rejected, anomalies=anomalies)


def build_payload(reports: list[DailyReport], year: int,
                  annual_history: list[dict] | None = None) -> BuildResult:
    if not reports:
        raise ValueError("no usable reports — refusing to emit an empty dataset")

    reports = sorted(reports, key=lambda r: r.report_date)
    codes = [d["code"] for d in DISTRICTS]

    dates: list[str] = []
    national_cases: list[int] = []
    national_deaths: list[int] = []
    national_admitted: list[int] = []
    district_cases: dict[str, list[int]] = {c: [] for c in codes}
    district_deaths: dict[str, list[int]] = {c: [] for c in codes}

    # DGHS omits districts with no cases yet, so a district can vanish from the
    # table and reappear later. Carrying its last known cumulative forward stops
    # that reappearance registering as a huge one-day spike.
    last_cumulative: dict[str, int] = {c: 0 for c in codes}
    last_deaths: dict[str, int] = {c: 0 for c in codes}

    downward_revisions = 0
    revision_total = 0

    previous: DailyReport | None = None
    for report in reports:
        dates.append(report.report_date.isoformat())

        if previous is None:
            # Seed the series with the first day's cumulative, so that summing
            # the daily series reproduces the season total exactly. The app
            # derives "cases this season" that way, and it must not disagree
            # with the season figure shown in the history card.
            #
            # Starting from 1 January this is a handful of cases and invisible
            # on the chart. Starting mid-season it would be a tall first bar —
            # which is why the CLI refuses partial seasons by default.
            national_cases.append(report.national_cases)
            national_deaths.append(report.national_deaths)
            for code in codes:
                record = report.districts.get(code)
                cumulative = record.cumulative_cases if record else 0
                deaths = record.deaths if record else 0
                district_cases[code].append(cumulative)
                district_deaths[code].append(deaths)
                last_cumulative[code] = cumulative
                last_deaths[code] = deaths
        else:
            national_cases.append(max(0, report.national_cases - previous.national_cases))
            national_deaths.append(max(0, report.national_deaths - previous.national_deaths))
            for code in codes:
                record = report.districts.get(code)
                # Absent from today's table means "no cases reported yet", not
                # "reset to zero" — hold the previous cumulative.
                cumulative = record.cumulative_cases if record else last_cumulative[code]
                deaths = record.deaths if record else last_deaths[code]
                delta = cumulative - last_cumulative[code]
                if delta < 0:
                    downward_revisions += 1
                    revision_total += -delta
                    LOG.debug("%s %s: cumulative revised down by %d",
                              report.report_date, code, -delta)
                district_cases[code].append(max(0, delta))
                district_deaths[code].append(max(0, deaths - last_deaths[code]))
                last_cumulative[code] = cumulative
                last_deaths[code] = deaths

        national_admitted.append(report.total_currently_admitted)
        previous = report

    latest = reports[-1]
    history = [dict(entry, verified=True)
               for entry in (annual_history or FALLBACK_ANNUAL_HISTORY)
               if entry["year"] < year]
    history.append({
        "year": year,
        "cases": latest.national_cases,
        "deaths": latest.national_deaths,
        "verified": True,
    })

    payload = {
        "meta": {
            "datasetName": f"DGHS daily dengue press releases, {year} season",
            "isSampleData": False,
            "disclaimer": DISCLAIMER,
            "attribution": ATTRIBUTION,
            "seasonStart": dates[0],
            "lastUpdated": dates[-1],
            "year": year,
        },
        "dates": dates,
        "national": {
            "cases": national_cases,
            "deaths": national_deaths,
            "admitted": national_admitted,
        },
        "districts": [
            {
                **meta,
                "cases": district_cases[meta["code"]],
                "deaths": district_deaths[meta["code"]],
            }
            for meta in DISTRICTS
        ],
        "history": history,
    }

    span = (reports[-1].report_date - reports[0].report_date).days + 1
    return BuildResult(
        payload,
        days_used=len(reports),
        days_missing=span - len(reports),
        downward_revisions=downward_revisions,
        revision_total=revision_total,
    )
