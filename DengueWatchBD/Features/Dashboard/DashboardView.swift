import SwiftUI
import MapKit

/// The home screen, ordered by how urgently a reader needs each thing:
/// current risk, then local activity, then the trend, then where it is
/// spreading, then what to do about it.
struct DashboardView: View {
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
    private var focusArea: Area? {
        if let code = preferences.homeAreaCode, let area = store.area(code: code) {
            return area
        }
        if let here = location.lastKnownLocation {
            return store.nearestArea(to: here)
        }
        return nil
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
                onTap: {
                    Haptic.selection()
                    showingRiskDetail = true
                }
            )

            if focusArea == nil {
                // Without a area the reading is national, which is much
                // less useful than a local one. Offer the fix rather than
                // silently showing a country-wide number.
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

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            SectionHeader(loc.t("activity.title"), subtitle: loc.t("activity.subtitle")) {
                SourceBadge(kind: .official, detail: "DGHS")
            }

            LazyVGrid(columns: statColumns, spacing: Space.row) {
                StatCard(label: loc.t("dash.stat.cases"),
                         value: loc.num(store.seasonCases),
                         caption: store.national.first.map { loc.t("activity.since", loc.dayMonth($0.date)) },
                         accent: Palette.cases,
                         series: store.nationalRecent(30).map { Double($0.cases) })
                StatCard(label: loc.t("activity.thisWeek"),
                         value: loc.num(store.last7Cases),
                         change: store.weeklyCaseChange,
                         caption: loc.t("dash.stat.vsLastWeek"),
                         accent: Palette.cases,
                         series: store.nationalRecent(14).map { Double($0.cases) })
                // Replaces the old hospital-census card. This feed carries no
                // bed occupancy, and the 24-hour count is what DGHS leads its
                // daily release with anyway — the freshest figure on the screen.
                StatCard(label: loc.t("dash.stat.last24"),
                         value: loc.num(store.cases24h),
                         caption: loc.t("dash.stat.last24Deaths", loc.num(store.deaths24h)),
                         accent: Palette.admitted,
                         series: store.nationalRecent(14).map { Double($0.cases) })
                StatCard(label: loc.t("activity.hotspots"),
                         value: loc.num(store.hotspots.count),
                         caption: loc.t("activity.hotspotsCaption"),
                         accent: Palette.deaths)
            }
        }
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
    private var statColumns: [GridItem] {
        if typeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: Space.row)]
        }
        let count = sizeClass == .regular ? 4 : 2
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
