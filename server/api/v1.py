"""Swift-facing REST endpoints, backed by Supabase.

    GET /api/v1/dengue/latest
    GET /api/v1/dengue/history?days=30
    GET /api/v1/dengue/districts/{district_name}

Every key is camelCase and every date is an ISO 8601 `YYYY-MM-DD` string, so a
Swift `Codable` struct with matching property names decodes without a
`CodingKeys` block and with `.iso8601`-style date handling. Nulls are preserved
rather than defaulted, so an Optional in Swift means "DGHS did not publish
this" rather than "zero".
"""

from __future__ import annotations

import logging
import os
import threading
from datetime import datetime, timedelta, timezone
from typing import Any

import requests
from fastapi import APIRouter, HTTPException, Path, Query
from pydantic import BaseModel, Field

LOG = logging.getLogger("dengue-api.v1")
DHAKA = timezone(timedelta(hours=6))
REQUEST_TIMEOUT = 20
CACHE_TTL = timedelta(minutes=5)

router = APIRouter(prefix="/api/v1/dengue", tags=["dengue"])


# ---------------------------------------------------------------------------
# Response models — these define the JSON contract the Swift client decodes
# ---------------------------------------------------------------------------

class RegionalBreakdownOut(BaseModel):
    divisionName: str | None = None
    districtName: str
    cases24h: int
    deaths24h: int


class DailySummaryOut(BaseModel):
    reportDate: str = Field(examples=["2026-09-05"])
    totalCases24h: int
    totalDeaths24h: int
    totalCasesYtd: int | None = None
    totalDeathsYtd: int | None = None
    dhakaCityCases24h: int | None = None
    outsideDhakaCases24h: int | None = None
    regionalBreakdowns: list[RegionalBreakdownOut] = Field(default_factory=list)


class HistoryPointOut(BaseModel):
    """Deliberately narrow: a chart needs a date and some numbers, and sending
    64 districts per day would make a 30-day request large for no gain."""
    reportDate: str
    totalCases24h: int
    totalDeaths24h: int


class DistrictPointOut(BaseModel):
    reportDate: str
    districtName: str
    divisionName: str | None = None
    cases24h: int
    deaths24h: int


# ---------------------------------------------------------------------------
# Supabase access
# ---------------------------------------------------------------------------

_lock = threading.Lock()
_cache: dict[str, tuple[datetime, Any]] = {}


def _client() -> tuple[str, dict[str, str]]:
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_ANON_KEY") or os.getenv("SUPABASE_SERVICE_KEY")
    if not url or not key:
        raise HTTPException(503, "Supabase is not configured on this server")
    return url.rstrip("/") + "/rest/v1", {"apikey": key, "Authorization": f"Bearer {key}"}


def _get(table: str, params: dict[str, Any]) -> list[dict[str, Any]]:
    """Read from PostgREST, with a short cache so a burst of app launches does
    not become a burst of database queries."""
    cache_key = f"{table}:{sorted(params.items())}"
    now = datetime.now(timezone.utc)
    with _lock:
        hit = _cache.get(cache_key)
        if hit and now - hit[0] < CACHE_TTL:
            return hit[1]

    rest, headers = _client()
    try:
        response = requests.get(f"{rest}/{table}", params=params,
                                headers=headers, timeout=REQUEST_TIMEOUT)
        response.raise_for_status()
        rows = response.json()
    except requests.RequestException as exc:
        LOG.warning("supabase read failed: %s", exc)
        with _lock:
            stale = _cache.get(cache_key)
        if stale:
            # Slightly old figures beat a 502 on a screen someone is looking at.
            return stale[1]
        raise HTTPException(502, "upstream database unavailable") from exc

    with _lock:
        _cache[cache_key] = (now, rows)
    return rows


def _summary_row_to_out(row: dict[str, Any],
                        regions: list[dict[str, Any]]) -> DailySummaryOut:
    return DailySummaryOut(
        reportDate=row["report_date"],
        totalCases24h=row["total_cases_24h"],
        totalDeaths24h=row["total_deaths_24h"],
        totalCasesYtd=row.get("total_cases_ytd"),
        totalDeathsYtd=row.get("total_deaths_ytd"),
        dhakaCityCases24h=row.get("dhaka_city_cases_24h"),
        outsideDhakaCases24h=row.get("outside_dhaka_cases_24h"),
        regionalBreakdowns=[
            RegionalBreakdownOut(
                divisionName=r.get("division_name"),
                districtName=r["district_name"],
                cases24h=r.get("cases_24h", 0),
                deaths24h=r.get("deaths_24h", 0),
            )
            for r in regions
        ],
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("/latest", response_model=DailySummaryOut,
            summary="Newest reporting day, with its regional breakdown")
def latest() -> DailySummaryOut:
    rows = _get("daily_summaries", {
        "select": "*", "order": "report_date.desc", "limit": 1,
    })
    if not rows:
        raise HTTPException(404, "no data has been ingested yet")

    summary = rows[0]
    regions = _get("regional_breakdowns", {
        "select": "division_name,district_name,cases_24h,deaths_24h",
        "report_date": f"eq.{summary['report_date']}",
        "order": "district_name.asc",
    })
    return _summary_row_to_out(summary, regions)


@router.get("/history", response_model=list[HistoryPointOut],
            summary="Daily national figures, oldest first, for charting")
def history(days: int = Query(30, ge=1, le=365)) -> list[HistoryPointOut]:
    since = (datetime.now(DHAKA).date() - timedelta(days=days)).isoformat()
    rows = _get("daily_summaries", {
        "select": "report_date,total_cases_24h,total_deaths_24h",
        "report_date": f"gte.{since}",
        "order": "report_date.asc",
    })
    # Sorted here as well as in the query. A chart plots the array in the order
    # it arrives, so the ordering guarantee belongs to this endpoint rather than
    # to whatever the database happens to return.
    rows.sort(key=lambda r: r["report_date"])
    return [
        HistoryPointOut(
            reportDate=r["report_date"],
            totalCases24h=r["total_cases_24h"],
            totalDeaths24h=r["total_deaths_24h"],
        )
        for r in rows
    ]


@router.get("/districts/{district_name}", response_model=list[DistrictPointOut],
            summary="History for one district")
def district(
    district_name: str = Path(min_length=1, max_length=64),
    days: int = Query(90, ge=1, le=365),
) -> list[DistrictPointOut]:
    since = (datetime.now(DHAKA).date() - timedelta(days=days)).isoformat()
    rows = _get("regional_breakdowns", {
        "select": "report_date,division_name,district_name,cases_24h,deaths_24h",
        # ilike rather than eq: callers send "dhaka", DGHS writes "Dhaka".
        "district_name": f"ilike.{district_name}",
        "report_date": f"gte.{since}",
        "order": "report_date.asc",
    })
    rows.sort(key=lambda r: r["report_date"])
    if not rows:
        raise HTTPException(404, f"no data for district '{district_name}'")
    return [
        DistrictPointOut(
            reportDate=r["report_date"],
            districtName=r["district_name"],
            divisionName=r.get("division_name"),
            cases24h=r.get("cases_24h", 0),
            deaths24h=r.get("deaths_24h", 0),
        )
        for r in rows
    ]
