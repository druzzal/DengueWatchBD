"""The JSON endpoint must degrade, never crash.

DGHS is a government site that goes down — it was unreachable for most of this
week — so every one of these paths is a real operating condition, not a
hypothetical.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest

from api import main as api


@pytest.fixture(autouse=True)
def clear_cache():
    api._cache.update(fetched_at=None, payload=None, error=None)
    yield
    api._cache.update(fetched_at=None, payload=None, error=None)


SNAPSHOT = {
    "reportDate": "2026-09-05",
    "cumulative": {"cases": 41032, "deaths": 113},
    "last24Hours": {"cases": 988, "deaths": 2},
    "currentlyHospitalised": None,
    "parserVersion": "dghs-dashboard-v2",
}


def test_live_parse_is_served_and_cached():
    with patch.object(api, "_live_snapshot", return_value=SNAPSHOT) as parse:
        first, freshness, error = api._stats()
        assert freshness == "live" and error is None
        assert first["cumulative"]["cases"] == 41032

        second, freshness, _ = api._stats()
        assert freshness == "cached"
        assert parse.call_count == 1, "second request re-scraped DGHS"


def test_cache_expires_after_the_refresh_interval():
    with patch.object(api, "_live_snapshot", return_value=SNAPSHOT) as parse:
        api._stats()
        api._cache["fetched_at"] = (
            datetime.now(timezone.utc) - api.REFRESH_INTERVAL - timedelta(seconds=1)
        )
        api._stats()
        assert parse.call_count == 2


def test_source_down_with_a_warm_cache_serves_the_last_good_parse():
    with patch.object(api, "_live_snapshot", return_value=SNAPSHOT):
        api._stats()
    api._cache["fetched_at"] = None  # force a refresh attempt
    with patch.object(api, "_live_snapshot", side_effect=ConnectionError("timed out")):
        figures, freshness, error = api._stats()
    assert freshness == "stale"
    assert figures["cumulative"]["cases"] == 41032
    assert "ConnectionError" in error


def test_source_down_from_cold_falls_back_to_the_published_dataset():
    with patch.object(api, "_live_snapshot", side_effect=ConnectionError("timed out")):
        figures, freshness, error = api._stats()
    assert freshness == "published-fallback"
    assert figures["cumulative"]["cases"] is not None
    assert error


def test_a_changed_dom_does_not_crash_the_server():
    # The parser raises rather than guessing when DGHS changes its layout.
    with patch.object(api, "_live_snapshot", side_effect=ValueError("container not found")):
        _, freshness, error = api._stats()
    assert freshness in {"published-fallback", "unavailable"}
    assert "ValueError" in error


def test_nothing_available_at_all_reports_unavailable(monkeypatch):
    monkeypatch.setattr(api, "_published_fallback", lambda: None)
    with patch.object(api, "_live_snapshot", side_effect=ConnectionError("down")):
        figures, freshness, _ = api._stats()
    assert freshness == "unavailable" and figures == {}


def test_missing_values_stay_null_rather_than_becoming_zero():
    # A field DGHS does not publish must never read as a genuine zero.
    with patch.object(api, "_live_snapshot", return_value=SNAPSHOT):
        figures, _, _ = api._stats()
    assert figures["currentlyHospitalised"] is None
