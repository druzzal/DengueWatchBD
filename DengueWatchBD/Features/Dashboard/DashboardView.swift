import SwiftUI
import MapKit

/// The home screen, ordered by how urgently a reader needs each thing:
/// current risk, then local activity, then the trend, then where it is
/// spreading, then what to do about it.
struct DashboardView: View {
    @Environment(CaseLogStore.self) private var caseLog
    @Environment(DengueStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(LocalizationManager.self) private var loc
    @Environment(FeedSync.self) private var sync
    @Environment(LocationManager.self) private var location
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var trendRange: TrendRange = .fortnight
    @State private var showingAbout = false
    @State private var showingRiskDetail = false

    /// The area the user is being told about: their chosen area, else the
    /// area they are standing in, else the country.
    /// The area the hero reads for: where the reader is now when the phone can
    /// say so, and their chosen area otherwise.
    ///
    /// Location comes first deliberately. "The risk here" is the question this
    /// card answers, and someone who has travelled to a district with an
    /// outbreak needs that district's reading, not the one they picked at home
    /// last month. The card always names the area it is reading, so there is
    /// no guessing which one is on screen.
    private var focusArea: Area? {
        if let here = location.lastKnownLocation, let area = store.nearestArea(to: here) {
            return area
        }
        if let code = preferences.homeAreaCode, let area = store.area(code: code) {
            return area
        }
        return nil
    }

    /// True when the area on screen came from the phone's own position.
    private var focusIsCurrentLocation: Bool {
        guard let here = location.lastKnownLocation else { return false }
        return store.nearestArea(to: here) != nil
    }

    private var focusRisk: RiskLevel { focusArea?.risk ?? store.nationalRisk }

    private var focusAreaName: String {
        if let focusArea {
            return focusArea.displayName(loc.language)
        }
        return loc.t("area.nationwide")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.section) {
                    if sizeClass == .regular {
                        ScreenTitle(text: loc.t("dash.title"))
                    }
                    switch store.state {
                    case .idle, .loading:
                        loadingContent
                    case .failed where !store.areas.isEmpty:
                        // Keep showing what we have. On a surveillance app a
                        // refresh failure is no reason to blank the screen —
                        // yesterday's figures still answer the question.
                        AlertCard(risk: .moderate,
                                  title: loc.t("dash.error.title"),
                                  message: loc.t("dash.stale.message"),
                                  actionTitle: loc.t("common.tryAgain"),
                                  action: { Task { await store.reload() } })
                        loadedContent
                    case .failed:
                        ErrorStateView(
                            title: loc.t("dash.error.title"),
                            message: loc.t("dash.error.message"),
                            retry: { Task { await store.reload() } }
                        )
                        .padding(.top, Space.section)
                    case .loaded:
                        loadedContent
                    }
                }
                .padding(.horizontal, Space.screen)
                .padding(.bottom, Space.card)
                .readableColumn()
                .padding(.bottom, Space.section)
            }
            .background(Palette.plane)
            .columnAlignedTitle(loc.t("dash.title"), isWide: sizeClass == .regular)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { LanguageToggle() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAbout = true } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel(loc.t("dash.about.a11y"))
                }
            }
            .refreshable {
                await sync.sync(force: true)
                await store.refresh()
            }
            .task {
                // Ask for a fix. If permission has not been given yet this
                // records the want rather than prompting — the card below does
                // the asking, with an explanation — and the fix is delivered
                // the moment access is granted, without the reader having to
                // leave the tab and come back.
                location.requestOneFix()
            }
            .navigationDestination(for: Area.self) { AreaDetailView(area: $0) }
            .sheet(isPresented: $showingAbout) { AboutDataView() }
            .sheet(isPresented: $showingRiskDetail) {
                RiskDetailSheet(
                    risk: focusRisk,
                    areaName: focusAreaName,
                    incidence: focusArea?.incidencePer100k ?? nationalIncidence,
                    last14Cases: focusArea?.recentCases ?? store.nationalRecentCases,
                    lastUpdated: store.lastUpdated
                )
            }
        }
    }

    // MARK: - Loading

    /// The age of the data, plus — when the last check actually failed — the
    /// fact that it did. "Days old" alone would imply DGHS simply published
    /// nothing, which is a different situation from the app being unable to ask.
    private func staleMessage(days: Int) -> String {
        let age = loc.t(store.freshness == .outdated ? "outdated.message" : "stale.message",
                        loc.num(days))
        if case .failed = sync.status {
            return age + " " + loc.t("stale.checkFailed")
        }
        return age
    }

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            RiskCardSkeleton()
            VStack(alignment: .leading, spacing: Space.row) {
                SkeletonBlock(width: 140, height: 15)
                StatGridSkeleton()
            }
            ChartSkeleton()
        }
        .padding(.top, Space.tight)
    }

    // MARK: - Loaded

    @ViewBuilder
    private var loadedContent: some View {
        riskSection
        activitySection
        whatChangedSection
        myHealthSection
        topAreasSection
        trendSection
        mapSection
        provenanceSection
    }

    private var riskSection: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            DengueRiskCard(
                risk: focusRisk,
                areaName: focusAreaName,
                change: focusArea?.weeklyChange ?? store.weeklyCaseChange,
                lastUpdated: store.lastUpdated,
                incidence: focusArea?.incidencePer100k ?? nationalIncidence,
                isNationwide: focusArea == nil,
                isCurrentLocation: focusIsCurrentLocation,
                onTap: {
                    Haptic.selection()
                    showingRiskDetail = true
                }
            )

            if focusArea == nil, location.authorization != .authorizedWhenInUse,
               location.authorization != .authorizedAlways {
                // The reading is national, which is much less useful than a
                // local one. Explain what location is for before iOS asks, and
                // always leave the manual route open.
                LocationPermissionCard(onChooseManually: { router.show(.map) })
            } else if focusArea == nil {
                // Allowed, but no fix yet or the reader is outside Bangladesh.
                // The picker is the only route left.
                Button {
                    router.show(.map)
                } label: {
                    HStack(spacing: Space.tight) {
                        Image(systemName: "location.magnifyingglass")
                        Text(loc.t("area.chooseHint")).typo(.caption)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Palette.accent)
                    .padding(Space.row)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.accent.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if store.isStale, let days = store.dataAgeInDays {
            // Outdated reads louder than stale, and a failed source check is
            // named rather than left implicit — the app should never let a
            // reader assume it simply has nothing new to say when in fact it
            // could not reach the source at all.
            AlertCard(risk: store.freshness == .outdated ? .high : .moderate,
                      title: loc.t(store.freshness == .outdated
                                   ? "outdated.title" : "stale.title"),
                      message: staleMessage(days: days),
                      actionTitle: loc.t("common.tryAgain"),
                      action: {
                          Task {
                              await sync.sync(force: true)
                              await store.refresh()
                          }
                      })
        }

        // Only one advisory at a time, and staleness wins: a "cases are rising"
        // claim derived from figures the app has just called out as days old
        // would be asserting a trend it cannot stand behind.
        if !store.isStale, let alert = activeAlert {
                AlertCard(risk: alert.risk,
                          title: alert.title,
                          message: alert.message,
                          actionTitle: loc.t("alert.viewMap"),
                          action: { router.show(.map) })
            }
        }
    }

    /// Statements about what moved since the last report.
    ///
    /// The section disappears entirely when the digest has nothing it can
    /// support — an empty card saying "no changes" would be a claim of its own.
    @ViewBuilder
    private var whatChangedSection: some View {
        let items = SurveillanceDigest.items(
            nationalChange: store.weeklyCaseChange,
            hotspotCount: store.hotspots.count,
            hasAreaBreakdown: !store.areas.isEmpty,
            risingAreas: store.areasByRisk.compactMap { area in
                guard let change = area.weeklyChange, change > 0 else { return nil }
                return (name: area.displayName(loc.language), change: change)
            }
            .sorted { $0.change > $1.change }
        )

        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Space.row) {
                SectionHeader(loc.t("digest.title"), subtitle: loc.t("digest.subtitle"))
                Card {
                    VStack(alignment: .leading, spacing: Space.tight) {
                        ForEach(items) { item in
                            HStack(alignment: .firstTextBaseline, spacing: Space.tight) {
                                Image(systemName: symbol(for: item.kind))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(tint(for: item.kind))
                                    .frame(width: 18)
                                    .accessibilityHidden(true)
                                Text(loc.t(item.key, arguments: item.arguments))
                                    .typo(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        SecondaryActionButton(title: loc.t("digest.action"),
                                              systemImage: "map") { router.show(.map) }
                            .padding(.top, Space.hair)
                    }
                }
            }
        }
    }

    /// Icon and colour carry the same meaning as the words, so the section still
    /// reads without colour vision and without reading every sentence.
    private func symbol(for kind: SurveillanceDigest.Kind) -> String {
        switch kind {
        case .nationalRise, .steepestRises: "arrow.up.right"
        case .nationalFall: "arrow.down.right"
        case .nationalSteady: "equal"
        case .hotspots: "exclamationmark.triangle.fill"
        case .noBreakdown: "questionmark.circle"
        }
    }

    private func tint(for kind: SurveillanceDigest.Kind) -> Color {
        switch kind {
        case .nationalRise, .steepestRises: Palette.riskTint(.high)
        case .nationalFall: Palette.riskTint(.low)
        case .hotspots: Palette.riskTint(.severe)
        case .nationalSteady, .noBreakdown: Color.secondary
        }
    }

    /// The areas carrying the most dengue per head, ranked.
    ///
    /// Ordered by `areasByRisk`, which sorts on the 14-day rate rather than raw
    /// case counts. Ranking by counts would put the biggest cities on top every
    /// week regardless of how bad things actually are there — which is the
    /// question this list exists to answer.
    @ViewBuilder
    private var topAreasSection: some View {
        let ranked = Array(store.areasByRisk.prefix(5))
        if !ranked.isEmpty {
            VStack(alignment: .leading, spacing: Space.row) {
                SectionHeader(loc.t("top.title"), subtitle: loc.t("top.subtitle"))
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(ranked.enumerated()), id: \.element.id) { index, area in
                            NavigationLink(value: area) {
                                topAreaRow(rank: index + 1, area: area)
                            }
                            .buttonStyle(.plain)
                            if area.id != ranked.last?.id {
                                Divider().padding(.leading, 44)
                            }
                        }
                        SecondaryActionButton(title: loc.t("top.viewMap"),
                                              systemImage: "map") { router.show(.map) }
                            .padding(.top, Space.tight)
                    }
                }
            }
        }
    }

    private func topAreaRow(rank: Int, area: Area) -> some View {
        HStack(spacing: Space.row) {
            Text(loc.num(rank))
                .typo(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            // Two full-width lines rather than one row of five competing
            // items. The badge shares the name's line because their widths
            // vary together — a long name is not also a long badge — and the
            // rate then has the whole row, so nothing is ever cut short.
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Space.tight) {
                    Text(area.displayName(loc.language))
                        .typo(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: Space.tight)
                    RiskBadge(risk: area.risk, compact: true)
                }
                HStack(spacing: Space.tight) {
                    Text(loc.t("top.rate", loc.decimal(area.incidencePer100k)))
                        .typo(.micro)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    TrendIndicator(change: area.weeklyChange)
                    Spacer(minLength: 0)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: Hit.minimum)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The reader's own last check, if they have done one.
    ///
    /// Shows the recommendation and when it was made, and nothing else. The
    /// symptoms themselves stay in the case log behind the Check tab: Home is
    /// the screen most likely to be glanced at by someone else in the room,
    /// and a list of someone's symptoms is not a thing to put there by default.
    @ViewBuilder
    private var myHealthSection: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            SectionHeader(loc.t("health.title"))
            Card {
                if let latest = caseLog.entries.first {
                    VStack(alignment: .leading, spacing: Space.row) {
                        HStack(alignment: .top, spacing: Space.row) {
                            Image(systemName: latest.outcome.symbolName)
                                .font(.title3)
                                .foregroundStyle(Palette.riskTint(outcomeRisk(latest.outcome)))
                                .frame(width: 26)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(loc.t(latest.outcome.headlineKey))
                                    .typo(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(loc.t("health.checkedAt", loc.relative(latest.date)))
                                    .typo(.micro)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        SecondaryActionButton(title: loc.t("health.checkAgain"),
                                              systemImage: "stethoscope") { router.show(.health) }
                    }
                } else {
                    VStack(alignment: .leading, spacing: Space.row) {
                        Text(loc.t("health.empty"))
                            .typo(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        SecondaryActionButton(title: loc.t("health.check"),
                                              systemImage: "stethoscope") { router.show(.health) }
                    }
                }
            }
        }
    }

    /// Maps a triage outcome onto the risk palette, so the colour here means
    /// the same thing it means everywhere else in the app.
    private func outcomeRisk(_ outcome: TriageOutcome) -> RiskLevel {
        switch outcome {
        case .selfCare: .low
        case .testAdvised: .moderate
        case .seeDoctorToday: .high
        case .emergency: .severe
        }
    }

    /// The brief's "Today in Bangladesh": the national snapshot, led by the
    /// freshest figure DGHS publishes rather than by the season total.
    ///
    /// Every tile here can be absent. A tile with nothing behind it is left
    /// out rather than shown as zero — see `NationalSnapshot` for why that
    /// distinction is not pedantry.
    private var activitySection: some View {
        let snapshot = store.snapshot
        return VStack(alignment: .leading, spacing: Space.row) {
            SectionHeader(activityTitle, subtitle: activitySubtitle) {
                SourceBadge(kind: .official, detail: "DGHS")
            }

            LazyVGrid(columns: statColumns(for: snapshot.tileCount), spacing: Space.row) {
                if let cases24 = snapshot.last24Cases {
                    StatCard(label: loc.t("dash.stat.last24"),
                             value: loc.num(cases24),
                             // Omitted rather than "0 deaths" when the figure
                             // never arrived: that reads as good news.
                             caption: snapshot.last24Deaths.map {
                                 loc.t("dash.stat.last24Deaths", loc.num($0))
                             },
                             accent: Palette.admitted,
                             series: store.nationalRecent(14).map { Double($0.cases) })
                }
                if let week = snapshot.weekCases {
                    StatCard(label: loc.t("activity.thisWeek"),
                             value: loc.num(week),
                             change: snapshot.weeklyChange,
                             caption: snapshot.weeklyChange == nil ? nil : loc.t("dash.stat.vsLastWeek"),
                             accent: Palette.cases,
                             series: store.nationalRecent(14).map { Double($0.cases) })
                }
                if let season = snapshot.seasonCases {
                    StatCard(label: loc.t("dash.stat.cases"),
                             value: loc.num(season),
                             caption: snapshot.seasonStart.map { loc.t("activity.since", loc.dayMonth($0)) },
                             accent: Palette.cases,
                             series: store.nationalRecent(30).map { Double($0.cases) })
                }
                if let deaths = snapshot.seasonDeaths {
                    // Beside the season case count, which is the figure it
                    // belongs next to.
                    StatCard(label: loc.t("dash.stat.seasonDeaths"),
                             value: loc.num(deaths),
                             caption: snapshot.seasonStart.map { loc.t("activity.since", loc.dayMonth($0)) },
                             accent: Palette.deaths,
                             // The seven-day average, as DeathsCard plots it.
                             // Raw daily deaths are single digits and would be
                             // noise at this size, not a trend.
                             series: Array(Series.movingAverage(store.national.map(\.deaths),
                                                                window: 7).suffix(30)))
                }
                if let hotspots = snapshot.highRiskAreas {
                    StatCard(label: loc.t("activity.hotspots"),
                             value: loc.num(hotspots),
                             // The feed's reporting areas, not the country's 64
                             // districts. The app has no district breakdown, so
                             // it cannot use a district denominator.
                             caption: loc.t("activity.hotspotsCaption", loc.num(snapshot.reportingAreas)),
                             accent: Palette.deaths)
                }
            }
        }
    }

    /// "Today" only when the figures are actually from today. Ten-day-old
    /// numbers under a "Today" heading would be the app misreporting DGHS.
    private var activityTitle: String {
        store.isStale ? loc.t("activity.title.stale") : loc.t("activity.title")
    }

    private var activitySubtitle: String? {
        store.lastUpdated.map { loc.t("activity.reported", loc.reportedDate($0)) }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            SectionHeader(loc.t("trend.section"))
            TrendCard(points: store.national, range: $trendRange)
            DeathsCard(points: store.national)
            if !store.ageBandsCases.isEmpty {
                WhoIsAffectedCard(bands: store.ageBandsCases, split: store.sexSplitCases)
            }
            if !store.history.isEmpty {
                SeasonComparisonCard(history: store.history,
                                     currentYear: store.meta?.year ?? store.history.last?.year ?? 0)
            }
        }
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            SectionHeader(loc.t("map.section")) {
                Button(loc.t("common.viewAll")) { router.show(.map) }
                    .typo(.caption)
                    .foregroundStyle(Palette.accent)
            }
            MapPreviewCard(areas: store.areasByRisk) { router.show(.map) }
        }
    }

    private var provenanceSection: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            HStack {
                SyncStatusRow()
                Spacer(minLength: 0)
            }
        }
    }

    /// One column once text is large enough that two would crush the figures;
    /// four across on a regular-width screen, where two leaves each card mostly
    /// empty.
    private func statColumns(for tiles: Int) -> [GridItem] {
        if typeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: Space.row)]
        }
        let count = StatGrid.columns(forTiles: tiles, wide: sizeClass == .regular)
        return Array(repeating: GridItem(.flexible(), spacing: Space.row), count: count)
    }

    // MARK: - Derived

    private var nationalIncidence: Double { store.nationalIncidencePer100k }

    /// One advisory at most, and only when it says something the hero card has
    /// not already said.
    ///
    /// A "high risk area" banner directly beneath a hero card already reading
    /// SEVERE for that same area is duplication, and stacking two tinted
    /// red cards is precisely the alarm fatigue this screen should avoid. So
    /// the banner is reserved for the national trend, which the hero card —
    /// scoped to one area — does not cover.
    private var activeAlert: (risk: RiskLevel, title: String, message: String)? {
        guard let change = store.weeklyCaseChange, change >= 0.15 else { return nil }
        return (.moderate,
                loc.t("alert.rising.title"),
                loc.t("alert.rising.message", loc.percentChange(change)))
    }
}

/// A still map with the worst areas marked, standing in for the full map.
struct MapPreviewCard: View {
    @Environment(LocalizationManager.self) private var loc
    let areas: [Area]
    let onTap: () -> Void

    private var marked: [Area] { Array(areas.prefix(12)) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                Map(initialPosition: .region(.bangladesh), interactionModes: []) {
                    ForEach(marked) { area in
                        Annotation("", coordinate: CLLocationCoordinate2D(
                            latitude: area.latitude, longitude: area.longitude)) {
                            Circle()
                                .fill(area.risk.tint.opacity(0.85))
                                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                                .frame(width: 14, height: 14)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: 190)
                .allowsHitTesting(false)

                HStack(spacing: Space.tight) {
                    RiskScaleLegend()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(Space.row)
            }
            .cardSurface()
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .pressable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loc.t("map.preview.a11y"))
        .accessibilityAddTraits(.isButton)
    }
}

/// One line telling the user how fresh the data is and why.
struct SyncStatusRow: View {
    @Environment(LocalizationManager.self) private var loc
    @Environment(FeedSync.self) private var sync

    private var text: String {
        switch sync.status {
        case .syncing: loc.t("sync.updating")
        case .updated: loc.t("sync.justUpdated")
        case .upToDate(let date): loc.t("sync.lastChecked", loc.relative(date))
        case .offline: loc.t("sync.offline")
        case .failed: loc.t("sync.failed")
        case .bundledOnly, .idle: loc.t("sync.bundled")
        }
    }

    private var symbol: String {
        switch sync.status {
        case .syncing: "arrow.triangle.2.circlepath"
        case .updated, .upToDate: "checkmark.circle"
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.triangle"
        case .bundledOnly, .idle: "shippingbox"
        }
    }

    var body: some View {
        HStack(spacing: Space.hair + 2) {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium))
            Text(text).typo(.micro).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// The language switch, shown on the home screen as the brief requires.
struct LanguageToggle: View {
    @Environment(LocalizationManager.self) private var loc

    var body: some View {
        Button {
            withAnimation(Motion.interactive) { loc.toggle() }
            Haptic.selection()
        } label: {
            Text(loc.language.shortLabel)
                .typo(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(loc.t("lang.toggle.a11y"))
    }
}
