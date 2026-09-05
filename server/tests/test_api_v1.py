"""The JSON contract the Swift client decodes.

These assert shape and key names, because a renamed key here is a silent
decoding failure on a phone that has already shipped.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from api import v1  # noqa: E402
from api.main import app  # noqa: E402

SUMMARY = {
    "report_date": "2026-09-05", "total_cases_24h": 988, "total_deaths_24h": 2,
    "total_cases_ytd": 41032, "total_deaths_ytd": 113,
    "dhaka_city_cases_24h": None, "outside_dhaka_cases_24h": None,
}
REGIONS = [{"report_date": "2026-09-05", "division_name": "Dhaka",
            "district_name": "Dhaka", "cases_24h": 400, "deaths_24h": 1},
           {"report_date": "2026-09-04", "division_name": "Dhaka",
            "district_name": "Dhaka", "cases_24h": 380, "deaths_24h": 0}]


@pytest.fixture
def client(monkeypatch):
    v1._cache.clear()

    def fake_get(table, params):
        if table == "daily_summaries":
            if params.get("limit") == 1:
                return [SUMMARY]
            return [SUMMARY, {**SUMMARY, "report_date": "2026-09-04",
                              "total_cases_24h": 900, "total_deaths_24h": 1}]
        return REGIONS

    monkeypatch.setattr(v1, "_get", fake_get)
    return TestClient(app)


def test_latest_returns_camelcase_keys(client):
    body = client.get("/api/v1/dengue/latest").json()
    assert set(body) >= {"reportDate", "totalCases24h", "totalDeaths24h",
                         "totalCasesYtd", "totalDeathsYtd",
                         "dhakaCityCases24h", "outsideDhakaCases24h",
                         "regionalBreakdowns"}
    assert body["reportDate"] == "2026-09-05"
    assert body["totalCases24h"] == 988


def test_latest_nests_regional_breakdowns_in_camelcase(client):
    region = client.get("/api/v1/dengue/latest").json()["regionalBreakdowns"][0]
    assert set(region) == {"divisionName", "districtName", "cases24h", "deaths24h"}
    assert region["districtName"] == "Dhaka"


def test_absent_figures_stay_null_not_zero(client):
    # An Optional in Swift must mean "DGHS did not publish it".
    assert client.get("/api/v1/dengue/latest").json()["dhakaCityCases24h"] is None


def test_report_dates_are_plain_iso_days(client):
    # No time component, no offset: Swift decodes it as a calendar day.
    assert client.get("/api/v1/dengue/latest").json()["reportDate"] == "2026-09-05"


def test_history_is_ascending_for_charts(client):
    points = client.get("/api/v1/dengue/history?days=7").json()
    assert [p["reportDate"] for p in points] == sorted(p["reportDate"] for p in points)
    assert set(points[0]) == {"reportDate", "totalCases24h", "totalDeaths24h"}


def test_history_rejects_an_absurd_range(client):
    assert client.get("/api/v1/dengue/history?days=9999").status_code == 422
    assert client.get("/api/v1/dengue/history?days=0").status_code == 422


def test_district_lookup_is_case_insensitive(client):
    assert client.get("/api/v1/dengue/districts/dhaka").status_code == 200


def test_unknown_district_is_404_not_an_empty_200(client, monkeypatch):
    monkeypatch.setattr(v1, "_get", lambda table, params: [])
    assert client.get("/api/v1/dengue/districts/Atlantis").status_code == 404


def test_no_data_ingested_yet_is_404(client, monkeypatch):
    monkeypatch.setattr(v1, "_get", lambda table, params: [])
    assert client.get("/api/v1/dengue/latest").status_code == 404


def test_unconfigured_supabase_reports_503(monkeypatch):
    v1._cache.clear()
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    monkeypatch.delenv("SUPABASE_ANON_KEY", raising=False)
    monkeypatch.delenv("SUPABASE_SERVICE_KEY", raising=False)
    assert TestClient(app).get("/api/v1/dengue/latest").status_code == 503
