"""Where DGHS data comes from.

Two adapters, one interface. The rest of the pipeline must not care which is
in use, so a change at the source is a change in exactly one file.

    DGHSDataSource
        ├── DGHSDashboardSource     — the HEOC dashboard page
        └── DGHSPressReleaseSource  — the daily PDF press releases

There is no public JSON or AJAX endpoint. The dashboard page was inspected:
it loads only client-side libraries (DataTables, Highcharts, Google Maps) and
its figures are rendered server-side into the HTML as Highcharts series. So the
"structured endpoint" is the page itself, and both adapters are scrapers — but
the dashboard's embedded arrays are genuinely structured data rather than
free text, which makes them far more robust to parse than the PDF tables.

The two sources are complementary, not redundant:

  * The dashboard carries division-level totals, a monthly series and the
    year-by-year history, already aggregated.
  * The press releases carry all 64 districts and the demographic tables,
    which the dashboard does not break out.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import date


@dataclass
class NationalTotals:
    report_date: date | None = None
    total_cases: int | None = None
    total_deaths: int | None = None
    cases_24h: int | None = None
    deaths_24h: int | None = None
    current_hospitalised: int | None = None
    discharged: int | None = None


@dataclass
class AreaCount:
    """A count for one named area at a stated geographic level."""
    level: str          # "division" | "district" | "city_corporation"
    name: str
    cases: int | None = None
    deaths: int | None = None


@dataclass
class PeriodCount:
    """A count for a labelled period — a month or a year."""
    period: str
    cases: int | None = None
    deaths: int | None = None


@dataclass
class DGHSSnapshot:
    """Everything one source could extract in a single fetch.

    Fields a source cannot supply stay empty rather than being filled with
    zeros — a missing value and a genuine zero must never be confused.
    """
    source: str
    source_url: str
    fetched_at: str
    # Provenance travels with the data, so any figure can be traced to the
    # surface and the parser that produced it.
    source_type: str = "dashboard"
    parser_version: str = "unknown"

    national: NationalTotals = field(default_factory=NationalTotals)
    areas: list[AreaCount] = field(default_factory=list)
    daily: list[PeriodCount] = field(default_factory=list)
    daily_deaths: list[PeriodCount] = field(default_factory=list)
    monthly: list[PeriodCount] = field(default_factory=list)
    yearly: list[PeriodCount] = field(default_factory=list)
    #: Series that were present but not trusted, with the reason.
    skipped: list[str] = field(default_factory=list)

    @property
    def is_empty(self) -> bool:
        return not (self.areas or self.daily or self.monthly or self.yearly
                    or self.national.total_cases is not None)


class DGHSSourceError(RuntimeError):
    """The source could not be read or did not look the way we expect."""


class DGHSDataSource(ABC):
    """One fetch returns one snapshot, or raises."""

    name: str = "DGHS"
    url: str = ""

    @abstractmethod
    def fetch(self) -> DGHSSnapshot:
        ...
