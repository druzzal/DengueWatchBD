# DGHS source mapping

Why each figure is trusted, or is not. The rule: **only display DGHS data whose
semantic meaning can be proven.** A smaller correct dataset beats a larger
plausible one.

## How series are identified

The dashboard renders every chart as:

```js
Highcharts.chart('confirmed_case', {
    xAxis: { categories: ['01-Jan-26', ...] },
    series: [{ name: 'Affected (Admitted) by date', data: [76, 63, ...] }]
});
```

Two independent semantic identifiers — the **container id** and the **series
name** — plus explicit category labels. Nothing is identified by position.

> **Correction.** The first version of this adapter concluded the charts were
> not self-describing and extracted only the annual series. That was wrong: it
> searched for `renderTo`, which this page does not use, and so never saw the
> container ids. Keyed on position, it reported 41,891 dengue deaths in July.
> `test_reordering_charts_does_not_change_results` shuffles the chart blocks and
> asserts the output is byte-identical, so that failure cannot recur.

## Confidence

| Level | Meaning | Used? |
|---|---|---|
| HIGH | container id **and** series name state the meaning, and values reconcile against an independent figure | yes |
| MEDIUM | id suggestive, series unnamed or shape ambiguous | no |
| LOW | meaning would have to be inferred from position | no |

## Trusted series (HIGH)

| Source element | Meaning | Evidence | Extraction | Validation |
|---|---|---|---|---|
| `affected_case_last_24_hour` / `Admitted` | national cases, last 24h | id + series name | scalar | ≥ 0 |
| `death_case_last_24_hour` / `Death` | national deaths, last 24h | id + series name | scalar | ≥ 0 |
| `affected_case_in_year` / `Admitted` | season cases to date | id + series name | scalar | equals sum of daily series |
| `death_case_in_year` / `Death` | season deaths to date | id + series name | scalar | equals sum of daily deaths |
| `dengue_discharged_total_and_24_hours` / `DISCHARGED from 1 January to Till date` | discharged to date | id + series name | scalar | ≥ 0 |
| `confirmed_case` / `Affected (Admitted) by date` | daily national cases | id + series name + one date label per point | 245 pairs | **sums to 38,280 = season total** |
| `death_case` / `Death by date` | daily national deaths | id + series name + date labels | 51 pairs | **sums to 107 = season deaths** |
| `div_city_cor_case_in_year` / `Admitted` | division & city-corporation season cases | id + series name + named categories | 10 areas | **sums to 38,280** |
| `div_city_cor_death_in_year` / `Death` | division & city-corporation season deaths | id + series name | 10 areas | ≥ 0 |
| `year_case` / `Affected` | annual national totals 2018– | id + four-digit-year categories | 9 years | cross-checked against published totals |

Cross-source check: the press-release PDFs independently give 38,280 cases and
107 deaths for 2026. All three dashboard reconciliations agree exactly.

## Excluded, and why (MEDIUM / LOW)

| Source element | Why not used |
|---|---|
| `dengue_affected_by_age_group`, `dengue_death_by_age_group` | series named `Male`/`Female`, but the age bands themselves are not labelled in the block — the bucket boundaries would have to be assumed |
| `dengue_affected_by_gender`, `dengue_death_by_gender` | containers exist but carry no data array in the served page |
| `by_week_case`, `by_month_case` | one chart mixes 2023, 2024 and 2025 series of differing lengths; attributing a value to a year is not safe |
| `division_case`, `division_death` | category list contains duplicated and misspelled labels (`Raishahi` alongside `Rajshahi`), so an area cannot be keyed reliably. `div_city_cor_*_in_year` covers the same ground cleanly and is used instead |

These are logged in every snapshot's `skipped` list, so exclusion is visible at
runtime rather than implicit.

## District-level data

The dashboard reports divisions and the two Dhaka city corporations, **not the
64 districts**. District figures come only from the press-release PDFs, where
every number reconciles against the document's own stated totals. No district
value is ever interpolated from a division total.

## Parser version

`dghs-dashboard-v2`. Recorded in every ingestion run so a stored figure can be
traced to the logic that produced it. Bump on any material extraction change.
