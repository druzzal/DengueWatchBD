# DengueWatch auto-update

Zero-server pipeline for daily DGHS dengue figures.

```
DGHS dashboard ──► GitHub Actions (daily 17:30 Dhaka) ──► Supabase ──► iOS app
```

Nothing here needs a server you run or pay for: GitHub Actions runs the
scraper, Supabase stores the rows and serves them over its auto-generated REST
API, and the app talks to that API directly.

DengueWatch is an independent app that uses official DGHS data. It is not a
DGHS product and is not endorsed by DGHS.

## Layout

```
database/schema.sql          table, index, RLS policy
scraper/scrape_dghs.py       scrape, validate, upsert
.github/workflows/scrape.yml daily automation
iOS/DengueService.swift      drop-in Swift client
requirements.txt
```

## Setup

**1. Supabase.** Create a project, open the SQL editor, paste
`database/schema.sql`, run it. From *Project Settings → API* copy the project
URL, the `anon` key (public, ships in the app) and the `service_role` key
(secret, never ships).

**2. GitHub secrets.** *Settings → Secrets and variables → Actions*:

| Secret | Value |
|---|---|
| `SUPABASE_URL` | `https://<project>.supabase.co` |
| `SUPABASE_SERVICE_KEY` | the `service_role` key |

**3. Run it.** *Actions → Scrape DGHS dengue data → Run workflow*. Tick
**dry_run** first to see what the parser reads without writing anything.

**4. iOS.** Drop `iOS/DengueService.swift` into the Xcode project and construct
it with the project URL and the **anon** key:

```swift
let service = DengueService(
    projectURL: "https://<project>.supabase.co",
    anonKey: "<anon key>"
)
let today = try await service?.latest()
```

## Running the scraper locally

```sh
python3 -m venv venv && ./venv/bin/pip install -r requirements.txt
./venv/bin/python scraper/scrape_dghs.py --dry-run     # nothing is written
SUPABASE_URL=... SUPABASE_SERVICE_KEY=... ./venv/bin/python scraper/scrape_dghs.py
```

Verified live on 2026-09-05: 988 cases, 2 deaths.

## How the parsing works, and how to fix it when DGHS changes

The dashboard draws its figures with Highcharts, so the numbers are arguments
to `Highcharts.chart('<container>', { ... })` calls inside `<script>` tags, not
text in the DOM. Traversing elements finds nothing; the parser reads the
embedded JavaScript instead.

Each figure is looked up by **container id and series name**, never by
position:

| Figure | Container | Series |
|---|---|---|
| cases in 24h | `confirmed_case` | `Affected (Admitted) by date` |
| deaths in 24h | `death_case` | `Death by date` |

with `affected_case_last_24_hour` / `death_case_last_24_hour` as named
alternates. If none match, the run **fails** rather than falling back to a
guess. That is deliberate: an earlier draft of this script fell back to a loose
regex over the page text and returned **24 deaths** for a day DGHS reported
**2**, and no validation rule could catch it, because 24 deaths against 988
cases is entirely plausible. A failed run is recoverable; a plausible wrong
number is not.

To repair the parser after a DGHS change:

1. Run with `--dry-run`. The log prints every container id found on the page.
2. Open the page source, find the `Highcharts.chart('<id>'` block you need.
3. Add the `(container, series name)` pair to `CASE_SERIES` or `DEATH_SERIES`.

## What is not published

`dhaka_cases_24h` and `outside_dhaka_cases_24h` are **null**. The dashboard
does not break the daily figure down that way, and the columns are nullable
rather than defaulted to `0` on purpose: storing zero would assert "no cases in
Dhaka today", which DGHS never said. If you need that split, it appears in the
daily press-release PDFs, which this script does not read.

## Security

Row Level Security is on, with a single policy granting `SELECT` to `anon` and
`authenticated`. No policy grants insert, update or delete. The scraper writes
with the `service_role` key, which bypasses RLS.

That combination is what makes shipping the anon key in the app safe: someone
who extracts it from the binary can read public case counts, which is the
point, and cannot alter them. Putting the service key in the app would hand
every user the ability to rewrite the national dengue figures.
