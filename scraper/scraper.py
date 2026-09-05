"""DGHS dengue ingestion into Supabase.

    python scraper/scraper.py                 # today
    python scraper/scraper.py --date 2026-09-04
    python scraper/scraper.py --dry-run       # parse and validate, write nothing

Two strategies, in order:

  1. The DGHS dashboard. Its figures are arguments to Highcharts.chart()
     calls, not DOM text, so they are read from the embedded JavaScript.
  2. The daily press-release PDF, when the dashboard has not moved on.

This module deliberately contains no parser of its own. `server/dghs/` already
parses both surfaces, is covered by 53 tests, and identifies every chart series
by its Highcharts container id and series name rather than by position — an
earlier version keyed on position and reported 41,891 deaths in one month when
DGHS reordered its charts. A second parser here would be a second thing to
keep correct, and the two would drift apart silently.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import requests
from bs4 import BeautifulSoup
from pydantic import BaseModel, Field, NonNegativeInt, ValidationError, model_validator

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "server"))

from dghs.dashboard import DASHBOARD_URL, DGHSDashboardSource  # noqa: E402
from dghs.fetch import USER_AGENT  # noqa: E402
from dghs.source import DGHSSourceError  # noqa: E402

LOG = logging.getLogger("dghs-ingest")
DHAKA = timezone(timedelta(hours=6))

PRESS_RELEASE_INDEX = "https://old.dghs.gov.bd/index.php/bd/home/5200-daily-dengue-status-report"
REQUEST_TIMEOUT = 45
SURGE_THRESHOLD = 0.20  # a >20% day-on-day rise raises a surge alert


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

class RegionalBreakdown(BaseModel):
    """One district's figures for one reporting day."""
    division_name: str | None = None
    district_name: str = Field(min_length=1, max_length=64)
    cases_24h: NonNegativeInt = 0
    deaths_24h: NonNegativeInt = 0


class DailySummary(BaseModel):
    """A DGHS reporting day.

    Optional fields stay None when DGHS did not publish them. They are never
    defaulted to zero: a missing figure and a genuine zero mean different
    things, and conflating them would let a parser failure read as "no cases".
    """
    report_date: date
    total_cases_24h: NonNegativeInt
    total_deaths_24h: NonNegativeInt
    total_cases_ytd: NonNegativeInt | None = None
    total_deaths_ytd: NonNegativeInt | None = None
    dhaka_city_cases_24h: NonNegativeInt | None = None
    outside_dhaka_cases_24h: NonNegativeInt | None = None
    regional_breakdowns: list[RegionalBreakdown] = Field(default_factory=list)
    primary_source: str = "DGHS dashboard"

    @model_validator(mode="after")
    def _sanity(self) -> "DailySummary":
        if self.report_date > datetime.now(DHAKA).date():
            raise ValueError(f"report_date {self.report_date} is in the future")
        if self.total_cases_ytd is not None and self.total_cases_ytd < self.total_cases_24h:
            raise ValueError("year-to-date cases are below the 24-hour figure")
        if self.total_deaths_ytd is not None and self.total_deaths_ytd < self.total_deaths_24h:
            raise ValueError("year-to-date deaths are below the 24-hour figure")

        split = [v for v in (self.dhaka_city_cases_24h, self.outside_dhaka_cases_24h)
                 if v is not None]
        if len(split) == 2 and sum(split) != self.total_cases_24h:
            raise ValueError(
                f"Dhaka {self.dhaka_city_cases_24h} + outside "
                f"{self.outside_dhaka_cases_24h} != total {self.total_cases_24h}")

        # A single district cannot out-report the whole country in the same
        # 24 hours. This exists because the first version of the dashboard
        # strategy mapped the division chart's cumulative season totals into
        # cases_24h, and Barishal came through as 6,379 against a national
        # 988 — wrong by three orders of magnitude and completely plausible
        # looking in a database. Anything that mixes a cumulative figure into
        # a daily column trips this.
        for region in self.regional_breakdowns:
            if region.cases_24h > self.total_cases_24h:
                raise ValueError(
                    f"{region.district_name} reports {region.cases_24h} cases in 24h "
                    f"but the national total is {self.total_cases_24h} — "
                    f"a cumulative figure has probably been read as a daily one")
            if region.deaths_24h > self.total_deaths_24h:
                raise ValueError(
                    f"{region.district_name} reports {region.deaths_24h} deaths in 24h "
                    f"but the national total is {self.total_deaths_24h}")

        names = [r.district_name for r in self.regional_breakdowns]
        if len(names) != len(set(names)):
            duplicates = sorted({n for n in names if names.count(n) > 1})
            raise ValueError(f"duplicate districts: {duplicates}")
        return self

    def to_row(self) -> dict[str, Any]:
        return {
            "report_date": self.report_date.isoformat(),
            "total_cases_24h": self.total_cases_24h,
            "total_deaths_24h": self.total_deaths_24h,
            "total_cases_ytd": self.total_cases_ytd,
            "total_deaths_ytd": self.total_deaths_ytd,
            "dhaka_city_cases_24h": self.dhaka_city_cases_24h,
            "outside_dhaka_cases_24h": self.outside_dhaka_cases_24h,
        }

    def to_regional_rows(self) -> list[dict[str, Any]]:
        return [
            {
                "report_date": self.report_date.isoformat(),
                "division_name": r.division_name,
                "district_name": r.district_name,
                "cases_24h": r.cases_24h,
                "deaths_24h": r.deaths_24h,
            }
            for r in self.regional_breakdowns
        ]


# ---------------------------------------------------------------------------
# Strategy 1 — the dashboard
# ---------------------------------------------------------------------------

def scrape_dashboard() -> DailySummary:
    """Parse the DGHS dashboard through the pipeline's own parser."""
    LOG.info("[DGHS] Fetching official dashboard...")
    snapshot = DGHSDashboardSource().fetch()
    national = snapshot.national

    if national.report_date is None:
        raise DGHSSourceError("dashboard carries no reporting date")
    if national.cases_24h is None or national.deaths_24h is None:
        raise DGHSSourceError("dashboard is missing the 24-hour figures")

    # The dashboard's per-division series are cumulative season totals, not
    # 24-hour counts, so nothing here can fill regional_breakdowns without
    # mislabelling it. Daily per-district figures exist only in the press
    # release, which the fallback strategy parses. Leaving this empty is the
    # honest outcome: a caller can tell "no regional detail today" from a
    # wrong number, but not from a wrong number presented as right.
    regions: list[RegionalBreakdown] = []

    LOG.info("[DGHS] Parsed reporting date: %s", national.report_date)
    LOG.info("[DGHS] Parsed daily cases: %s, deaths: %s",
             national.cases_24h, national.deaths_24h)

    return DailySummary(
        report_date=national.report_date,
        total_cases_24h=national.cases_24h,
        total_deaths_24h=national.deaths_24h,
        total_cases_ytd=national.total_cases,
        total_deaths_ytd=national.total_deaths,
        regional_breakdowns=regions,
        primary_source="DGHS dashboard",
    )


# ---------------------------------------------------------------------------
# Strategy 2 — the press-release PDF
# ---------------------------------------------------------------------------

def find_latest_press_release(session: requests.Session) -> str | None:
    """Find the newest press-release PDF link.

    This is the one place BeautifulSoup earns its place: the link really is an
    <a href> in the DOM, unlike the dashboard figures.
    """
    try:
        response = session.get(PRESS_RELEASE_INDEX, timeout=REQUEST_TIMEOUT)
        response.raise_for_status()
    except requests.RequestException as exc:
        LOG.warning("[DGHS] Press-release index unreachable: %s", exc)
        return None

    soup = BeautifulSoup(response.text, "html.parser")
    for anchor in soup.find_all("a", href=True):
        href = anchor["href"]
        if href.lower().endswith(".pdf") and "dengue" in href.lower():
            return href if href.startswith("http") else f"https://old.dghs.gov.bd{href}"
    return None


def scrape_press_release(day: date) -> DailySummary:
    """Parse the daily press release for `day` using the existing PDF parser."""
    from dghs.fetch import fetch_report  # imported late: pdfplumber is heavy
    from dghs.parse import parse_report

    LOG.info("[DGHS] Falling back to the press release for %s", day)
    raw = fetch_report(day)
    if raw is None:
        raise DGHSSourceError(f"no press release published for {day}")

    report = parse_report(raw, day)
    regions = [
        RegionalBreakdown(
            division_name=getattr(d, "division", None),
            district_name=d.name,
            cases_24h=max(0, d.cases or 0),
            deaths_24h=max(0, d.deaths or 0),
        )
        for d in getattr(report, "districts", [])
    ]
    return DailySummary(
        report_date=report.report_date,
        total_cases_24h=report.national_cases,
        total_deaths_24h=report.national_deaths,
        regional_breakdowns=regions,
        primary_source="DGHS daily report",
    )


# ---------------------------------------------------------------------------
# Supabase
# ---------------------------------------------------------------------------

class Supabase:
    """Thin PostgREST client. Avoids a dependency for four HTTP calls."""

    def __init__(self, url: str, service_key: str) -> None:
        self.rest = url.rstrip("/") + "/rest/v1"
        self.session = requests.Session()
        self.session.headers.update({
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        })

    def upsert(self, table: str, rows: list[dict[str, Any]], on_conflict: str) -> None:
        if not rows:
            return
        response = self.session.post(
            f"{self.rest}/{table}",
            params={"on_conflict": on_conflict},
            headers={"Prefer": "resolution=merge-duplicates,return=minimal"},
            data=json.dumps(rows),
            timeout=REQUEST_TIMEOUT,
        )
        if response.status_code >= 400:
            raise RuntimeError(f"{table} upsert failed: HTTP {response.status_code} {response.text[:300]}")

    def previous_summary(self, before: date) -> dict[str, Any] | None:
        response = self.session.get(
            f"{self.rest}/daily_summaries",
            params={
                "select": "report_date,total_cases_24h",
                "report_date": f"lt.{before.isoformat()}",
                "order": "report_date.desc",
                "limit": 1,
            },
            timeout=REQUEST_TIMEOUT,
        )
        response.raise_for_status()
        rows = response.json()
        return rows[0] if rows else None


# ---------------------------------------------------------------------------
# Surge detection
# ---------------------------------------------------------------------------

def surge_alert(summary: DailySummary, previous: dict[str, Any] | None) -> dict[str, Any] | None:
    """An APNs payload when cases jump more than SURGE_THRESHOLD day on day.

    Returned, not sent. Pushing needs an APNs key this job has no business
    holding, and a data pipeline that can also message every user is a larger
    blast radius than it needs.
    """
    if not previous:
        return None
    before = previous.get("total_cases_24h") or 0
    if before <= 0:
        return None

    change = (summary.total_cases_24h - before) / before
    if change <= SURGE_THRESHOLD:
        return None

    LOG.warning("[DGHS] Surge: %s -> %s cases (+%.0f%%)",
                before, summary.total_cases_24h, change * 100)
    return {
        "aps": {
            "alert": {
                "title-loc-key": "surge.title",
                "loc-key": "surge.body",
                "loc-args": [f"{change * 100:.0f}", f"{summary.total_cases_24h:,}"],
            },
            "sound": "default",
            "interruption-level": "time-sensitive",
        },
        "reportDate": summary.report_date.isoformat(),
        "totalCases24h": summary.total_cases_24h,
        "previousCases24h": before,
        "percentChange": round(change * 100, 1),
    }


# ---------------------------------------------------------------------------
# Pipeline
# ---------------------------------------------------------------------------

def ingest(day: date, dry_run: bool = False) -> int:
    try:
        summary = scrape_dashboard()
        if summary.report_date < day - timedelta(days=1):
            LOG.info("[DGHS] Dashboard is as of %s, older than expected",
                     summary.report_date)
            raise DGHSSourceError("dashboard has not updated")
    except (DGHSSourceError, ValidationError, requests.RequestException) as exc:
        LOG.warning("[DGHS] Dashboard strategy failed: %s", exc)
        try:
            summary = scrape_press_release(day)
        except Exception as fallback_exc:  # noqa: BLE001 - reported, not swallowed
            LOG.error("[DGHS] Both strategies failed. Dashboard: %s. Press release: %s",
                      exc, fallback_exc)
            return 1

    LOG.info("[DGHS] Validation passed — %d regional rows, source: %s",
             len(summary.regional_breakdowns), summary.primary_source)

    if dry_run:
        LOG.info("[DGHS] Dry run — nothing written")
        print(json.dumps(summary.model_dump(mode="json"), indent=2)[:1200])
        return 0

    url, key = os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_SERVICE_KEY")
    if not url or not key:
        LOG.error("[DGHS] SUPABASE_URL and SUPABASE_SERVICE_KEY must be set")
        return 1

    client = Supabase(url, key)
    previous = client.previous_summary(summary.report_date)

    client.upsert("daily_summaries", [summary.to_row()], on_conflict="report_date")
    client.upsert("regional_breakdowns", summary.to_regional_rows(),
                  on_conflict="report_date,district_name")
    LOG.info("[DGHS] Publishing new dataset")

    alert = surge_alert(summary, previous)
    if alert:
        Path("surge-alert.json").write_text(json.dumps(alert, indent=2), encoding="utf-8")
        LOG.info("[DGHS] Surge payload written to surge-alert.json")

    LOG.info("[DGHS] Success")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--date", type=lambda s: datetime.strptime(s, "%Y-%m-%d").date(),
                        default=datetime.now(DHAKA).date())
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(message)s",
    )
    return ingest(args.date, dry_run=args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
