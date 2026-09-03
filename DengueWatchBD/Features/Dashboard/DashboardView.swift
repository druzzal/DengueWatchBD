import SwiftUI
import MapKit

/// The home screen, ordered by how urgently a reader needs each thing:
/// current risk, then local activity, then the trend, then where it is
/// spreading, then what to do about it.
struct DashboardView: View {
    @Environment(SurveillanceStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(LocalizationManager.self) private var loc
    @Environment(SurveillanceSync.self) private var sync
    @Environment(LocationManager.self) private var location
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var trendRange: TrendRange = .fortnight
    @State private var showingAbout = false
    @State private var showingRiskDetail = false

    /// The area the user is being told about: their chosen district, else the
    /// district they are standing in, else the country.
    private var focusDistrict: District? {
        if let code = preferences.homeDistrictCode, let district = store.district(code: code) {
            return district
        }
        if let here = location.lastKnownLocation {
            return store.nearestDistrict(to: here)
        }
        return nil
    }

    private var focusRisk: RiskLevel { focusDistrict?.risk ?? store.nationalRisk }

    private var focusAreaName: String {
        if let focusDistrict {
            return focusDistrict.displayName(loc.language)
        }
        return loc.t("area.nationwide")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.section) {
                    switch store.state {
                    case .idle, .loading:
                        loadingContent
                    case .failed where !store.districts.isEmpty:
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
            .navigationTitle(loc.t("dash.title"))
            .navigationBarTitleDisplayMode(.large)
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
                await store.reload()
            }
            .navigationDestination(for: District.self) { DistrictDetailView(district: $0) }
            .sheet(isPresented: $showingAbout) { AboutDataView() }
            .sheet(isPresented: $showingRiskDetail) {
                RiskDetailSheet(
                    risk: focusRisk,
                    areaName: focusAreaName,
                    incidence: focusDistrict?.incidencePer100k ?? nationalIncidence,
                    last14Cases: focusDistrict?.last14Cases ?? nationalLast14,
                    lastUpdated: store.lastUpdated
                )
            }
        }
    }

    // MARK: - Loading

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
                change: focusDistrict?.weeklyChange ?? store.weeklyCaseChange,
                lastUpdated: store.lastUpdated,
                incidence: focusDistrict?.incidencePer100k ?? nationalIncidence,
                isNationwide: focusDistrict == nil,
                onTap: {
                    Haptic.selection()
                    showingRiskDetail = true
                }
            )

            if focusDistrict == nil {
                // Without a district the reading is national, which is much
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
            AlertCard(risk: .moderate,
                      title: loc.t("stale.title"),
                      message: loc.t("stale.message", loc.num(days)),
                      actionTitle: loc.t("common.tryAgain"),
                      action: {
                          Task {
                              await sync.sync(force: true)
                              await store.reload()
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
                         value: loc.compact(store.seasonCases),
                         caption: store.dates.first.map { loc.t("activity.since", loc.dayMonth($0)) },
                         accent: Palette.cases,
                         series: store.nationalRecent(30).map { Double($0.cases) })
                StatCard(label: loc.t("activity.thisWeek"),
                         value: loc.num(store.last7Cases),
                         change: store.weeklyCaseChange,
                         caption: loc.t("dash.stat.vsLastWeek"),
                         accent: Palette.cases,
                         series: store.nationalRecent(14).map { Double($0.cases) })
                StatCard(label: loc.t("dash.stat.admitted"),
                         value: loc.compact(store.currentlyAdmitted),
                         change: store.admittedChange,
                         caption: loc.t("dash.stat.vs7days"),
                         accent: Palette.admitted,
                         series: store.nationalRecent(30).map { Double($0.admitted) })
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
        }
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            SectionHeader(loc.t("map.section")) {
                Button(loc.t("common.viewAll")) { router.show(.map) }
                    .typo(.caption)
                    .foregroundStyle(Palette.accent)
            }
            MapPreviewCard(districts: store.districtsByRisk) { router.show(.map) }
        }
    }

    private var provenanceSection: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            HStack {
                SyncStatusRow()
                Spacer(minLength: 0)
            }
            if let meta = store.meta, meta.isSampleData {
                InlineNote(symbol: "flask.fill", detail: meta.disclaimer)
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

    private var nationalIncidence: Double {
        let population = store.districts.reduce(0) { $0 + $1.populationThousands }
        guard population > 0 else { return 0 }
        return Double(nationalLast14) / Double(population) * 100
    }

    private var nationalLast14: Int {
        store.districts.reduce(0) { $0 + $1.last14Cases }
    }

    /// One advisory at most, and only when it says something the hero card has
    /// not already said.
    ///
    /// A "high risk area" banner directly beneath a hero card already reading
    /// SEVERE for that same district is duplication, and stacking two tinted
    /// red cards is precisely the alarm fatigue this screen should avoid. So
    /// the banner is reserved for the national trend, which the hero card —
    /// scoped to one district — does not cover.
    private var activeAlert: (risk: RiskLevel, title: String, message: String)? {
        guard let change = store.weeklyCaseChange, change >= 0.15 else { return nil }
        return (.moderate,
                loc.t("alert.rising.title"),
                loc.t("alert.rising.message", loc.percentChange(change)))
    }
}

/// A still map with the worst districts marked, standing in for the full map.
struct MapPreviewCard: View {
    @Environment(LocalizationManager.self) private var loc
    let districts: [District]
    let onTap: () -> Void

    private var marked: [District] { Array(districts.prefix(12)) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                Map(initialPosition: .region(.bangladesh), interactionModes: []) {
                    ForEach(marked) { district in
                        Annotation("", coordinate: CLLocationCoordinate2D(
                            latitude: district.latitude, longitude: district.longitude)) {
                            Circle()
                                .fill(district.risk.tint.opacity(0.85))
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
    @Environment(SurveillanceSync.self) private var sync

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
