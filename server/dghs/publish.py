"""Deciding whether a freshly built dataset is worth publishing, and keeping
the last known good copy when it is.

Split out of `cli.py` because "did the data actually change" is a question
about content, not about files. The workflow previously asked git whether
anything under public/ differed, but the run log gains an entry on every run,
so the answer was always yes and every run committed — including runs where
DGHS had published nothing new.
"""

from __future__ import annotations

import hashlib
import json
import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

DHAKA = timezone(timedelta(hours=6))

# How far behind DGHS's own daily cadence the newest report may fall before
# the published status stops calling itself fresh.
STALE_AFTER_DAYS = 3
OUTDATED_AFTER_DAYS = 7


def fingerprint(payload: dict) -> str:
    """A stable digest of the data a reader would actually see.

    Deliberately excludes `meta`: it carries the ingestion timestamp, which
    changes on every run, so including it would make every dataset look new
    and defeat the whole point of the check.
    """
    body = {key: value for key, value in payload.items() if key != "meta"}
    canonical = json.dumps(body, sort_keys=True, separators=(",", ":"),
                           ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class PublishDecision:
    changed: bool
    reason: str
    new_digest: str
    previous_digest: str | None


def decide(payload: dict, current_path: Path) -> PublishDecision:
    """Compare the built dataset against what is already published."""
    new_digest = fingerprint(payload)
    if not current_path.exists():
        return PublishDecision(True, "no dataset published yet", new_digest, None)
    try:
        existing = json.loads(current_path.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        # An unreadable published file is itself a reason to republish.
        return PublishDecision(True, "published dataset unreadable", new_digest, None)

    old_digest = fingerprint(existing)
    if old_digest == new_digest:
        return PublishDecision(False, "identical to published dataset",
                               new_digest, old_digest)
    return PublishDecision(True, "dataset changed", new_digest, old_digest)


def publish(payload: dict, current_path: Path) -> None:
    """Write the new dataset, keeping the copy it replaces as last-known-good.

    The previous file is only ever written from a dataset that already passed
    validation, so it is always safe to fall back to. Both writes go through a
    temporary file and os.replace so a crash mid-write cannot leave a truncated
    JSON file where a valid one used to be.
    """
    current_path.parent.mkdir(parents=True, exist_ok=True)

    if current_path.exists():
        previous_path = current_path.parent / "previous.json"
        _atomic_write(previous_path, current_path.read_text(encoding="utf-8"))

    _atomic_write(current_path,
                  json.dumps(payload, separators=(",", ":"), ensure_ascii=False))


def _atomic_write(path: Path, text: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)


def freshness(latest_report_date: str | None, today: object = None) -> str:
    """FRESH / STALE / OUTDATED, judged against DGHS's daily cadence.

    Returned lowercase to match the vocabulary already used in status.json.
    """
    if not latest_report_date:
        return "unknown"
    try:
        reported = datetime.fromisoformat(latest_report_date).date()
    except ValueError:
        return "unknown"
    reference = today or datetime.now(DHAKA).date()
    age = (reference - reported).days
    if age > OUTDATED_AFTER_DAYS:
        return "outdated"
    if age > STALE_AFTER_DAYS:
        return "stale"
    return "fresh"
