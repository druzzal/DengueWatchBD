# DGHS dengue data pipeline

Turns the Directorate General of Health Services' **daily dengue press releases**
into the JSON [DengueWatch](../) reads, so the app shows real surveillance data
instead of the simulated dataset it ships with.

DGHS publishes no machine-readable feed — the daily figures exist only as PDFs —
so this parses them.

## Quick start

```sh
python3 -m venv venv && ./venv/bin/pip install -r requirements.txt

# Backfill the whole season, then publish the result somewhere the app can GET.
./venv/bin/python -m dghs.cli --start 2026-01-01 --out surveillance.json
```

Then point the app at it, in `ios/DengueWatchBD/Data/AppConfig.swift`:

```swift
static let surveillanceEndpoint = URL(string: "https://your-host/surveillance.json")
```

That is the only app-side change. The sync layer — conditional GET, on-disk
cache, refresh on reconnect — is already built.

## Where the data comes from

```
https://old.dghs.gov.bd/images/docs/vpr/YYYYMMDD_dengue_all.pdf
```

One PDF per day, at a predictable path, so there is no index to scrape. Each
release carries year-to-date cumulative figures for all 64 districts plus Dhaka
city corporation, which is reported separately and folded into Dhaka district.

The district table columns are: new admissions in the last 24h (government,
private, total), then cumulative admitted, deaths, discharged, and currently
admitted — all since 1 January.

## Why it refuses to run more often than it runs

A health app showing wrong district numbers is worse than one showing none, so
the parser fails loudly rather than emitting anything doubtful. Every run is
checked against:

- **The PDF's own national totals.** District cases and deaths must sum exactly
  to the figures printed on the summary page. Any mismatch aborts.
- **All 64 districts present.** A short table aborts.
- **An internal identity, per district:** `admitted − discharged − deaths ==
  currently admitted`. This is what confirmed the column semantics in the first
  place, and it catches a misread column immediately.
- **Season coverage.** The app derives "cases this season" by summing the daily
  series. Because DGHS publishes cumulative figures, a window starting in August
  produces a series that sums to far less than the true season total. The CLI
  refuses to write in that case and tells you to backfill from January, unless
  you pass `--allow-partial`.

Output is written atomically, and only after all checks pass.

## The Bengali font problem

The district table is typeset with legacy Bengali fonts, so extracted text is
mangled and inconsistent — and **mangled differently on different days**:

| District | 2 Sep encoding | 27 Aug encoding | January encoding |
|---|---|---|---|
| Faridpur | `ফরিদপুি` | `ফরিদপযি` | `ফরিদপুি` |
| Shariatpur | `িীয়তপুি` | `িীয়তপযি` | `শিীয়তপুি` |
| Rajshahi | `িাজ াহী` | `িাজ াহী` | `িাজশাহী` |

Fuzzy matching is not safe here: Madaripur's mangled form best-matches
*Chandpur*, and silently attributing one district's cases to another is exactly
the failure this app cannot have.

Instead `dghs/district_aliases.json` maps exact mangled strings to district
codes. Anything unrecognised raises. The table is not hand-typed — it is
generated positionally, because the district *order* in the report is stable:

```sh
# Harvest every encoding used across a season of cached releases.
./venv/bin/python tools_make_aliases.py .cache/*.pdf --write
```

The generator cross-checks every alias it already knows against the position it
would infer, and refuses to write if any disagree — so if DGHS ever reorders the
table, you find out instead of getting silently wrong data.

## Layout is not stable either

The summary page is page 1 in some releases and page 7 in others, and the
document is 10 or 11 pages depending on the day. Nothing here assumes a page
index; pages are searched for what they contain.

## Running it daily

`.github/workflows/update-dengue-data.yml` runs the build each morning and
commits the result. Point it at wherever you host the JSON.

Be a considerate client: requests are paced one per second with a descriptive
User-Agent, and PDFs are cached on disk so a re-run costs one request per new
day, not one per day of the season.

## Where the DGHS data actually comes from

Two public surfaces, no API behind either. This was established by fetching the
dashboard and inspecting it, not assumed:

**1. The HEOC dashboard** — `dashboard.dghs.gov.bd/pages/heoc_dengue_v1.php`

No JSON, no AJAX, no REST endpoint. The page loads only client-side libraries
(DataTables, Highcharts, Google Maps) and its figures are rendered server-side
into Highcharts arrays. The page *is* the structured source.

It carries division totals, a monthly series, age and sex breakdowns and a
year-by-year history — and all of it parses cleanly. **Only the year history is
used.** The arrays are structured but not self-describing: the chart definitions
sit in a JavaScript block with no ids, titles or adjacent headings, so telling
"division cases this season" from "division cases in the last 24 hours" depends
purely on the order charts appear in the file.

That was built first and it is a real trap. Keyed on position, it reported
41,891 dengue deaths in July and read the 24-hour division figures as season
totals — both plausible-looking, both wrong, and both would fail silently the
moment DGHS reorders a chart. `test_dashboard_does_not_guess_unlabelled_series`
asserts those series stay empty.

The year series is safe because four-digit-year categories identify it
regardless of position, and its values check against independently published
totals. It also cross-checks the other source: the dashboard reports 2026 as
38,280, matching the press releases exactly.

**2. The daily press releases** — `old.dghs.gov.bd/images/docs/vpr/YYYYMMDD_dengue_all.pdf`

The authoritative source for daily and district figures. Every number is
reconciled against the document's own stated national totals before anything is
written.

## Reliability

`dghs/validation.py` separates two kinds of problem. **Rejections** stop a
record being written: negative counts, a report dated in the future, a
cumulative total that fell further than DGHS's observed revision behaviour.
**Anomalies** are logged and let through: a large single-day jump is surprising
but dengue genuinely spikes, and discarding real outbreak data would be the
worse failure.

`dghs/runlog.py` records every attempt to `ingestion-runs.json` and derives
`status.json`:

    healthy    — the last run succeeded
    no_change  — DGHS published nothing newer; existing data untouched
    stale      — the newest report is more than three days old, measured
                 against DGHS's daily cadence
    error      — the last run failed; previous data preserved

A failed run never overwrites a good dataset: the CLI writes nothing unless
every check passes, and the workflow only commits when `public/` actually
changed.

## Optional Supabase

`supabase_schema.sql` is provided but **not applied or tested** — provisioning a
project needs your account. The pipeline does not require it. Publishing a
static JSON file that the app fetches with a conditional GET already satisfies
the requirement, costs nothing to host, and has no privileged credential to
leak. Add the database when you want queryable history or multiple consumers,
not before.


## What a season of real releases taught this parser

None of the following was visible from a single PDF. Each was found by running
the pipeline across all 243 days of the 2026 season and reading the failures.

- **The table lists only districts that have reported cases.** On 1 January 2026
  it had 28 rows, not 64, growing through the season. An "expected 64 rows"
  check was an artifact of testing on a September release.
- **A district can therefore vanish and reappear.** Differencing naively would
  register the reappearance as a huge one-day spike, so the builder carries each
  district's last known cumulative forward.
- **DGHS revises district figures downward** — 15 times, 129 cases in total,
  across the 2026 season. A daily series cannot hold a negative count, so those
  are clamped to zero, which leaves the district series summing exactly that
  much high. The CLI asserts the gap equals the clamped total precisely, rather
  than tolerating a fuzzy margin.
- **29 days of the season had no release at all**, and 6 more could not be
  parsed. Both are skipped loudly; the cumulative differencing spans the gap
  correctly.

## Tests

```sh
./venv/bin/python -m pytest tests/ -q
```

The fixture is a real press release, committed so the suite runs offline and
regressions are caught against known-good numbers (38,280 cases / 107 deaths /
2,740 in hospital, as published for 2 September 2026).

## Layout

```
dghs/
  fetch.py                 URL construction, caching, retries, 404 handling
  parse.py                 PDF -> DailyReport, with all reconciliation checks
  build.py                 daily reports -> the app's payload (cumulative -> daily)
  districts.py             static reference: names, divisions, centres, population
  district_aliases.json    mangled Bengali -> district code
  cli.py                   entry point and validation
tools_make_aliases.py      regenerate aliases positionally from PDFs
tests/                     parser tests against a committed real release
```

## JSON endpoint (`api/`)

A read-only FastAPI service over the same DGHS figures, for clients that want
a single HTTP call rather than the full published dataset.

```sh
cd server
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
./venv/bin/python -m uvicorn api.main:app --reload --port 8000
```

Then:

```sh
curl http://127.0.0.1:8000/api/dengue-stats
```

```json
{
  "source": { "name": "DGHS", "url": "https://dashboard.dghs.gov.bd/pages/heoc_dengue_v1.php" },
  "retrievedAt": "2026-09-05T20:19:16+06:00",
  "freshness": "live",
  "data": {
    "reportDate": "2026-09-05",
    "cumulative": { "cases": 41032, "deaths": 113 },
    "last24Hours": { "cases": 988, "deaths": 2 },
    "currentlyHospitalised": null
  }
}
```

`freshness` is the field to read before trusting the numbers:

| Value | Meaning |
|---|---|
| `live` | just parsed from DGHS |
| `cached` | parsed within the last 30 minutes |
| `stale` | DGHS unreachable; last good parse, with `error` set |
| `published-fallback` | DGHS unreachable and no cache; the pipeline's last validated dataset |
| `unavailable` | nothing to serve — HTTP 503 |

The service holds no scraper of its own. It calls `dghs.dashboard`, the same
parser the ingestion pipeline uses, so there is one place to fix when DGHS
changes its page. It refreshes at most every 30 minutes rather than on every
request, so client traffic never reaches DGHS directly.

**The iOS app does not use this endpoint** and should not. It reads the
published `surveillance.json`, which carries validation, cross-checking and
last-known-good that a request-time parse cannot. See
`docs/DGHS_DATA_PIPELINE.md`.
