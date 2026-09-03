"""Tests for the DGHS parser.

The fixture is a real press release, kept in the repo so the suite runs offline
and so a regression in the parser is caught against known-good numbers rather
than against whatever DGHS published today.
"""

from __future__ import annotations

import json
from datetime import date, timedelta
from pathlib import Path

import pytest

from dghs.build import build_payload
from dghs.districts import BY_CODE, DISTRICTS
from dghs.parse import DISTRICT_ALIASES, ParseError, parse_pdf

FIXTURE = Path(__file__).parent / "fixtures" / "20260902_dengue_all.pdf"

# Verified by hand against the published PDF for 2 September 2026.
EXPECTED_CASES = 38_280
EXPECTED_DEATHS = 107
EXPECTED_ADMITTED = 2_740
EXPECTED_DHAKA_CASES = 9_721      # Dhaka district plus Dhaka city corporation


@pytest.fixture(scope="module")
def report():
    if not FIXTURE.exists():
        pytest.skip(f"fixture missing: {FIXTURE}")
    return parse_pdf(FIXTURE, date(2026, 9, 2))


def test_national_totals(report):
    assert report.national_cases == EXPECTED_CASES
    assert report.national_deaths == EXPECTED_DEATHS


def test_all_districts_present(report):
    """By September every district has cases, so all 64 are listed.

    Early in a season DGHS omits districts with no cases — on 1 January 2026 the
    table had 28 rows — so the parser does not require 64. The reconciliation
    against national totals is what guarantees completeness.
    """
    assert len(report.districts) == 64
    assert set(report.districts) == {d["code"] for d in DISTRICTS}


def test_districts_reconcile_to_national(report):
    assert sum(d.cumulative_cases for d in report.districts.values()) == EXPECTED_CASES
    assert sum(d.deaths for d in report.districts.values()) == EXPECTED_DEATHS


def test_dhaka_includes_city_corporation(report):
    """Dhaka city is reported separately and must be folded into Dhaka district."""
    assert report.districts["DHAKA"].cumulative_cases == EXPECTED_DHAKA_CASES


def test_hospital_census_identity(report):
    """admitted - discharged - deaths == still in hospital, for every district."""
    for record in report.districts.values():
        expected = record.cumulative_cases - record.discharged - record.deaths
        assert expected == record.currently_admitted, record.code
    assert report.total_currently_admitted == EXPECTED_ADMITTED


def test_alias_table_covers_every_district():
    codes = {d["code"] for d in DISTRICTS}
    assert set(DISTRICT_ALIASES.values()) == codes
    # More than one spelling per district is expected: DGHS uses several legacy
    # Bengali fonts, which extract differently.
    assert len(DISTRICT_ALIASES) >= len(codes)


def test_unknown_district_name_raises(monkeypatch, report):
    """A new font encoding must fail loudly, not silently drop a district."""
    from dghs import parse as parse_module
    stripped = dict(DISTRICT_ALIASES)
    stripped.pop(next(iter(stripped)))
    monkeypatch.setattr(parse_module, "DISTRICT_ALIASES", stripped)
    with pytest.raises(ParseError, match="unrecognised district names"):
        parse_pdf(FIXTURE, date(2026, 9, 2))


def test_build_payload_shape(report):
    """The payload must match what SurveillancePayload decodes in the app."""
    result = build_payload([report], year=2026)
    payload = result.payload

    assert set(payload) == {"meta", "dates", "national", "districts", "history"}
    assert set(payload["meta"]) == {
        "datasetName", "isSampleData", "disclaimer", "attribution",
        "seasonStart", "lastUpdated", "year",
    }
    assert payload["meta"]["isSampleData"] is False

    length = len(payload["dates"])
    for series in payload["national"].values():
        assert len(series) == length

    assert len(payload["districts"]) == 64
    for district in payload["districts"]:
        assert set(district) >= {
            "code", "name", "division", "latitude", "longitude",
            "populationThousands", "cases", "deaths",
        }
        assert len(district["cases"]) == length
        assert len(district["deaths"]) == length
        assert district["code"] in BY_CODE

    # The first day carries the season-to-date cumulative, so that summing the
    # daily series reproduces the season total.
    assert payload["national"]["cases"] == [EXPECTED_CASES]
    assert payload["national"]["admitted"] == [EXPECTED_ADMITTED]
    assert payload["history"][-1] == {
        "year": 2026, "cases": EXPECTED_CASES, "deaths": EXPECTED_DEATHS, "verified": True,
    }


def test_daily_values_are_differences_of_cumulative(report):
    """Two days in, the daily figure is the day-on-day change."""
    from copy import deepcopy
    later = deepcopy(report)
    later.report_date = date(2026, 9, 3)
    later.national_cases = report.national_cases + 500
    later.national_deaths = report.national_deaths + 3
    for code, record in later.districts.items():
        record.cumulative_cases += 0
    later.districts["DHAKA"].cumulative_cases += 500
    later.districts["DHAKA"].deaths += 3

    payload = build_payload([report, later], year=2026).payload
    assert payload["national"]["cases"] == [EXPECTED_CASES, 500]
    assert payload["national"]["deaths"] == [EXPECTED_DEATHS, 3]
    dhaka = next(d for d in payload["districts"] if d["code"] == "DHAKA")
    assert dhaka["cases"] == [EXPECTED_DHAKA_CASES, 500]

    # Summing the daily series must reproduce the season total exactly.
    assert sum(payload["national"]["cases"]) == payload["history"][-1]["cases"]


# --- Dashboard adapter -------------------------------------------------

DASHBOARD_FIXTURE = Path(__file__).parent / "fixtures_dashboard.html"


@pytest.fixture(scope="module")
def dashboard_snapshot():
    from dghs.dashboard import DGHSDashboardSource
    html = DASHBOARD_FIXTURE.read_text(encoding="utf-8", errors="replace")
    return DGHSDashboardSource().parse(html)


def test_dashboard_extracts_year_history(dashboard_snapshot):
    years = {p.period: p.cases for p in dashboard_snapshot.yearly}
    # Independently published figures, used as a cross-check on the parse.
    assert years["2019"] == 101_354
    assert years["2023"] == 321_017
    assert years["2025"] == 102_861


def test_dashboard_agrees_with_press_release(dashboard_snapshot, report):
    """Two different DGHS surfaces must report the same season total."""
    current = {p.period: p.cases for p in dashboard_snapshot.yearly}["2026"]
    assert current == report.national_cases


def test_dashboard_does_not_guess_unlabelled_series(dashboard_snapshot):
    """Superseded assertion, kept as a record of why the rule exists.

    This originally asserted that divisions were excluded, because the first
    parser could only identify series by position — and doing so produced
    41,891 "deaths" in a July. Divisions are now extracted safely, keyed on the
    container id `div_city_cor_case_in_year` and the series name `Admitted`.

    What still must not appear is anything whose meaning would have to be
    inferred: the multi-year weekly and monthly charts.
    """
    assert dashboard_snapshot.monthly == []
    assert any("by_month_case" in reason for reason in dashboard_snapshot.skipped)


def test_dashboard_raises_when_layout_changes():
    from dghs.dashboard import DGHSDashboardSource
    from dghs.source import DGHSSourceError
    with pytest.raises(DGHSSourceError):
        DGHSDashboardSource().parse("<html><body>no charts here</body></html>")


# --- Validation --------------------------------------------------------

def test_validation_rejects_impossible_values():
    from datetime import date as _date
    from dghs.validation import validate_daily
    today = _date(2026, 9, 2)

    assert not validate_daily(today, -1, 0, today=today).ok
    assert not validate_daily(today, 10, -3, today=today).ok
    assert not validate_daily(_date(2027, 1, 1), 10, 1, today=today).ok
    assert not validate_daily(today, 99_999, 1, today=today).ok


def test_validation_rejects_cumulative_going_backwards():
    from datetime import date as _date
    from dghs.validation import validate_daily
    today = _date(2026, 9, 2)
    result = validate_daily(today, 10, 1, previous_cumulative=38_000,
                            cumulative=30_000, today=today)
    assert not result.ok
    assert any(f.code == "cumulative_reversal" for f in result.rejections)


def test_validation_allows_real_spikes_but_flags_them():
    """A genuine outbreak must not be thrown away."""
    from datetime import date as _date
    from dghs.validation import validate_daily
    today = _date(2026, 9, 2)
    result = validate_daily(today, 1_400, 5, previous_cumulative=3_000, today=today)
    assert result.ok
    assert any(f.code == "large_jump" for f in result.anomalies)


# --- Run log -----------------------------------------------------------

def test_runlog_reports_stale_when_source_falls_behind(tmp_path):
    from dghs.runlog import IngestionRun, append_run, status_document
    runs = tmp_path / "runs.json"
    append_run(runs, IngestionRun.start("DGHS", "http://x").finish("success"))

    fresh = status_document(runs, date.today().isoformat())
    assert fresh["status"] == "healthy"

    behind = status_document(runs, (date.today() - timedelta(days=9)).isoformat())
    assert behind["status"] == "stale"


def test_runlog_survives_a_corrupt_file(tmp_path):
    from dghs.runlog import IngestionRun, append_run
    runs = tmp_path / "runs.json"
    runs.write_text("{not json", encoding="utf-8")
    append_run(runs, IngestionRun.start("DGHS", "http://x").finish("success"))
    assert runs.read_text(encoding="utf-8").lstrip().startswith("[")


# --- Chart identification is semantic, not positional -------------------

def test_dashboard_identifies_series_by_container_id(dashboard_snapshot):
    """Every trusted figure comes from a named container and named series."""
    n = dashboard_snapshot.national
    assert n.cases_24h == 1110
    assert n.deaths_24h == 5
    assert n.total_cases == 38_280
    assert n.total_deaths == 107
    assert n.discharged == 35_433


def test_dashboard_daily_series_reconciles(dashboard_snapshot):
    """245 daily points must sum to the season total the same page reports."""
    assert len(dashboard_snapshot.daily) == 245
    assert sum(p.cases for p in dashboard_snapshot.daily) == dashboard_snapshot.national.total_cases


def test_dashboard_divisions_reconcile(dashboard_snapshot):
    assert sum(a.cases for a in dashboard_snapshot.areas) == dashboard_snapshot.national.total_cases


def test_reordering_charts_does_not_change_results():
    """The regression that matters.

    An earlier parser keyed on chart order and reported 41,891 deaths in July.
    Shuffling the chart blocks must now change nothing at all, because every
    series is found by container id and series name.
    """
    import re
    from dghs.dashboard import DGHSDashboardSource

    html = DASHBOARD_FIXTURE.read_text(encoding="utf-8", errors="replace")
    marks = [m.start() for m in re.finditer(r"Highcharts\.chart\(", html)]
    head, tail = html[:marks[0]], html[marks[-1]:]
    blocks = [html[a:b] for a, b in zip(marks, marks[1:])]
    shuffled = head + "".join(reversed(blocks)) + tail

    original = DGHSDashboardSource().parse(html)
    reordered = DGHSDashboardSource().parse(shuffled)

    assert reordered.national.total_cases == original.national.total_cases
    assert reordered.national.deaths_24h == original.national.deaths_24h
    assert [p.cases for p in reordered.daily] == [p.cases for p in original.daily]
    assert {a.name: a.cases for a in reordered.areas} == {a.name: a.cases for a in original.areas}


def test_unsafe_series_stay_excluded(dashboard_snapshot):
    """Age, sex and multi-year charts are present but must not be returned."""
    reasons = " ".join(dashboard_snapshot.skipped)
    assert "age_group" in reasons
    assert "by_week_case" in reasons
    assert dashboard_snapshot.monthly == []


def test_missing_container_is_skipped_not_guessed():
    from dghs.dashboard import DGHSDashboardSource
    html = DASHBOARD_FIXTURE.read_text(encoding="utf-8", errors="replace")
    stripped = html.replace("'confirmed_case'", "'renamed_container'")
    snap = DGHSDashboardSource().parse(stripped)
    assert snap.daily == []
    assert any("daily_cases" in s for s in snap.skipped)
    # Everything else still parses — one missing chart is not a total failure.
    assert snap.national.total_cases == 38_280


def test_parser_version_and_provenance_recorded(dashboard_snapshot):
    assert dashboard_snapshot.parser_version == "dghs-dashboard-v2"
    assert dashboard_snapshot.source_type == "dashboard"
    assert dashboard_snapshot.source_url.startswith("https://dashboard.dghs.gov.bd")


# --- Cross-source verification -----------------------------------------

def test_cross_check_marks_agreement(dashboard_snapshot, report):
    from dghs.crosscheck import cross_check
    result = cross_check("2026-09-02",
                         dashboard_snapshot.national.total_cases,
                         dashboard_snapshot.national.total_deaths,
                         report.national_cases, report.national_deaths)
    assert result.verified
    assert result.verification_status == "cross_checked"
    assert result.discrepancies == []


def test_cross_check_records_disagreement_without_choosing():
    from dghs.crosscheck import cross_check
    result = cross_check("2026-09-02", 38_280, 107, 38_000, 107)
    assert not result.verified
    assert result.verification_status == "disputed"
    assert result.discrepancies[0].metric == "total_cases"
    assert result.discrepancies[0].difference == 280


def test_first_report_is_not_judged_as_a_daily_figure(tmp_path):
    """Regression: validating the baseline day as one day's cases rejected
    the entire season, because a cumulative total looks implausible as a
    daily count."""
    from dghs.validation import validate_daily
    from datetime import date as _date
    today = _date(2026, 9, 2)
    # A baseline is passed as zero delta with the cumulative attached.
    assert validate_daily(today, cases=0, deaths=0, cumulative=38_280, today=today).ok


def test_rejection_does_not_cascade():
    """Regression: a rejected day must not poison every day after it.

    `previous` has to advance even when a report is rejected, otherwise the
    next day differences against a stale baseline and is rejected too.
    """
    from dghs.validation import validate_daily
    from datetime import date as _date
    today = _date(2026, 9, 2)
    # Day N rejected for an implausible delta...
    bad = validate_daily(today, cases=50_000, deaths=1,
                         previous_cumulative=1_000, cumulative=51_000, today=today)
    assert not bad.ok
    # ...but the following day, differenced against the advanced baseline, is fine.
    good = validate_daily(today, cases=120, deaths=1,
                          previous_cumulative=51_000, cumulative=51_120, today=today)
    assert good.ok


def test_cross_check_skips_when_dates_differ():
    """Regression from the first CI run.

    The dashboard is as-of today; a day's press release lands the next morning.
    Comparing their totals across different dates reported a 1,252-case
    "dispute" that was just one extra day of dengue.
    """
    from dghs.crosscheck import cross_check
    result = cross_check("2026-09-02", 39_532, 111, 38_280, 107,
                         dashboard_date="2026-09-03")
    assert result.verification_status == "not_comparable"
    assert result.discrepancies == []


def test_cross_check_still_catches_same_date_disagreement():
    from dghs.crosscheck import cross_check
    result = cross_check("2026-09-02", 38_000, 107, 38_280, 107,
                         dashboard_date="2026-09-02")
    assert result.verification_status == "disputed"
    assert result.discrepancies[0].difference == -280
