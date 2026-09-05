"""The `latest` block only appears when it has something true to add."""

from __future__ import annotations

from datetime import date

from dghs.latest import build_latest
from dghs.source import DGHSSnapshot, NationalTotals


def snapshot(report_date, total_cases=41032, total_deaths=113,
             cases_24h=988, deaths_24h=2):
    return DGHSSnapshot(
        source="DGHS", source_url="https://example.invalid", fetched_at="now",
        national=NationalTotals(report_date=report_date,
                                total_cases=total_cases, total_deaths=total_deaths,
                                cases_24h=cases_24h, deaths_24h=deaths_24h),
    )


def test_dashboard_ahead_of_the_series_is_carried():
    block = build_latest(snapshot(date(2026, 9, 5)), series_as_of=date(2026, 9, 3))
    assert block["reportDate"] == "2026-09-05"
    assert block["seasonCases"] == 41032
    assert block["seriesAsOf"] == "2026-09-03", "readers must see what the charts cover"
    assert block["source"] == "DGHS dashboard"


def test_nothing_is_carried_when_the_series_is_current():
    # The healthy case: the PDFs kept up, so there is nothing to add.
    assert build_latest(snapshot(date(2026, 9, 3)), series_as_of=date(2026, 9, 3)) is None


def test_nothing_is_carried_when_the_dashboard_lags():
    assert build_latest(snapshot(date(2026, 9, 1)), series_as_of=date(2026, 9, 3)) is None


def test_no_snapshot_means_no_block():
    assert build_latest(None, series_as_of=date(2026, 9, 3)) is None


def test_a_dashboard_without_season_totals_is_not_carried():
    # 24-hour figures alone cannot update a headline that counts the season.
    snap = snapshot(date(2026, 9, 5), total_cases=None, total_deaths=None)
    assert build_latest(snap, series_as_of=date(2026, 9, 3)) is None


def test_absent_24h_figures_are_omitted_not_zeroed():
    snap = snapshot(date(2026, 9, 5), cases_24h=None, deaths_24h=None)
    block = build_latest(snap, series_as_of=date(2026, 9, 3))
    assert "cases24h" not in block and "deaths24h" not in block
    assert block["seasonCases"] == 41032


def test_no_report_date_means_no_block():
    assert build_latest(snapshot(None), series_as_of=date(2026, 9, 3)) is None
