"""Validation rules for the Supabase ingestion.

Every rule here exists because the corresponding mistake is easy to make and
invisible once it reaches a database.
"""

from __future__ import annotations

import sys
from datetime import date, timedelta
from pathlib import Path

import pytest
from pydantic import ValidationError

sys.path.insert(0, str(Path(__file__).resolve().parent))

from scraper import DailySummary, RegionalBreakdown, surge_alert  # noqa: E402


def summary(**overrides):
    base = dict(report_date=date(2026, 9, 5), total_cases_24h=988, total_deaths_24h=2,
                total_cases_ytd=41032, total_deaths_ytd=113)
    base.update(overrides)
    return DailySummary(**base)


def test_a_valid_day_passes():
    assert summary().total_cases_24h == 988


def test_negative_counts_are_rejected():
    with pytest.raises(ValidationError):
        summary(total_cases_24h=-1)


def test_a_future_report_date_is_rejected():
    with pytest.raises(ValidationError, match="future"):
        summary(report_date=date.today() + timedelta(days=2))


def test_year_to_date_below_the_daily_figure_is_rejected():
    with pytest.raises(ValidationError, match="year-to-date"):
        summary(total_cases_ytd=10)


def test_dhaka_split_must_add_up():
    with pytest.raises(ValidationError, match="!="):
        summary(dhaka_city_cases_24h=100, outside_dhaka_cases_24h=100)


def test_dhaka_split_that_adds_up_is_accepted():
    assert summary(dhaka_city_cases_24h=400, outside_dhaka_cases_24h=588)


def test_duplicate_districts_are_rejected():
    with pytest.raises(ValidationError, match="duplicate"):
        summary(regional_breakdowns=[
            RegionalBreakdown(district_name="Dhaka", cases_24h=1),
            RegionalBreakdown(district_name="Dhaka", cases_24h=2),
        ])


def test_a_district_cannot_out_report_the_whole_country():
    # The regression that prompted this rule: the dashboard's cumulative
    # season totals were read into a 24-hour column, and Barishal came
    # through as 6,379 against a national 988.
    with pytest.raises(ValidationError, match="cumulative figure"):
        summary(regional_breakdowns=[
            RegionalBreakdown(division_name="Barishal", district_name="Barishal",
                              cases_24h=6379, deaths_24h=10)
        ])


def test_district_deaths_cannot_exceed_the_national_total():
    with pytest.raises(ValidationError, match="deaths in 24h"):
        summary(regional_breakdowns=[
            RegionalBreakdown(district_name="Dhaka", cases_24h=10, deaths_24h=99)
        ])


def test_plausible_regional_rows_are_accepted():
    ok = summary(regional_breakdowns=[
        RegionalBreakdown(division_name="Dhaka", district_name="Dhaka",
                          cases_24h=400, deaths_24h=1),
        RegionalBreakdown(division_name="Khulna", district_name="Khulna",
                          cases_24h=120, deaths_24h=0),
    ])
    assert len(ok.regional_breakdowns) == 2


def test_missing_optional_figures_stay_none_not_zero():
    row = summary(total_cases_ytd=None).to_row()
    assert row["total_cases_ytd"] is None


class TestSurgeAlert:
    def test_a_rise_over_the_threshold_raises_an_alert(self):
        alert = surge_alert(summary(total_cases_24h=130), {"total_cases_24h": 100})
        assert alert and alert["percentChange"] == 30.0
        assert alert["aps"]["interruption-level"] == "time-sensitive"

    def test_a_small_rise_does_not(self):
        assert surge_alert(summary(total_cases_24h=110), {"total_cases_24h": 100}) is None

    def test_a_fall_does_not(self):
        assert surge_alert(summary(total_cases_24h=50), {"total_cases_24h": 100}) is None

    def test_no_previous_day_does_not(self):
        assert surge_alert(summary(), None) is None

    def test_a_zero_previous_day_does_not_divide_by_zero(self):
        assert surge_alert(summary(), {"total_cases_24h": 0}) is None
