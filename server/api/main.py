"""A read-only JSON endpoint over the DGHS dengue figures.

    GET /api/dengue-stats

Two things about this service are deliberate.

It does not contain a scraper. `dghs.dashboard.DGHSDashboardSource` already
parses the DGHS dashboard, is covered by the test suite, and identifies every
series by its Highcharts container id and series name rather than by position.
A second parser here would be a second thing to keep correct when DGHS changes
its page, and the two would drift.

It does not scrape on request. A request-time scrape would put DGHS between
the app and its users: every app launch becomes a hit on a government server,
a DGHS outage becomes an app outage, and figures reach the reader with none of
the validation the ingestion pipeline applies. Instead this serves the
canonical dataset the pipeline publishes, and refreshes from DGHS at most once
every REFRESH_INTERVAL.
"""

from __future__ import annotations

import json
import logging
import sys
import threading
from dataclasses import asdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI
from api.v1 import router as v1_router
from fastapi.responses import JSONResponse

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from dghs.dashboard import DASHBOARD_URL, DGHSDashboardSource  # noqa: E402
from dghs.source import DGHSSourceError  # noqa: E402

LOG = logging.getLogger("dengue-api")
DHAKA = timezone(timedelta(hours=6))

# Published dataset, written by the ingestion pipeline.
PUBLISHED = Path(__file__).resolve().parent.parent.parent / "public" / "surveillance.json"

# DGHS publishes daily. Refreshing more often than this only costs them
# bandwidth and gains nothing.
REFRESH_INTERVAL = timedelta(minutes=30)

app = FastAPI(
    title="DengueWatch DGHS stats",
    description="Aggregated official DGHS dengue figures. Not a DGHS service.",
    version="1.0.0",
)

_lock = threading.Lock()
_cache: dict[str, Any] = {"fetched_at": None, "payload": None, "error": None}


def _published_fallback() -> dict[str, Any] | None:
    """The last dataset the ingestion pipeline validated and published."""
    if not PUBLISHED.exists():
        return None
    try:
        data = json.loads(PUBLISHED.read_text(encoding="utf-8"))
    except (ValueError, OSError) as exc:
        LOG.warning("published dataset unreadable: %s", exc)
        return None

    history = data.get("history") or []
    season = history[-1] if history else {}
    return {
        "reportDate": data.get("meta", {}).get("lastUpdated"),
        "cumulative": {
            "cases": season.get("cases"),
            "deaths": season.get("deaths"),
        },
        "last24Hours": {"cases": None, "deaths": None},
        "currentlyHospitalised": None,
    }


def _live_snapshot() -> dict[str, Any]:
    """Parse the DGHS dashboard through the pipeline's own parser."""
    snapshot = DGHSDashboardSource().fetch()
    national = snapshot.national
    return {
        "reportDate": national.report_date.isoformat() if national.report_date else None,
        "cumulative": {
            "cases": national.total_cases,
            "deaths": national.total_deaths,
        },
        "last24Hours": {
            "cases": national.cases_24h,
            "deaths": national.deaths_24h,
        },
        "currentlyHospitalised": national.current_hospitalised,
        "parserVersion": snapshot.parser_version,
    }


def _stats() -> tuple[dict[str, Any], str, str | None]:
    """Return (figures, freshness, error). Never raises."""
    now = datetime.now(timezone.utc)
    with _lock:
        fetched = _cache["fetched_at"]
        if fetched and now - fetched < REFRESH_INTERVAL and _cache["payload"]:
            return _cache["payload"], "cached", None

    try:
        payload = _live_snapshot()
        with _lock:
            _cache.update(fetched_at=now, payload=payload, error=None)
        return payload, "live", None
    except (DGHSSourceError, Exception) as exc:  # noqa: BLE001 - reported, never raised
        message = f"{type(exc).__name__}: {exc}"
        LOG.warning("live fetch failed: %s", message)
        with _lock:
            _cache["error"] = message
            if _cache["payload"]:
                # A previous good parse is better than nothing, and honestly
                # labelled rather than passed off as current.
                return _cache["payload"], "stale", message

        fallback = _published_fallback()
        if fallback:
            return fallback, "published-fallback", message
        return {}, "unavailable", message


app.include_router(v1_router)


@app.get("/api/dengue-stats")
def dengue_stats() -> JSONResponse:
    figures, freshness, error = _stats()

    body: dict[str, Any] = {
        "source": {
            "name": "DGHS",
            "organization": "Directorate General of Health Services",
            "country": "Bangladesh",
            "url": DASHBOARD_URL,
        },
        "disclaimer": (
            "DengueWatch is an independent application using official DGHS "
            "data. It is not a DGHS service and is not endorsed by DGHS."
        ),
        "retrievedAt": datetime.now(DHAKA).isoformat(timespec="seconds"),
        "freshness": freshness,
        "data": figures,
    }
    if error:
        body["error"] = error

    # A degraded answer is still a useful answer, so only a total absence of
    # data is a server error.
    status = 200 if figures else 503
    return JSONResponse(body, status_code=status)


@app.get("/health")
def health() -> dict[str, Any]:
    return {"ok": True, "lastError": _cache["error"]}
