"""Command line entry point.

    python -m dghs.cli --start 2026-01-01 --end 2026-09-02 --out surveillance.json

Writes atomically, and only after the payload passes its own sanity checks, so
a partial or nonsensical file is never published.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

from .build import build_payload, collect_reports
from .dashboard import DGHSDashboardSource
from .crosscheck import cross_check
from .runlog import IngestionRun, append_run, status_document
from .latest import build_latest
from .publish import decide, freshness, publish
from .source import DGHSSourceError

LOG = logging.getLogger("dghs")


def _parse_date(text: str) -> date:
    return datetime.strptime(text, "%Y-%m-%d").date()


def write_status(out: Path, runs_path: Path, latest_report_date: str | None) -> Path:
    """Write status.json beside the dataset.

    Called on both the publish and the no-change paths: a run that found
    nothing new still moves `lastSuccessfulIngestion` forward, and that is
    exactly how a reader tells "the source has not updated" apart from "the
    pipeline has stopped running".
    """
    status = status_document(runs_path, latest_report_date)
    status["freshness"] = freshness(latest_report_date)
    status_path = out.parent / "status.json"
    status_path.write_text(json.dumps(status, indent=1), encoding="utf-8")
    return status_path


def validate_payload(payload: dict, revision_total: int = 0) -> list[str]:
    """Cheap structural checks before anything is written."""
    problems: list[str] = []
    length = len(payload["dates"])
    if length == 0:
        problems.append("no dates")
    for key, series in payload["national"].items():
        if len(series) != length:
            problems.append(f"national.{key} has {len(series)} points, expected {length}")
    if len(payload["districts"]) != 64:
        problems.append(f"{len(payload['districts'])} districts, expected 64")
    for district in payload["districts"]:
        for key in ("cases", "deaths"):
            if len(district[key]) != length:
                problems.append(f"{district['code']}.{key} has {len(district[key])} points")
    # The district series sums high by exactly the downward revisions that were
    # clamped away — an exact identity, not a tolerance.
    total = sum(payload["national"]["cases"])
    district_total = sum(sum(d["cases"]) for d in payload["districts"])
    excess = district_total - total
    if excess != revision_total:
        problems.append(
            f"national daily cases sum to {total:,} and districts to "
            f"{district_total:,}, a difference of {excess:,}, but only "
            f"{revision_total:,} was clamped from downward revisions"
        )
    return problems


def check_season_coverage(payload: dict) -> str | None:
    """Is the daily series actually a whole season?

    The app derives "cases this season" by summing the daily series. DGHS
    publishes cumulative figures, so a window that starts in August yields a
    daily series summing to the August-onward total, and the app would show a
    season figure far below the real one. Catch that here rather than shipping
    a headline number that is quietly wrong.
    """
    reported = payload["history"][-1]["cases"]
    summed = sum(payload["national"]["cases"])
    if reported <= 0:
        return None
    shortfall = (reported - summed) / reported
    if shortfall > 0.02:
        return (
            f"the daily series sums to {summed:,} cases but the season total to date "
            f"is {reported:,}. The series starts on {payload['meta']['seasonStart']}, so "
            f"it is missing the earlier part of the year. Re-run with "
            f"--start {payload['meta']['year']}-01-01 to backfill the whole season, "
            f"or pass --allow-partial if a partial window is what you want."
        )
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start", type=_parse_date,
                        help="first day to include (default: 1 January of --year)")
    parser.add_argument("--end", type=_parse_date, default=date.today(),
                        help="last day to include (default: today). DGHS often "
                             "publishes the same day; a day that is not out yet "
                             "simply 404s and is retried on the next run.")
    parser.add_argument("--year", type=int, help="season year (default: year of --end)")
    parser.add_argument("--out", type=Path, default=Path("surveillance.json"))
    parser.add_argument("--cache", type=Path, default=Path(".cache"))
    parser.add_argument("--allow-partial", action="store_true",
                        help="emit a dataset whose daily series does not cover the "
                             "whole season (the app's season totals will be low)")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(message)s",
    )

    year = args.year or args.end.year
    start = args.start or date(year, 1, 1)
    if start > args.end:
        LOG.error("--start is after --end")
        return 2

    run = IngestionRun.start("DGHS", DGHSDashboardSource.url)
    runs_path = args.out.parent / "ingestion-runs.json"

    # The dashboard supplies the year-by-year history. If it is unreachable the
    # run continues on the fallback table rather than failing outright — the
    # daily figures matter more than the history strip.
    annual_history: list[dict] | None = None
    snapshot = None
    try:
        snapshot = DGHSDashboardSource().fetch()
        annual_history = [
            {"year": int(p.period), "cases": p.cases, "deaths": p.deaths or 0}
            for p in snapshot.yearly if p.cases is not None
        ]
        run.source_last_updated = (snapshot.national.report_date.isoformat()
                                   if snapshot.national.report_date else None)
        LOG.info("dashboard: %d years of history, source dated %s",
                 len(annual_history), run.source_last_updated or "unknown")
    except DGHSSourceError as exc:
        LOG.warning("dashboard unavailable (%s); using fallback history", exc)

    LOG.info("collecting DGHS reports %s to %s", start, args.end)
    outcome = collect_reports(start, args.end, args.cache)
    reports = outcome.reports
    run.days_fetched = (args.end - start).days + 1
    run.days_parsed = len(reports)
    run.days_skipped = run.days_fetched - run.days_parsed
    run.validation_rejections = outcome.rejected
    run.validation_anomalies = outcome.anomalies
    if outcome.rejected or outcome.anomalies:
        LOG.info("validation: %d rejected, %d anomalies logged",
                 outcome.rejected, outcome.anomalies)

    if not reports:
        LOG.error("no reports could be parsed; leaving %s untouched", args.out)
        append_run(runs_path, run.finish("error", "no reports could be parsed"))
        return 1

    result = build_payload(reports, year, annual_history=annual_history)
    problems = validate_payload(result.payload, result.revision_total)
    if problems:
        for problem in problems:
            LOG.error("validation: %s", problem)
        LOG.error("refusing to write %s", args.out)
        append_run(runs_path, run.finish("error", "; ".join(problems)))
        return 1

    coverage = check_season_coverage(result.payload)
    if coverage:
        if args.allow_partial:
            LOG.warning("partial season: %s", coverage)
        else:
            LOG.error("%s", coverage)
            LOG.error("refusing to write %s", args.out)
            return 1

    # Record which DGHS surface produced this dataset, so a reader can tell a
    # dashboard-backed figure from a press-release-backed one without guessing.
    result.payload["meta"]["primarySource"] = (
        "DGHS daily report" if snapshot is None else "DGHS dashboard"
    )
    # When the press-release host is down, the dashboard may already have
    # newer national totals. They travel in their own block rather than being
    # appended to the series, which has no district figures to go with them.
    latest_block = build_latest(snapshot, reports[-1].report_date)
    if latest_block:
        result.payload["latest"] = latest_block
        LOG.info("dashboard is ahead of the press releases: carrying %s "
                 "(%s cases) alongside a series that ends %s",
                 latest_block["reportDate"],
                 f"{latest_block['seasonCases']:,}",
                 latest_block["seriesAsOf"])
    else:
        result.payload.pop("latest", None)

    result.payload["meta"]["parserVersion"] = (
        snapshot.parser_version if snapshot is not None else "dghs-pdf-v1"
    )

    decision = decide(result.payload, args.out)
    if not decision.changed:
        LOG.info("no change: %s (sha256 %s)", decision.reason, decision.new_digest[:12])
        append_run(runs_path, run.finish("no_change"))
        write_status(args.out, runs_path, latest_report_date=reports[-1].report_date.isoformat())
        return 0

    LOG.info("publishing: %s (sha256 %s)", decision.reason, decision.new_digest[:12])
    publish(result.payload, args.out)

    # Cross-check the two DGHS surfaces. Disagreement is recorded, never
    # silently resolved in favour of one of them.
    latest_report = reports[-1]
    if snapshot is not None:
        check = cross_check(
            report_date=latest_report.report_date.isoformat(),
            dashboard_cases=snapshot.national.total_cases,
            dashboard_deaths=snapshot.national.total_deaths,
            press_cases=latest_report.national_cases,
            press_deaths=latest_report.national_deaths,
            dashboard_date=(snapshot.national.report_date.isoformat()
                            if snapshot.national.report_date else None),
        )
        run.verification_status = check.verification_status
        if check.discrepancies:
            discrepancy_path = args.out.parent / "source-discrepancies.json"
            existing: list[dict] = []
            if discrepancy_path.exists():
                try:
                    existing = json.loads(discrepancy_path.read_text(encoding="utf-8"))
                except ValueError:
                    existing = []
            discrepancy_path.write_text(
                json.dumps(check.as_dicts() + existing, indent=1), encoding="utf-8")
            for d in check.discrepancies:
                LOG.warning("source disagreement on %s: dashboard %s vs press release %s",
                            d.metric, d.dashboard_value, d.press_release_value)
        elif check.verification_status == "not_comparable":
            LOG.info("cross-check: skipped — dashboard is as of %s, press "
                     "releases run to %s",
                     snapshot.national.report_date, latest_report.report_date)
        else:
            LOG.info("cross-check: both DGHS surfaces agree (%s)", check.verification_status)
    else:
        run.verification_status = "unverified"

    run.records_written = len(result.payload["dates"])
    run.downward_revisions = result.downward_revisions
    append_run(runs_path, run.finish("success"))

    status_path = write_status(args.out, runs_path, result.payload["meta"]["lastUpdated"])
    LOG.info("wrote %s and %s", runs_path.name, status_path.name)

    meta = result.payload["meta"]
    LOG.info("wrote %s — %d days used, %d days with no release",
             args.out, result.days_used, result.days_missing)
    if result.downward_revisions:
        LOG.info("%d district figures were revised downward by DGHS "
                 "(%d cases in total, clamped to zero in the daily series)",
                 result.downward_revisions, result.revision_total)
    LOG.info("season %s: %s cases, %s deaths as of %s",
             meta["year"],
             f"{result.payload['history'][-1]['cases']:,}",
             result.payload["history"][-1]["deaths"],
             meta["lastUpdated"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
