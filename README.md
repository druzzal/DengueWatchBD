# DengueWatch Bangladesh

An iOS dengue surveillance app for Bangladesh: national and area-level case
tracking, a WHO-criteria symptom check, a personal case log, prevention
guidance, and local alerts when your own area gets worse.

- **SwiftUI + Swift Charts + MapKit**, iOS 17.0 and up, iPhone and iPad.
- **No backend, no account, no analytics, no location permission.** Everything
  the user enters stays in the app container.

## Building

```sh
open DengueWatchBD.xcodeproj
```

The project uses an Xcode 16+ synchronized file group, so new files added under
`DengueWatchBD/` are picked up without editing the project file.

Requires an installed iOS simulator runtime — `actool` refuses to compile the
asset catalog without one, even for a device build. If a build fails with
"No available simulator runtimes for platform iphonesimulator", run
`xcodebuild -downloadPlatform iOS`, then `xcrun simctl runtime scan-and-mount`
if `xcrun simctl list runtimes` still comes back empty.

In DEBUG builds the app can open straight onto a given tab, which is what the
screenshot and UI-test runs use:

```sh
SIMCTL_CHILD_DW_START_TAB=map xcrun simctl launch booted bd.denguewatch.app
```

`DW_START_TAB` is one of overview/map/check/care/prevent, and is compiled out of
release builds.

## Features

| Screen | What it does |
|---|---|
| **Overview** | National totals, epidemic curve with a scrubable 7-day average, who is affected by age and sex, deaths, areas to watch, season history back to 2018. Language toggle lives here. |
| **Map** | Ten reporting areas as proportional symbols, by total cases or two-week rate per 100k. Shows your live location and which area you are in, with that area's risk band. A searchable list view doubles as the offline and screen-reader path. |
| **Check** | WHO warning-sign triage with an original illustration per symptom, fever-phase awareness, higher-risk-group handling, and a personal log. |
| **Care** | Emergency numbers, live nearby-hospital search through Maps, and a directory of major government dengue hospitals with directions. |
| **Prevent** | Five prevention topics, the seasonal calendar, area risk alerts and the enter-a-high-risk-area warning. |

## Bilingual

Full Bengali and English, switched in-app (not by device language) from the home
screen. 352 string keys per language, checked for parity. Bengali also gets:

- **Bengali numerals** everywhere — `১.৮ লাখ`, not `178k`.
- **Bengali magnitude words** — হাজার / লাখ / কোটি rather than k / M, because
  "১০১k" is not how a number is read in Bengali.
- **Bengali place names** for all ten reporting areas and eight divisions.
- **More leading** on every text style, because Bengali carries the matra
  headline and deeper descenders than Latin at the same point size.
- **Localised permission prompts** via `bn.lproj/InfoPlist.strings`, which iOS
  shows according to *system* language.

A missing Bengali key trips an assertion in debug and falls back to English in
release, so a gap degrades to readable text rather than a blank label.

## Automatic updates

The app updates itself. `FeedSync` refreshes on launch, on foreground, and on
the offline→online edge — only that edge, so a flapping connection doesn't
hammer the server.

Each refresh is two steps, and the first one usually ends it:

1. GET [`summary.json`](https://druzzal.github.io/dengue-bd-dashboard/data/summary.json)
   (~350 bytes) and compare its `last_updated` — the report date DGHS itself
   stamps — against what is already on screen.
2. Only if that date is newer, GET `latest.json` (~40 KB) for the full
   breakdown, with a conditional GET against the on-disk cache.

DGHS publishes once a day, so most checks cost a few hundred bytes rather than
forty kilobytes. That matters on the metered connections most readers are on.

The feed itself lives in a separate repository,
[dengue-bd-dashboard](https://github.com/druzzal/dengue-bd-dashboard): a GitHub
Action scrapes the DGHS HEOC dashboard every three hours, converts it to JSON,
and commits only when the published figures actually change. Nothing is typed in
by hand, and the same URLs the app reads can be opened in a browser.

There is no API key, no account and no server of our own. The feed is a static
file on GitHub Pages, which is also why it needs no credential shipped inside
the app.

## Location

Three uses, all evaluated on the device, none uploaded:

1. **Live location on the map** — the standard blue dot, plus a "You are in
   *area*" row carrying that area's risk band. Tapping the row zooms to
   you; a second control returns to the whole country.

   `MapUserLocationButton` is deliberately *not* used: it flips the bound camera
   into follow mode as soon as the first fix lands, which throws a national
   surveillance map to street level uninvited. The controls are hand-rolled so
   the map opens on the country and only moves when asked.

   Nearest-area lookup compares against area *centres*, so it is an
   approximation, and it is bounded — beyond 120 km from any centre the app says
   you are outside the covered area rather than naming the closest area.

2. **High-risk area warning** — `CLCircularRegion` monitoring of up to 20 of the
   worst areas (iOS caps region monitoring at 20). Needs "Always"
   authorization to fire with the app closed; without it the warning only works
   while the app is open, and the settings screen says which state you are in.
   Rate-limited to one notification per area per day.
3. **Nearby hospitals** — coarse location handed to `MKLocalSearch`.

There is no community reporting feature. It was built and then removed: without
a server a "community" map shows a user only their own reports, which is not a
community map, and client-side GPS checks cannot make a crowdsourced report
trustworthy on their own. If a backend is ever added, the honest version of that
feature belongs server-side from the start.

## On hospital data

The nearby search returns live results from Apple Maps — that is the trustworthy
path, and it stays correct as places change.

The curated list carries **no phone numbers and no hard-coded coordinates, on
purpose**. Published hospital numbers change often, and a wrong number during a
medical emergency is worse than no number; a stale coordinate can send someone to
the wrong side of a city. Names and cities are stable, so directions are resolved
through Maps. Only three phone numbers are hard-coded — 999, 16263 (Shastho
Batayon) and 333 — because they are national, stable and free to dial.

The list is compiled from publicly known government hospitals. It is **not** an
official DGHS directory, and the screen says so and points at 16263 to check bed
availability before travelling.

## Illustrations

The symptom drawings are original vector paths in a normalised 100×100 space
(`Features/Illustrations/`), not bitmaps. They scale from a 28 pt log row to a
160 pt result screen, adapt to light and dark, add nothing to the bundle, and
raise no licensing questions. Severity is carried by shape as well as tint.


## The data

`DengueWatchBD/Resources/dengue-feed.json` is the offline seed: a copy of the
published feed, so the app shows real figures on first launch with no network at
all. `FeedSync` replaces it with a download as soon as one succeeds.

The feed carries, for the current season:

- **National daily series** — cases every day, deaths on the days they occurred.
  The two are *not* parallel arrays and are joined by parsed date, not by index.
- **Ten reporting areas** — eight divisions plus the two Dhaka city
  corporations, with season cases and deaths that sum exactly to the national
  headline.
- **Weekly series per division**, by epidemiological week.
- **Age and sex breakdown**, which the previous pipeline never carried.
- **Annual totals** back to 2018.

### Geography is division-level, and that is the ceiling

DGHS publishes district-level dengue figures only in the daily PDF press
releases at `old.dghs.gov.bd`. That host became unreachable, and the HEOC
dashboard this feed reads has never carried a district breakdown — so there is
no district feed to rebuild from this source. The app reports the ten areas DGHS
does publish rather than inventing a finer grain.

Dhaka's three feed rows (outside-city, DNCC, DSCC) share one weekly series. Each
one's weekly numbers are apportioned by its share of the division's season
cases, the three still sum to the division's reported weekly total, and the area
page says so in a footnote. Season cases and deaths are reported per area
directly and are never apportioned.

Populations are 2022 BBS census figures, used only as the denominator for
incidence — an approximation there costs a band boundary at worst, never a
headline number.

## Structure

One SwiftUI app reading one published feed. It has no backend of its own; the
ingestion pipeline lives in
[dengue-bd-dashboard](https://github.com/druzzal/dengue-bd-dashboard).

```
DengueWatchBD.xcodeproj
DengueWatchBD/          the app (below)
DengueWatchBDTests/     decoding, mapping, geography and localisation tests
Tools/                  helper scripts
```

Inside `DengueWatchBD/`:

```
App/            entry point, tab shell, about + first-run disclaimer
Models/         FeedPayload (wire format), Domain (Area, Geography, RiskLevel)
Localization/   AppLanguage, NumberStyle, the two string tables, place names
Data/           DengueStore, DengueFeedService, FeedSync, FeedConfig,
                case log, preferences
Design/         Theme.swift (validated palette), Typography.swift (type scale)
Features/
  Dashboard/    stat tiles, case trend, deaths, age/sex breakdown, history,
                shared chart axes
  Map/          proportional-symbol map, area list, area detail
  Triage/       symptom check, triage engine, personal log
  Care/         emergency numbers, hospital directory, nearby search
  Prevention/   prevention topics, seasonal calendar
  Alerts/       notification scheduling, alert + geofence settings
  Location/     the single CoreLocation owner
  Illustrations/ symptom motifs drawn as paths
  Shared/       cards, chips, sparkline, legends, language toggle
```

## Charts

Every colour in `Design/Theme.swift` was run through a palette validator rather
than chosen by eye:

- **Series trio** (cases blue / admissions aqua / deaths red) passes the
  all-pairs colour-vision checks in both light and dark mode. Their CVD
  separation sits in the 6–8 band, which is only legal with secondary encoding,
  so each measure gets its own titled chart plus a legend or direct label — hue
  never carries identity on its own.
- **Risk ramp** is a single-hue ordinal ramp with monotone lightness, stepped
  separately for each mode so the step nearest the surface still clears 2:1.
  It is always drawn next to an icon and the word ("High"), never colour alone.

Cases, deaths and hospital census each get their own card and their own y-axis.
There is no dual-axis chart anywhere in the app.

## Medical scope

The symptom check implements WHO dengue warning-sign criteria to help someone
decide *when to seek care*. It does not diagnose. Severe signs route straight to
"go to hospital now" with a 999 call button, warning signs route to "see a doctor
today", and the NSAID warning appears in every advice path that involves fever.
