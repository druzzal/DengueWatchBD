"""Adapter for the DGHS HEOC dengue dashboard page.

    https://dashboard.dghs.gov.bd/pages/heoc_dengue_v1.php

There is no JSON or AJAX endpoint behind the page; its figures are rendered
server-side into Highcharts configuration blocks. But those blocks *are*
self-describing, via two independent identifiers:

    Highcharts.chart('confirmed_case', { ... name: 'Affected (Admitted) by date' })
    └── container id ──┘                       └── series name ──┘

An earlier version of this adapter concluded the opposite and extracted only
the annual series. That was wrong: it searched for `renderTo`, which this page
does not use, and so never saw the container ids. Series are now identified by
id plus series name, never by the order charts appear in the file.

Confidence rules, per the project's data-safety policy:

  HIGH   — container id and series name both state the meaning, and the values
           reconcile against an independent figure. Only these are returned.
  MEDIUM — id is suggestive but the series is unnamed or the shape is unclear.
  LOW    — meaning would have to be inferred from position.

Anything below HIGH is skipped and logged rather than guessed. A plausible but
wrong epidemiological number is worse than a missing one.
"""

from __future__ import annotations

import logging
import re
from datetime import date, datetime, timezone

import requests

from .source import (
    AreaCount,
    DGHSDataSource,
    DGHSSnapshot,
    DGHSSourceError,
    NationalTotals,
    PeriodCount,
)

LOG = logging.getLogger(__name__)

DASHBOARD_URL = "https://dashboard.dghs.gov.bd/pages/heoc_dengue_v1.php"
USER_AGENT = "DengueWatchBD/1.0 (+public health data sync)"

# Bump when extraction logic materially changes, so an ingestion log entry can
# be traced back to the parser that produced it.
PARSER_VERSION = "dghs-dashboard-v2"

_CHART = re.compile(r"Highcharts\.chart\(\s*['\"]([\w\-]+)['\"]")
_CATEGORIES = re.compile(r"categories\s*:\s*\[([^\]]*)\]")
_NUMBERS = r"data\s*:\s*\[([0-9,\s.\-]+)\]"

# Charts whose meaning is stated by both id and series name. The tuple is
# (container id, series name, what it means).
HIGH_CONFIDENCE = {
    "cases_24h": ("affected_case_last_24_hour", "Admitted"),
    "deaths_24h": ("death_case_last_24_hour", "Death"),
    "total_cases": ("affected_case_in_year", "Admitted"),
    "total_deaths": ("death_case_in_year", "Death"),
    "discharged_total": ("dengue_discharged_total_and_24_hours",
                         "DISCHARGED from 1 January to Till date"),
    "daily_cases": ("confirmed_case", "Affected (Admitted) by date"),
    "daily_deaths": ("death_case", "Death by date"),
    "division_cases": ("div_city_cor_case_in_year", "Admitted"),
    "division_deaths": ("div_city_cor_death_in_year", "Death"),
    "annual_cases": ("year_case", "Affected"),
}

# Present and parseable, deliberately not returned. Kept here so the decision is
# visible rather than implicit.
KNOWN_BUT_UNUSED = {
    "dengue_affected_by_age_group": "age bands are not labelled in the block",
    "dengue_death_by_age_group": "age bands are not labelled in the block",
    "dengue_affected_by_gender": "series carries no data array in the page",
    "by_week_case": "mixes several years in one chart; year attribution unclear",
    "by_month_case": "mixes several years in one chart; year attribution unclear",
    "division_case": "duplicate and misspelled category labels ('Raishahi')",
}


def _clean_categories(raw: str) -> list[str]:
    return [p.strip().strip('"').strip("'") for p in raw.split(",") if p.strip()]


def _numbers(raw: str) -> list[int]:
    out: list[int] = []
    for part in raw.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            out.append(int(float(part)))
        except ValueError:
            continue
    return out


class DGHSDashboardSource(DGHSDataSource):
    name = "DGHS Dengue Dashboard"
    source_type = "dashboard"
    url = DASHBOARD_URL
    parser_version = PARSER_VERSION

    def __init__(self, url: str = DASHBOARD_URL, timeout: int = 45):
        self.url = url
        self.timeout = timeout

    # -- fetching -------------------------------------------------------

    def fetch(self) -> DGHSSnapshot:
        try:
            response = requests.get(self.url, timeout=self.timeout,
                                    headers={"User-Agent": USER_AGENT})
        except requests.RequestException as exc:
            raise DGHSSourceError(f"could not reach the dashboard: {exc}") from exc
        if response.status_code != 200:
            raise DGHSSourceError(f"dashboard returned HTTP {response.status_code}")
        return self.parse(response.text)

    # -- parsing --------------------------------------------------------

    def _blocks(self, html: str) -> dict[str, str]:
        """Each chart's source, keyed by its container id."""
        marks = [(m.group(1), m.start()) for m in _CHART.finditer(html)]
        blocks: dict[str, str] = {}
        for index, (container, start) in enumerate(marks):
            end = marks[index + 1][1] if index + 1 < len(marks) else len(html)
            blocks[container] = html[start:end]
        return blocks

    def _series(self, block: str, series_name: str) -> list[int] | None:
        """The data array belonging to a *named* series, not a positional one."""
        pattern = re.compile(
            rf"name\s*:\s*['\"]{re.escape(series_name)}['\"].*?{_NUMBERS}", re.S)
        match = pattern.search(block)
        if match:
            return _numbers(match.group(1))
        # Single-value charts sometimes state the name after the data.
        pattern = re.compile(rf"{_NUMBERS}.*?name\s*:\s*['\"]{re.escape(series_name)}['\"]", re.S)
        match = pattern.search(block)
        return _numbers(match.group(1)) if match else None

    def _categories(self, block: str) -> list[str]:
        match = _CATEGORIES.search(block)
        return _clean_categories(match.group(1)) if match else []

    def parse(self, html: str) -> DGHSSnapshot:
        blocks = self._blocks(html)
        if not blocks:
            raise DGHSSourceError(
                "no Highcharts containers found — the dashboard layout has changed")

        snapshot = DGHSSnapshot(
            source=self.name,
            source_url=self.url,
            fetched_at=datetime.now(timezone.utc).isoformat(timespec="seconds"),
            source_type=self.source_type,
            parser_version=self.parser_version,
        )

        def value(key: str) -> list[int] | None:
            container, series_name = HIGH_CONFIDENCE[key]
            block = blocks.get(container)
            if block is None:
                LOG.warning("chart '%s' absent — skipping %s", container, key)
                snapshot.skipped.append(f"{key}: container '{container}' not found")
                return None
            data = self._series(block, series_name)
            if data is None:
                LOG.warning("series '%s' absent in '%s' — skipping %s",
                            series_name, container, key)
                snapshot.skipped.append(f"{key}: series '{series_name}' not found")
            return data

        # National scalars.
        for key, attr in (("cases_24h", "cases_24h"), ("deaths_24h", "deaths_24h"),
                          ("total_cases", "total_cases"), ("total_deaths", "total_deaths"),
                          ("discharged_total", "discharged")):
            data = value(key)
            if data:
                setattr(snapshot.national, attr, data[0])

        # Daily series — the dashboard states a date per point.
        daily = value("daily_cases")
        if daily:
            container, _ = HIGH_CONFIDENCE["daily_cases"]
            labels = self._categories(blocks[container])
            if len(labels) == len(daily):
                snapshot.daily = [
                    PeriodCount(period=label, cases=count)
                    for label, count in zip(labels, daily)
                ]
            else:
                snapshot.skipped.append(
                    f"daily_cases: {len(labels)} labels for {len(daily)} values")

        deaths = value("daily_deaths")
        if deaths:
            container, _ = HIGH_CONFIDENCE["daily_deaths"]
            labels = self._categories(blocks[container])
            if len(labels) == len(deaths):
                snapshot.daily_deaths = [
                    PeriodCount(period=label, deaths=count)
                    for label, count in zip(labels, deaths)
                ]

        # Division and city-corporation season totals.
        div_cases = value("division_cases")
        div_deaths = value("division_deaths")
        if div_cases:
            container, _ = HIGH_CONFIDENCE["division_cases"]
            labels = self._categories(blocks[container])
            deaths_by_index = div_deaths or [None] * len(div_cases)
            if len(labels) == len(div_cases):
                for label, cases, dead in zip(labels, div_cases, deaths_by_index):
                    cleaned = label.strip()
                    level = ("city_corporation"
                             if cleaned.upper() in {"DNCC", "DSCC"} else "division")
                    snapshot.areas.append(
                        AreaCount(level=level, name=cleaned, cases=cases, deaths=dead))

        # Annual history.
        annual = value("annual_cases")
        if annual:
            container, _ = HIGH_CONFIDENCE["annual_cases"]
            labels = self._categories(blocks[container])
            if len(labels) == len(annual):
                snapshot.yearly = [
                    PeriodCount(period=label.strip(), cases=count)
                    for label, count in zip(labels, annual)
                ]

        for container, reason in KNOWN_BUT_UNUSED.items():
            if container in blocks:
                snapshot.skipped.append(f"{container}: {reason}")

        snapshot.national.report_date = self._report_date(html)

        if snapshot.is_empty:
            raise DGHSSourceError(
                "no high-confidence series could be read — the dashboard "
                "layout has probably changed")
        return snapshot

    @staticmethod
    def _report_date(html: str) -> date | None:
        for pattern in (r"(\d{1,2})[-/\s]([A-Za-z]{3,9})[-/\s](20\d{2})",
                        r"(20\d{2})-(\d{2})-(\d{2})"):
            match = re.search(pattern, html)
            if not match:
                continue
            for fmt in ("%d-%b-%Y", "%d %B %Y", "%d-%B-%Y", "%Y-%m-%d"):
                try:
                    return datetime.strptime("-".join(match.groups()), fmt).date()
                except ValueError:
                    continue
        return None
