# DengueWatch Bangladesh

An iOS dengue surveillance app for Bangladesh: national and district-level case
tracking, a WHO-criteria symptom check, a personal case log, prevention
guidance, and local alerts when your own district gets worse.

- **SwiftUI + Swift Charts + MapKit**, iOS 17.0 and up, iPhone and iPad.
- **No backend, no account, no analytics, no location permission.** Everything
  the user enters stays in the app container.

## Building

```sh
open ios/DengueWatchBD.xcodeproj
```

The project uses an Xcode 16+ synchronized file group, so new files added under
`ios/DengueWatchBD/` are picked up without editing the project file.

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
| **Overview** | National totals, epidemic curve with a scrubable 7-day average, hospital census, deaths, districts to watch, season history back to 2019. Language toggle lives here. |
| **Map** | 64 districts as proportional symbols, by total cases or 14-day rate per 100k. Shows your live location and which district you are standing in, with that district's risk band. A searchable list view doubles as the offline and screen-reader path. |
| **Check** | WHO warning-sign triage with an original illustration per symptom, fever-phase awareness, higher-risk-group handling, and a personal log. |
| **Care** | Emergency numbers, live nearby-hospital search through Maps, and a directory of major government dengue hospitals with directions. |
| **Prevent** | Five prevention topics, the seasonal calendar, district risk alerts and the enter-a-high-risk-area warning. |

## Bilingual

Full Bengali and English, switched in-app (not by device language) from the home
screen. 352 string keys per language, checked for parity. Bengali also gets:

- **Bengali numerals** everywhere — `১.৮ লাখ`, not `178k`.
- **Bengali magnitude words** — হাজার / লাখ / কোটি rather than k / M, because
  "১০১k" is not how a number is read in Bengali.
- **Bengali place names** for all 64 districts and 8 divisions.
- **More leading** on every text style, because Bengali carries the matra
  headline and deeper descenders than Latin at the same point size.
- **Localised permission prompts** via `bn.lproj/InfoPlist.strings`, which iOS
  shows according to *system* language.

A missing Bengali key trips an assertion in debug and falls back to English in
release, so a gap degrades to readable text rather than a blank label.

## Automatic updates

`SurveillanceSync` refreshes on launch, on foreground, and on the offline→online
edge — only that edge, so a flapping connection doesn't hammer the server. It
uses a conditional GET (`If-None-Match` / `If-Modified-Since`) against an on-disk
cache, so a daily check costs almost nothing when nothing changed.

**`AppConfig.surveillanceEndpoint` is still `nil`, because this needs a host
rather than more code.** DGHS publishes its daily dengue figures only as PDF
press releases, so [`server/`](server/) parses them into the
`SurveillancePayload` shape:

```sh
cd server
python3 -m venv venv && ./venv/bin/pip install -r requirements.txt
./venv/bin/python -m dghs.cli --start 2026-01-01 --out surveillance.json
```

Publish that JSON anywhere the app can GET it and set `surveillanceEndpoint` to
its URL. Nothing else changes. See [server/README.md](server/README.md) — in
particular why the parser refuses to emit data that does not reconcile against
the PDF's own national totals, and how it copes with DGHS using several legacy
Bengali fonts that mangle district names differently on different days.

## Location

Three uses, all evaluated on the device, none uploaded:

1. **Live location on the map** — the standard blue dot, plus a "You are in
   *district*" row carrying that district's risk band. Tapping the row zooms to
   you; a second control returns to the whole country.

   `MapUserLocationButton` is deliberately *not* used: it flips the bound camera
   into follow mode as soon as the first fix lands, which throws a national
   surveillance map to street level uninvited. The controls are hand-rolled so
   the map opens on the country and only moves when asked.

   Nearest-district lookup compares against district *centres*, so it is an
   approximation, and it is bounded — beyond 120 km from any centre the app says
   you are outside the covered area rather than naming the closest district.

2. **High-risk area warning** — `CLCircularRegion` monitoring of up to 20 of the
   worst districts (iOS caps region monitoring at 20). Needs "Always"
   authorization to fire with the app closed; without it the warning only works
   while the app is open, and the settings screen says which state you are in.
   Rate-limited to one notification per district per day.
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

`ios/DengueWatchBD/Resources/surveillance.json` holds the whole dataset: a shared
date axis, national daily series, 64 districts across 8 divisions with
coordinates and population, and annual totals back to 2019.

**The bundled dataset is real.** It is built by [`server/`](server/) from 198
DGHS daily press releases covering the 2026 season to 2 September: 38,280 cases
and 107 deaths nationally, broken down across all 64 districts. Annual totals
from 2019 onward are the published DGHS figures.

The app ships with this as its offline fallback, so it shows real surveillance
data with no network at all. It does **not** update by itself yet — see below.

### Keeping it current

`SurveillanceService` is the only type that knows where bytes come from:

```swift
protocol SurveillanceService: Sendable {
    func fetch() async throws -> SurveillancePayload
}
```

`BundledSurveillanceService` reads the bundled JSON. `RemoteSurveillanceService`
is written and ready — point it at a DGHS-shaped endpoint and pass it to
`SurveillanceStore(service:)` in `RootView`. No view changes are needed.

## Structure

One repository, three pieces that share a single contract — the published
`surveillance.json`. The backend serves both apps; neither app has a backend of
its own.

```
ios/            the SwiftUI app (below)
android/        the Kotlin/Compose app, domain layer ported from ios/Models
server/         DGHS ingestion: scrapers, parser, validation, cross-check
public/         what the pipeline publishes, and what both apps fetch
Tools/          helper scripts
```

Inside `ios/DengueWatchBD/`:

```
App/            entry point, tab shell, about + first-run disclaimer
Models/         wire format, District, RiskLevel, series maths
Localization/   AppLanguage, NumberStyle, the two string tables, place names
Data/           store, service protocol, sync, case log, preferences, config
Design/         Theme.swift (validated palette), Typography.swift (type scale)
Features/
  Dashboard/    stat tiles, epidemic curve, admissions, deaths, season history
  Map/          proportional-symbol map, district list, district detail
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
