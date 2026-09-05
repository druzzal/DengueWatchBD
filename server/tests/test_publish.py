"""Publishing decisions: does the data actually differ, and is the last good
copy preserved when it does."""

from __future__ import annotations

import json
from datetime import date
from pathlib import Path

import pytest

from dghs.publish import decide, fingerprint, freshness, publish


def dataset(cases: list[int], updated: str = "2026-09-03") -> dict:
    return {
        "meta": {"lastUpdated": updated, "retrievedAt": "2026-09-05T09:00:00+06:00"},
        "dates": ["2026-09-01", "2026-09-02"],
        "national": {"cases": cases},
        "districts": [],
        "history": [],
    }


def test_fingerprint_ignores_ingestion_timestamps():
    # Two runs on different days that scraped identical figures must look
    # identical, or every run would publish.
    a = dataset([10, 20], updated="2026-09-03")
    b = dataset([10, 20], updated="2026-09-03")
    b["meta"]["retrievedAt"] = "2026-09-06T09:00:00+06:00"
    assert fingerprint(a) == fingerprint(b)


def test_fingerprint_changes_when_figures_change():
    assert fingerprint(dataset([10, 20])) != fingerprint(dataset([10, 21]))


def test_unchanged_dataset_is_not_republished(tmp_path: Path):
    out = tmp_path / "surveillance.json"
    payload = dataset([10, 20])
    publish(payload, out)
    again = decide(dataset([10, 20]), out)
    assert not again.changed
    assert "identical" in again.reason


def test_changed_dataset_is_published(tmp_path: Path):
    out = tmp_path / "surveillance.json"
    publish(dataset([10, 20]), out)
    assert decide(dataset([10, 21]), out).changed


def test_first_ever_run_publishes(tmp_path: Path):
    assert decide(dataset([1]), tmp_path / "nothing-here.json").changed


def test_unreadable_published_file_triggers_republish(tmp_path: Path):
    out = tmp_path / "surveillance.json"
    out.write_text("{ this is not json", encoding="utf-8")
    decision = decide(dataset([1]), out)
    assert decision.changed
    assert "unreadable" in decision.reason


def test_publishing_keeps_the_previous_dataset(tmp_path: Path):
    out = tmp_path / "surveillance.json"
    publish(dataset([10, 20]), out)
    publish(dataset([10, 21]), out)

    current = json.loads(out.read_text())
    previous = json.loads((tmp_path / "previous.json").read_text())
    assert current["national"]["cases"] == [10, 21]
    assert previous["national"]["cases"] == [10, 20], "last known good was lost"


def test_no_previous_file_on_the_very_first_publish(tmp_path: Path):
    out = tmp_path / "surveillance.json"
    publish(dataset([1]), out)
    assert not (tmp_path / "previous.json").exists()


def test_publish_leaves_no_temporary_files(tmp_path: Path):
    out = tmp_path / "surveillance.json"
    publish(dataset([1]), out)
    publish(dataset([2]), out)
    assert [p.name for p in tmp_path.iterdir() if p.suffix == ".tmp"] == []


@pytest.mark.parametrize("reported,expected", [
    ("2026-09-05", "fresh"),
    ("2026-09-02", "fresh"),     # 3 days — at the edge, still fresh
    ("2026-09-01", "stale"),     # 4 days
    ("2026-08-28", "outdated"),  # 8 days
])
def test_freshness_tiers(reported: str, expected: str):
    assert freshness(reported, today=date(2026, 9, 5)) == expected


def test_freshness_of_an_absent_or_broken_date_is_unknown():
    assert freshness(None) == "unknown"
    assert freshness("not-a-date") == "unknown"
