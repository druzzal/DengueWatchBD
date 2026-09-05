# DGHS data pipeline

How official Bangladesh dengue figures reach the app, and what happens when
they cannot.

DengueWatch is an independent application that uses official DGHS data. It is
not a DGHS product and is not endorsed by DGHS.

## Architecture

```
DGHS dashboard  ──┐
                  ├─► ingestion (server/dghs) ─► validation ─► cross-check
DGHS press PDFs ──┘                                                 │
                                                                    ▼
                                       public/surveillance.json  (canonical)
                                       public/previous.json      (last known good)
                                       public/status.json        (freshness)
                                       public/ingestion-runs.json(audit trail)
                                                                    │
                                        raw.githubusercontent.com   │
                                                                    ▼
                              iOS SurveillanceService (conditional GET)
                              Android (planned, same endpoint)
```

**The apps never touch DGHS.** They know one URL and one schema. If DGHS
changes its HTML tomorrow, the pipeline fails loudly and the apps keep showing
the last good dataset — they do not break, and they do not silently show
nothing.

## Sources

| Role | Source | Module |
|---|---|---|
| Primary | `https://dashboard.dghs.gov.bd/pages/heoc_dengue_v1.php` | `dghs/dashboard.py` |
| Fallback / detail | Daily press-release PDFs on `old.dghs.gov.bd` | `dghs/fetch.py`, `dghs/parse.py` |

DGHS publishes no JSON or AJAX API. The dashboard embeds its figures in
Highcharts constructor calls, so the parser reads those rather than scraping
rendered pixels, DataTables markup, or map tiles.

### Why series are identified by name, not position

`dashboard.py` keys every series on its Highcharts **container id plus series
name** (`HIGH_CONFIDENCE` in that module). An earlier version keyed on chart
order and silently reported 41,891 deaths in a month when DGHS reordered its
charts. Charts that cannot be identified unambiguously are listed in
`KNOWN_BUT_UNUSED` and excluded — never guessed. Reordering the page changes
nothing; a test enforces this (`test_reordering_charts_does_not_change_results`).

## Canonical dataset

`public/surveillance.json`:

| Key | Meaning |
|---|---|
| `meta` | dataset name, disclaimer, attribution, season start, `lastUpdated`, `primarySource`, `parserVersion`, `isSampleData` |
| `dates` | reporting dates actually used, ascending |
| `national` | per-date national series |
| `districts` | 64 districts: code, name, division, coordinates, population, series |
| `history` | per-season totals, with a `verified` flag |

Absent data is omitted or explicitly null. Nothing is invented or back-filled.
`lastUpdated` is the **source reporting date**, not the ingestion time; the
ingestion time lives in `ingestion-runs.json`, and the app's own last
successful fetch is separate again and stored on device.

## Validation

`dghs/validation.py` separates two kinds of finding:

- **Rejections** discard the day: missing figures, negative counts, cumulative
  totals moving backwards beyond DGHS's own revisions, district sums that do
  not reconcile with the national total in the same PDF.
- **Anomalies** are recorded but published: real spikes happen, and suppressing
  them would misrepresent an outbreak.

A rejected day does not advance the running "previous" baseline, so one bad day
cannot cascade into rejecting every day after it
(`test_rejection_does_not_cascade`).

Structural failure — a chart the parser can no longer identify — raises rather
than returning a plausible-looking zero.

## Cross-check

`dghs/crosscheck.py` compares the two DGHS surfaces **only when they describe
the same date**. Comparing a dashboard dated 4 Sep with a press release dated
3 Sep once produced a false "disputed" verdict; it now reports
`not_comparable` instead. Genuine same-date disagreement is recorded in
`public/source-discrepancies.json` and never resolved in favour of one source.

## Change detection and last known good

`dghs/publish.py` takes a `sha256` over the dataset **excluding `meta`**, since
`meta` carries timestamps that change every run. If the digest matches what is
already published, nothing is written and the run is recorded as `no_change`.

When the digest differs, the outgoing `surveillance.json` is copied to
`previous.json` before the new one is written. Both writes go through a
temporary file and `os.replace`, so an interrupted run cannot leave truncated
JSON where a valid dataset used to be. `previous.json` is only ever written
from a dataset that already passed validation.

## Freshness

`status.json` carries a `freshness` field, judged against DGHS's daily cadence:

| Value | Meaning |
|---|---|
| `fresh` | newest report ≤ 3 days old |
| `stale` | 4–7 days old |
| `outdated` | more than 7 days old |
| `unknown` | no usable reporting date |

The iOS app applies the same thresholds (`AppConfig.stalenessThreshold`,
`AppConfig.outdatedThreshold`) so app and server never disagree about the same
dataset. When the app is showing cached data *and* its last check failed, it
says so rather than letting the age alone imply DGHS simply published nothing.

## Schedule

`.github/workflows/update-dengue-data.yml`, job `build`:

```yaml
- cron: "0 3 * * *"    # 09:00 Dhaka
- cron: "0 12 * * *"   # 18:00 Dhaka
```

Two passes because DGHS publishes during the working day, not first thing: a
single morning run scraped a source that had not updated yet and left the data
a day behind. The early figure is also not final — DGHS revises after
publishing — so `RETRY_RECENT_DAYS = 3` lets a corrected figure overwrite a
provisional one.

GitHub Actions cron is UTC. Dhaka is UTC+6.

Manual trigger: **Actions → Update dengue data → Run workflow**. It accepts an
optional `start` date; leaving it empty defaults to 1 January of the current
year.

## Failure behaviour

| Failure | Result |
|---|---|
| Source unreachable | retries with backoff, then the day is skipped; recent days retried for 3 days |
| A day fails validation | that day is dropped; the rest still publish |
| Payload fails validation | nothing is written; run recorded as `error`; job exits non-zero |
| Parser cannot identify a chart | raises; no partial data published |
| Nothing changed | no write, run recorded as `no_change` |

The last good dataset is never replaced by empty, partial, or zeroed data.

## iOS data flow

```
SurveillanceSync ──► SurveillanceService.fetchIfChanged()
                          │  If-None-Match / If-Modified-Since
                          ├─ 304 ──► .notModified, keep cache
                          └─ 200 ──► decode, validate, write cache
                                        │
                                   SurveillanceStore ──► views
```

- Endpoint: `AppConfig.surveillanceEndpoint`
- Cache: `Library/Application Support/surveillance-cache.json` plus
  `surveillance-validators.json` (the stored ETag)
- Throttle: `AppConfig.minimumSyncInterval` (6 h), skipped only when a cached
  payload actually exists
- Offline: cached data is shown with its age; the dashboard is never blank
  because the network is down
- Bundled `Resources/surveillance.json` is the first-launch seed only

## Running it locally

```sh
cd server
python3 -m venv venv && ./venv/bin/pip install -r requirements-dev.txt
./venv/bin/python -m pytest tests/ -q                       # unit tests, no network
./venv/bin/python -m dghs.cli --start 2026-01-01 --out ../public/surveillance.json
```

Unit tests use stored fixtures and never touch the live site. The CLI run above
is the live integration test.

## When DGHS changes its page

1. Run the CLI. A structural change raises rather than publishing.
2. Check `public/ingestion-runs.json` for the failing run and its message.
3. Open the dashboard HTML and find the `Highcharts.chart('<id>', …)` block.
4. Update `HIGH_CONFIDENCE` in `dghs/dashboard.py` — match on container id and
   series name, never on position.
5. Bump `PARSER_VERSION`.
6. Add a fixture and a test for the new shape before relying on it.

`server/docs/dghs-source-mapping.md` records which chart each published field
comes from.
