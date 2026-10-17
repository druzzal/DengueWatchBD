# DengueWatch Bangladesh

An iOS dengue app for Bangladesh: national and area-level case tracking, a
symptom check and care plan built on WHO's 2025 guideline, a personal health
record to hand to a doctor, prevention guidance, and local alerts when your own
area gets worse.

- **SwiftUI + Swift Charts + MapKit + VisionKit**, iOS 17.0 and up, iPhone and
  iPad.
- **No backend, no account, no analytics.** Location is optional and is only
  used on the device. Everything the user enters stays in the app container.

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
SIMCTL_CHILD_DW_START_TAB=map xcrun simctl launch booted bd.uzzal.denguewatch
```

`DW_START_TAB` is one of home/map/health/care/prevent, and is compiled out of
release builds.

### Tests

```sh
# Unit tests: rules, stores, localisation, PDF
xcodebuild test -project DengueWatchBD.xcodeproj -scheme DengueWatchBD \
  -destination "platform=iOS Simulator,name=iPhone 18 Pro" -only-testing:DengueWatchBDTests

# UI tests: the My health flows, tapped on the real app
xcodebuild test -project DengueWatchBD.xcodeproj -scheme DengueWatchBD \
  -destination "platform=iOS Simulator,name=iPhone 18 Pro" -only-testing:DengueWatchBDUITests
```

The UI tests add a drink, log and undo a urination, complete a symptom check,
delete the latest check and a past one, and export the log to the share sheet.
They launch the app with `DW_UITEST=1`, which (in DEBUG builds only, see
`App/UITestSupport.swift`) starts it empty, in English, past the first-run
disclaimer and without animations; `DW_UITEST_SEED=checks,vitals` adds sample
records. They match English labels, so a reworded button means updating the
test that taps it.

#### Shared clinical cases

`DengueWatchBDTests/clinical-rules.json` holds the cases the iOS and Android
apps must agree on: triage outcomes, the WHO care-plan group and its reasons,
reading ranges, what a typed number is read as, what a scanned report line is
read as, trends, and the fluid log's waking hours. `ClinicalConformanceTests`
runs every case; the Android app runs the same file. Change a clinical rule
here, add or update its case, and copy the file byte for byte to the Android
repository (`app/src/test/resources/clinical-rules.json`), whose tests fail
if the two copies differ.

`DengueWatchBDTests/shared-strings.json` does the same for the copy: every
string key both apps carry, with its English and Bangla wording, plus the
keys each app has on its own by design. `SharedStringsTests` fails when this
app's tables disagree with it — a feature added here and not on Android, or
a phrase reworded on one side only — until the other app catches up or the
difference is recorded in the file on purpose.

### Installing on an iPhone

Build the Release configuration for a connected, paired phone, then install and
launch it with `devicectl`:

```sh
xcodebuild -project DengueWatchBD.xcodeproj -scheme DengueWatchBD \
  -configuration Release -destination "id=<device UDID>" \
  -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device <device UDID> \
  build/Build/Products/Release-iphoneos/DengueWatchBD.app
xcrun devicectl device process launch --device <device UDID> bd.uzzal.denguewatch
```

`xcrun devicectl list devices` gives the UDID. Installing over an existing copy
keeps the reader's data.

Signing is automatic, with team `KC45FLCGH2`. A build signed with a free Apple ID
team carries a provisioning profile that expires after seven days, after which
the app will not open until it is rebuilt and reinstalled; a paid Apple
Developer Program membership gives profiles that last a year. Check a build's
expiry with:

```sh
security cms -D -i DengueWatchBD.app/embedded.mobileprovision | plutil -extract ExpirationDate raw -
```

A direct build like this keeps its debug symbols (the binary is about 13 MB);
an App Store archive strips them.

### Privacy manifest

`DengueWatchBD/PrivacyInfo.xcprivacy` declares no tracking and no collected
data, and one required-reason API: UserDefaults (`CA92.1`), for the app's own
settings. Feed refreshes are decided by the server's ETag and Last-Modified
headers and a sync date in UserDefaults, not by file timestamps, so the file
timestamp category is not declared. Any new required-reason API — file
timestamps, system boot time, disk space — needs adding here before
submission.

## Features

| Tab | What it does |
|---|---|
| **Home** | The national risk level and its trend, today's DGHS figures, what changed since the last report, the areas to watch, the epidemic curve with a scrubbable 7-day average, deaths, who is affected by age and sex, and season history back to 2018. |
| **Map** | Ten reporting areas as proportional symbols, by total cases or two-week rate per 100k, each with its 14-day risk band. Shows your live location and which area you are in. A searchable list view doubles as the offline and screen-reader path. An area can be shared as an image card. |
| **My health** | The symptom check, the fever timeline, the WHO care plan, the fluid log, vital signs and lab reports (typed in, photographed or uploaded, and read on the device), with trend charts and an A4 PDF of the whole log or a single day. |
| **Care** | Emergency numbers, live nearby-hospital search through Maps, and a directory of major government dengue hospitals with directions. |
| **Prevent** | A daily prevention checklist, five prevention topics, the dengue year, myths and facts, area risk alerts and the enter-a-high-risk-area warning. |

Every tab carries the language toggle.

## Bilingual

Full Bengali and English, switched in-app (not by device language) from the
button at the top of every tab. 652 string keys per language, checked for parity
by the tests. Bengali also gets:

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

### When the feed stops updating

If the DGHS dashboard changes shape, the scraper can stop producing new reports
without anything visibly failing. Two things catch that:

- **Readers** see a warning in the app once its figures are three days old, and
  a stronger one at seven.
- **The maintainer** hears a day earlier. `.github/workflows/feed-freshness.yml`
  runs daily at noon Dhaka time, reads `summary.json`, and fails when the latest
  report is two days or more behind today's Dhaka date, or the feed cannot be
  read. A failure opens one GitHub issue, "Dengue feed has stopped updating",
  comments on it each further day, and the first fresh run closes it. GitHub
  also emails the failure. It can be run by hand from the Actions tab.

A day missed for a public holiday will raise the issue too; it closes itself
when DGHS resumes.

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
all. `FeedSync` replaces it with a download as soon as one succeeds. The seed is
currently the DGHS report of 15 October 2026. Refresh it before a release by
copying the published
[`latest.json`](https://druzzal.github.io/dengue-bd-dashboard/data/latest.json)
over it, as long as its `schema_version` still matches.

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
DengueWatchBDTests/     decoding, mapping, geography, triage, care plan, health
                        log, PDF and localisation tests
DengueWatchBDUITests/   the My health flows, driven on the real app
.github/workflows/      the daily feed-freshness check
Tools/                  helper scripts
```

Inside `DengueWatchBD/`:

```
App/            entry point, tab shell, about + first-run disclaimer, UI-test
                launch state (DEBUG only)
Models/         FeedPayload (wire format), Domain (Area, Geography, RiskLevel),
                WHOCarePlan, vital signs, lab reports, fluid log
Localization/   AppLanguage, NumberStyle, the two string tables, place names
Data/           DengueStore, DengueFeedService, FeedSync, FeedConfig,
                background refresh, preferences, and the case log, vitals,
                lab and fluid stores
Design/         Theme.swift (validated palette), Typography.swift (type scale)
Features/
  Dashboard/    stat tiles, case trend, deaths, age/sex breakdown, history,
                shared chart axes
  Map/          proportional-symbol map, area list, area detail
  Triage/       symptom check, triage engine, health log
  Health/       My health, care plan card, fluid log, vitals and lab entry,
                lab scanner, PDF export
  Care/         emergency numbers, hospital directory, nearby search
  Prevention/   prevention topics, seasonal calendar
  Alerts/       notification scheduling, alert + geofence settings
  Location/     the single CoreLocation owner
  Share/        shareable area cards
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

## Your health record

My health keeps four on-device stores: symptom checks, vital-sign readings, lab
reports and the fluid log. Nothing in them leaves the phone unless the reader
exports a PDF and chooses where to send it. Lab reports that are photographed or
uploaded are read with Apple's Vision framework on the device, and the values
are shown as a draft for the reader to check before anything is saved.

The record shows and flags; it does not interpret. A reading outside the usual
range is marked as worth showing to a clinician, never explained, and no
combination of readings produces a diagnosis. The log groups everything by day,
and one day can be renamed, deleted or exported on its own. "Delete all" clears
all four stores.

A single symptom check can be deleted from the symptom check card in My health,
and any earlier one from its list of past checks. The care plan and fever
timeline then follow the check before it.

A check's advice is worked out from its saved answers each time it is shown,
by the current rules, so a check made before a rule changed says what the care
plan beside it says. The outcome shown at the time is still stored with it.

The PDF opens with an at-a-glance summary and trend charts, then the record day
by day. When fluids were logged it adds a fluid summary — days logged, average
drunk on a whole day, and the days urine reached WHO's aim — and two daily bar
charts, intake and urine. Today is left out of the averages and drawn paler,
because it is not over yet.

## Medical scope

The symptom check and care plan follow WHO's *Guidelines for clinical
management of arboviral diseases* (2025), which supersede the 2009 dengue
guidelines and their A / B / C groups. They help someone decide *when to seek
care*. They do not diagnose. Severe signs route straight to "go to hospital now"
with a 999 call button. Warning signs, being unable to drink, pregnancy, and
age or a long-term condition route to "see a doctor today". The NSAID warning
appears in every advice path that involves fever.

Vital signs can only raise the care plan's group. It reads the latest reading
of each measure from the last three days, not just the latest entry, so a
temperature logged on its own does not hide a low blood pressure taken an hour
before; the two blood-pressure numbers always come from the same reading. Under
five and over sixty are asked separately. A child under five is judged low at
a systolic under 70 rather than 90, and has no fast-pulse threshold, because a
normal pulse at that age runs well past 120 and the age group already means
being seen today. Pulse pressure (20 mmHg or less) and oxygen (under 94%) apply
at every age. Checks saved before the age question was split keep the adult
limits.

WHO's outpatient recommendation of measured oral fluids is the fluid log in My
health: drinks in millilitres and the number of times urine was passed, against
WHO's aim of four to six times a day. It sets no volume target, because WHO sets
that by age and condition. If no urine has been logged for six waking hours —
the symptom check's own warning sign — it says so; the night, 11 pm to 7 am,
does not count, so a night's sleep does not raise it every morning. A haematocrit that rises on two reports in a row is
pointed out for the doctor, but like every lab value it never changes the advice.
