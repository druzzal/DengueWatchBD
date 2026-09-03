"""Sanity checks applied before anything is written.

Two kinds of problem, treated differently:

  * `Rejection` — the record is impossible (negative counts, a report dated in
    the future, a cumulative total that went backwards by more than DGHS's
    observed revision behaviour). These stop the record being written.
  * `Anomaly` — the record is surprising but possible: a large single-day jump.
    Dengue genuinely spikes, so these are logged for observability and let
    through. Rejecting real outbreak data would be the worse failure.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, timedelta


@dataclass
class Finding:
    code: str
    detail: str


@dataclass
class ValidationResult:
    rejections: list[Finding] = field(default_factory=list)
    anomalies: list[Finding] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.rejections

    def summary(self) -> str:
        return (f"{len(self.rejections)} rejection(s), "
                f"{len(self.anomalies)} anomaly(ies)")


# A single day's national count above this is treated as suspicious. The worst
# day of the 2023 outbreak was around 2,700, so 10,000 is comfortably clear of
# anything real while still catching a parsing error that shifts a digit.
IMPLAUSIBLE_DAILY_CASES = 10_000
# Cumulative figures may be revised down slightly; a large drop means the parse
# picked up the wrong number.
MAX_DOWNWARD_REVISION = 500


def validate_daily(report_date: date,
                   cases: int | None,
                   deaths: int | None,
                   previous_date: date | None = None,
                   previous_cumulative: int | None = None,
                   cumulative: int | None = None,
                   today: date | None = None) -> ValidationResult:
    result = ValidationResult()
    today = today or date.today()

    if cases is None or deaths is None:
        result.rejections.append(Finding("missing", "cases or deaths absent"))
        return result

    if cases < 0:
        result.rejections.append(Finding("negative_cases", f"{cases}"))
    if deaths < 0:
        result.rejections.append(Finding("negative_deaths", f"{deaths}"))

    if report_date > today:
        result.rejections.append(
            Finding("future_date", f"{report_date} is after {today}"))

    if previous_date and report_date < previous_date:
        result.rejections.append(
            Finding("out_of_order", f"{report_date} precedes {previous_date}"))

    if cumulative is not None and previous_cumulative is not None:
        drop = previous_cumulative - cumulative
        if drop > MAX_DOWNWARD_REVISION:
            result.rejections.append(
                Finding("cumulative_reversal",
                        f"total fell {drop:,} from {previous_cumulative:,}"))

    if cases > IMPLAUSIBLE_DAILY_CASES:
        result.rejections.append(
            Finding("implausible_daily", f"{cases:,} cases in one day"))
    elif previous_cumulative and cases > 0:
        # Surprising but possible — dengue does spike. Log, do not block.
        if cases > max(200, previous_cumulative * 0.15):
            result.anomalies.append(
                Finding("large_jump", f"{cases:,} cases in a single day"))

    if deaths > cases and cases >= 0:
        result.anomalies.append(
            Finding("deaths_exceed_cases", f"{deaths} deaths, {cases} cases"))

    return result
