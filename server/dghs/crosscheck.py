"""Compare the two DGHS surfaces against each other.

The dashboard and the daily press releases are published from the same
surveillance system but rendered independently, so agreement between them is
real evidence and disagreement is a signal worth keeping.

The rule is deliberately conservative: when they disagree, neither value
silently wins. The discrepancy is recorded and the figure is marked unverified,
because a public-health app should not quietly pick a number.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone


@dataclass
class Discrepancy:
    report_date: str
    metric: str
    dashboard_value: int | None
    press_release_value: int | None
    difference: int | None
    detected_at: str
    status: str = "open"


@dataclass
class CrossCheckResult:
    verified: bool
    checked: list[str] = field(default_factory=list)
    discrepancies: list[Discrepancy] = field(default_factory=list)
    #: False when the two surfaces describe different dates, so no comparison
    #: was possible. Distinct from a genuine disagreement.
    comparable: bool = True

    @property
    def verification_status(self) -> str:
        if not self.comparable:
            return "not_comparable"
        if not self.checked:
            return "unverified"
        return "cross_checked" if self.verified else "disputed"

    def as_dicts(self) -> list[dict]:
        return [asdict(d) for d in self.discrepancies]


def cross_check(report_date: str,
                dashboard_cases: int | None,
                dashboard_deaths: int | None,
                press_cases: int | None,
                press_deaths: int | None,
                dashboard_date: str | None = None) -> CrossCheckResult:
    """Compare season totals from both surfaces, *for the same date*.

    The two surfaces are almost never as-of the same day: the dashboard shows
    today, while a day's press release is published the following morning, so a
    build ending yesterday is compared against a dashboard already carrying
    today. Comparing those totals is meaningless — the difference is elapsed
    time, not disagreement.

    The first CI run did exactly that and reported `disputed` for a 1,252-case
    gap that was simply one extra day of dengue. When the dates differ the
    result is `not_comparable`, which is honest, rather than a false alarm that
    would fire almost daily and drown out a real discrepancy.
    """
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    result = CrossCheckResult(verified=True)

    if dashboard_date is not None and dashboard_date != report_date:
        result.verified = False
        result.comparable = False
        return result

    for metric, left, right in (("total_cases", dashboard_cases, press_cases),
                                ("total_deaths", dashboard_deaths, press_deaths)):
        if left is None or right is None:
            continue
        result.checked.append(metric)
        if left != right:
            result.verified = False
            result.discrepancies.append(Discrepancy(
                report_date=report_date,
                metric=metric,
                dashboard_value=left,
                press_release_value=right,
                difference=left - right,
                detected_at=now,
            ))

    if not result.checked:
        result.verified = False
    return result
