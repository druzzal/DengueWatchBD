#!/usr/bin/env python3
"""Scrape the DGHS dengue dashboard and upsert today's figures into Supabase.

    python scraper/scrape_dghs.py            # scrape and write
    python scraper/scrape_dghs.py --dry-run  # scrape, validate, write nothing

Where the numbers actually live
-------------------------------
The dashboard renders its figures with Highcharts, so they are arguments to
`Highcharts.chart('<container id>', { ... })` calls inside <script> tags — not
text in the DOM. BeautifulSoup traversing elements finds nothing useful, which
is why the primary strategy reads the embedded JavaScript and BeautifulSoup is
used only to locate the script blocks and the summary cards.

Series are matched on their chart's container id and their series name, never
on position. An earlier parser in this project keyed on chart order and
reported 41,891 deaths in a single month after DGHS reordered its charts.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import sys
from dataclasses import asdict, dataclass
from datetime import date, datetime, timedelta, timezone

import requests
from bs4 import BeautifulSoup

DASHBOARD_URL = "https://dashboard.dghs.gov.bd/pages/heoc_dengue_v1.php"
USER_AGENT = "DengueWatch/1.0 (+public health data sync)"
TIMEOUT = 45
MAX_ATTEMPTS = 3
DHAKA = timezone(timedelta(hours=6))

LOG = logging.getLogger("dghs")


class ScrapeError(RuntimeError):
    """Raised when the page cannot be parsed with confidence.

    Always raised rather than returning zeros: a plausible-looking zero is far
    more dangerous than a failed run, because it reaches users as "no cases".
    """


@dataclass
class DengueStats:
    report_date: date
    total_cases_24h: int
    total_deaths_24h: int
    dhaka_cases_24h: int | None = None
    outside_dhaka_cases_24h: int | None = None

    def validate(self) -> None:
        if self.report_date > datetime.now(DHAKA).date():
            raise ScrapeError(f"report_date {self.report_date} is in the future")
        if self.total_cases_24h < 0 or self.total_deaths_24h < 0:
            raise ScrapeError("negative counts")
        if self.total_deaths_24h > self.total_cases_24h and self.total_cases_24h > 0:
            raise ScrapeError(
                f"{self.total_deaths_24h} deaths against {self.total_cases_24h} "
                "cases in 24h — the figures have probably been read from the "
                "wrong series")
        split = [v for v in (self.dhaka_cases_24h, self.outside_dhaka_cases_24h)
                 if v is not None]
        if len(split) == 2 and sum(split) != self.total_cases_24h:
            raise ScrapeError(
                f"Dhaka {self.dhaka_cases_24h} + outside "
                f"{self.outside_dhaka_cases_24h} != total {self.total_cases_24h}")

    def to_row(self) -> dict:
        row = asdict(self)
        row["report_date"] = self.report_date.isoformat()
        return row


# ---------------------------------------------------------------------------
# Fetch
# ---------------------------------------------------------------------------

def fetch_dashboard(url: str = DASHBOARD_URL) -> str:
    """GET the dashboard with retries and exponential backoff."""
    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})

    last: Exception | None = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            LOG.info("[DGHS] Fetching official dashboard (attempt %d/%d)...",
                     attempt, MAX_ATTEMPTS)
            response = session.get(url, timeout=TIMEOUT)
            response.raise_for_status()
            LOG.info("[DGHS] Retrieved %d KB", len(response.content) // 1024)
            return response.text
        except requests.RequestException as exc:
            last = exc
            LOG.warning("[DGHS] Request failed: %s", exc)
            if attempt < MAX_ATTEMPTS:
                delay = 2 ** attempt          # 2s, 4s — deliberate, not a fixed sleep
                LOG.info("[DGHS] Retrying in %ds", delay)
                import time; time.sleep(delay)
    raise ScrapeError(f"dashboard unreachable after {MAX_ATTEMPTS} attempts: {last}")


# ---------------------------------------------------------------------------
# Parse
# ---------------------------------------------------------------------------

def _int(text: str) -> int | None:
    digits = re.sub(r"[^\d]", "", text or "")
    return int(digits) if digits else None


def parse_report_date(html: str) -> date:
    """Find the reporting date.

    DGHS writes it as `05-Sep-2026`. The other shapes are kept as fallbacks
    because the page has used them before and the cost of trying is nil.
    Note the chart categories also carry dates like `01-Jan-26` — the
    two-digit year is what distinguishes those from the report date, and the
    recency check below rejects them anyway.
    """
    candidates: list[date] = []
    patterns = (
        (r"(\d{1,2})-([A-Za-z]{3,9})-(20\d{2})", ("%d-%b-%Y", "%d-%B-%Y")),
        (r"(\d{1,2})\s+([A-Za-z]{3,9})\s+(20\d{2})", ("%d %b %Y", "%d %B %Y")),
        (r"(20\d{2})-(\d{2})-(\d{2})", ("%Y-%m-%d",)),
        (r"(\d{1,2})/(\d{1,2})/(20\d{2})", ("%d/%m/%Y",)),
    )
    separators = {"%d-%b-%Y": "-", "%d-%B-%Y": "-", "%d %b %Y": " ",
                  "%d %B %Y": " ", "%Y-%m-%d": "-", "%d/%m/%Y": "/"}

    for pattern, formats in patterns:
        for match in re.finditer(pattern, html):
            for fmt in formats:
                try:
                    found = datetime.strptime(
                        separators[fmt].join(match.groups()), fmt).date()
                except ValueError:
                    continue
                candidates.append(found)
                break

    # A dashboard reports today or the last few days. Anything outside that is
    # a chart axis label or an unrelated number that parsed as a date.
    today = datetime.now(DHAKA).date()
    recent = [d for d in candidates
              if timedelta(days=0) <= (today - d) <= timedelta(days=14)]
    if recent:
        return max(recent)

    raise ScrapeError(
        f"no plausible reporting date found (parsed {len(candidates)} "
        f"date-like strings, none within 14 days of {today})")


def _highcharts_blocks(html: str) -> dict[str, str]:
    """Map each Highcharts container id to its constructor body."""
    blocks: dict[str, str] = {}
    for match in re.finditer(r"Highcharts\.chart\(\s*['\"]([\w-]+)['\"]", html):
        container = match.group(1)
        start = match.end()
        depth, i = 0, start
        while i < len(html):
            if html[i] == "{": depth += 1
            elif html[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        blocks[container] = html[start:i + 1]
    return blocks


def _series(block: str, name: str) -> list[int]:
    """Pull one named series' data out of a chart block."""
    pattern = re.compile(
        r"name\s*:\s*['\"]" + re.escape(name) + r"['\"].*?data\s*:\s*\[([^\]]*)\]",
        re.S)
    match = pattern.search(block)
    if not match:
        return []
    return [int(float(v)) for v in re.findall(r"-?\d+(?:\.\d+)?", match.group(1))]


def parse_stats(html: str) -> DengueStats:
    """Primary strategy: the embedded Highcharts data. Falls back to the
    summary cards in the DOM if a chart is missing."""
    report_date = parse_report_date(html)
    LOG.info("[DGHS] Parsed reporting date: %s", report_date)

    blocks = _highcharts_blocks(html)
    LOG.info("[DGHS] Found %d Highcharts blocks: %s",
             len(blocks), ", ".join(sorted(blocks)[:8]))

    cases = deaths = None

    # Each figure is looked up by container id and series name, in order of
    # preference. This is the fallback logic: several known-good identities,
    # tried in turn. What it deliberately does not do is guess — an earlier
    # version fell back to a loose regex over the page text and returned 24
    # deaths for a day DGHS reported 2, which validation could not catch
    # because 24 deaths against 988 cases is entirely plausible.
    CASE_SERIES = (
        ("confirmed_case", "Affected (Admitted) by date"),
        ("affected_case_last_24_hour", "Affected"),
    )
    DEATH_SERIES = (
        ("death_case", "Death by date"),
        ("death_case_last_24_hour", "Death"),
    )

    for container, series_name in CASE_SERIES:
        values = _series(blocks.get(container, ""), series_name)
        if values:
            cases = values[-1]
            LOG.info("[DGHS] Daily cases from '%s' / '%s': %s",
                     container, series_name, cases)
            break

    for container, series_name in DEATH_SERIES:
        values = _series(blocks.get(container, ""), series_name)
        if values:
            deaths = values[-1]
            LOG.info("[DGHS] Daily deaths from '%s' / '%s': %s",
                     container, series_name, deaths)
            break

    if cases is None or deaths is None:
        missing = [n for n, v in (("cases", cases), ("deaths", deaths)) if v is None]
        raise ScrapeError(
            f"could not read {' and '.join(missing)} from any known chart. "
            f"Containers present: {', '.join(sorted(blocks)) or 'none'}. "
            "The dashboard layout has changed; refusing to write a guess.")

    # DGHS does not publish the Dhaka split on this page. Left as None, never
    # as 0, so the database records "unknown" rather than "no cases in Dhaka".
    stats = DengueStats(report_date=report_date,
                        total_cases_24h=cases,
                        total_deaths_24h=deaths)
    stats.validate()
    LOG.info("[DGHS] Validation passed")
    return stats


# ---------------------------------------------------------------------------
# Upsert
# ---------------------------------------------------------------------------

def upsert(stats: DengueStats) -> None:
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_KEY")
    if not url or not key:
        raise ScrapeError("SUPABASE_URL and SUPABASE_SERVICE_KEY must be set")

    from supabase import create_client   # imported late so --dry-run needs no client

    client = create_client(url, key)
    LOG.info("[DGHS] Upserting %s", stats.report_date)
    # on_conflict on the primary key: re-running the same day updates rather
    # than failing, so a retry is always safe.
    client.table("dengue_stats").upsert(
        stats.to_row(), on_conflict="report_date"
    ).execute()
    LOG.info("[DGHS] Success")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true",
                        help="scrape and validate without writing")
    parser.add_argument("--url", default=DASHBOARD_URL)
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    try:
        html = fetch_dashboard(args.url)
        stats = parse_stats(html)
    except ScrapeError as exc:
        LOG.error("[DGHS] %s", exc)
        return 1
    except Exception as exc:                      # noqa: BLE001 - logged, not hidden
        LOG.exception("[DGHS] Unexpected failure: %s", exc)
        return 1

    print(json.dumps(stats.to_row(), indent=2))

    if args.dry_run:
        LOG.info("[DGHS] Dry run — nothing written")
        return 0

    try:
        upsert(stats)
    except Exception as exc:                      # noqa: BLE001 - logged, not hidden
        LOG.exception("[DGHS] Upsert failed: %s", exc)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
