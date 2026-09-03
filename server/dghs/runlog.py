"""A record of every ingestion attempt.

Without this there is no way to answer "did today's update actually work?"
other than diffing the output. The log is a small JSON file written beside the
dataset, so it travels with it and needs no database.

Statuses mirror what the API exposes:

    success    — new data fetched and written
    no_change  — the source had nothing newer; existing data left alone
    error      — the run failed; previous data preserved
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path

MAX_RUNS_KEPT = 60


@dataclass
class IngestionRun:
    run_started_at: str
    run_completed_at: str | None = None
    status: str = "error"
    source: str = "DGHS"
    source_url: str = ""
    source_last_updated: str | None = None
    days_fetched: int = 0
    days_parsed: int = 0
    days_skipped: int = 0
    records_written: int = 0
    downward_revisions: int = 0
    validation_rejections: int = 0
    validation_anomalies: int = 0
    verification_status: str = "unverified"
    parser_version: str = "dghs-dashboard-v2"
    error_message: str | None = None

    @staticmethod
    def start(source: str, source_url: str) -> "IngestionRun":
        return IngestionRun(
            run_started_at=datetime.now(timezone.utc).isoformat(timespec="seconds"),
            source=source,
            source_url=source_url,
        )

    def finish(self, status: str, error: str | None = None) -> "IngestionRun":
        self.run_completed_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
        self.status = status
        self.error_message = error
        return self


def append_run(path: Path, run: IngestionRun) -> None:
    """Append a run, newest first, keeping the log bounded."""
    path.parent.mkdir(parents=True, exist_ok=True)
    history: list[dict] = []
    if path.exists():
        try:
            history = json.loads(path.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            history = []
    history.insert(0, asdict(run))
    path.write_text(
        json.dumps(history[:MAX_RUNS_KEPT], indent=1),
        encoding="utf-8",
    )


def status_document(runs_path: Path, latest_report_date: str | None) -> dict:
    """What `/status` would serve: is the pipeline healthy, and how fresh?"""
    history: list[dict] = []
    if runs_path.exists():
        try:
            history = json.loads(runs_path.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            history = []

    last_success = next((r for r in history if r.get("status") == "success"), None)
    last_run = history[0] if history else None

    status = "error"
    if last_run and last_run.get("status") in {"success", "no_change"}:
        status = last_run["status"] if last_run["status"] == "no_change" else "healthy"

    # Stale is defined against DGHS's own cadence: it publishes daily, so more
    # than three days without a newer report means something is wrong upstream
    # or in the parser — not simply a quiet day.
    if latest_report_date:
        try:
            reported = datetime.fromisoformat(latest_report_date).date()
            age = (datetime.now(timezone.utc).date() - reported).days
            if age > 3:
                status = "stale"
        except ValueError:
            pass

    return {
        "source": "DGHS",
        "latestReportDate": latest_report_date,
        "lastSuccessfulIngestion": (last_success or {}).get("run_completed_at"),
        "lastRunStatus": (last_run or {}).get("status"),
        "status": status,
    }
