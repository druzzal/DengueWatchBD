"""The newest national figures, when the dashboard is ahead of the PDFs.

The published series is built from the daily press-release PDFs, because only
they carry per-district numbers. When that host is unreachable — as it has been
for days at a time — the series stops advancing even though the DGHS dashboard
has published newer national totals.

Extending the series with dashboard days is not an option: it has no
per-district figures, and padding each district with zeros would drag every
district's 14-day incidence down, understating local risk. On a health app that
is the wrong direction to be wrong in.

So the newer national figures travel separately, with their own date and their
own provenance, and the series keeps saying exactly what it can support.
"""

from __future__ import annotations

from datetime import date
from typing import Any

from .source import DGHSSnapshot


def build_latest(snapshot: DGHSSnapshot | None,
                 series_as_of: date) -> dict[str, Any] | None:
    """Return the `latest` block, or None when the series is already current.

    None is the normal, healthy case: it means the PDFs are keeping up and
    there is nothing the dashboard can add.
    """
    if snapshot is None:
        return None

    national = snapshot.national
    reported = national.report_date
    if reported is None or reported <= series_as_of:
        return None

    if national.total_cases is None or national.total_deaths is None:
        # Without season totals there is nothing worth carrying: the 24-hour
        # figures alone cannot update a headline that counts the season.
        return None

    block: dict[str, Any] = {
        "reportDate": reported.isoformat(),
        "seasonCases": national.total_cases,
        "seasonDeaths": national.total_deaths,
        "cases24h": national.cases_24h,
        "deaths24h": national.deaths_24h,
        "source": "DGHS dashboard",
        # What the charts and the district map actually cover. A reader must be
        # able to tell that the headline is newer than the breakdown.
        "seriesAsOf": series_as_of.isoformat(),
    }
    return {k: v for k, v in block.items() if v is not None}
