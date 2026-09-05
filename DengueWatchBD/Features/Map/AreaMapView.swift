import SwiftUI
import MapKit

enum MapMetric: String, CaseIterable, Identifiable {
    case total, rate
    var id: String { rawValue }
    var labelKey: String { "map.metric.\(rawValue)" }
    var explanationKey: String { "map.explain.\(rawValue)" }

    func value(for area: Area) -> Double {
        switch self {
        case .total: Double(area.seasonCases)
        case .rate: area.incidencePer100k
        }
    }
}

struct AreaMapView: View {
    @Environment(DengueStore.self) private var store
    @Environment(LocalizationManager.self) private var loc
    @Environment(LocationManager.self) private var location
    @Environment(Preferences.self) private var preferences
    @State private var metric: MapMetric = .total
    @State private var showsList = false
    @State private var searchText = ""
    @State private var showingLocationExplainer = false
    @State private var camera: MapCameraPosition = .region(.bangladesh)
    @State private var selectedArea: Area?
    @State private var pushedArea: Area?
    /// Auto-zoom happens once per visit to the tab, never again.
    ///
    /// `MapUserLocationButton` is still not used: it puts the camera into
    /// follow mode, so the map keeps dragging itself back and a reader can no
    /// longer pan away to look at another division. Moving once and then
    /// leaving the camera alone gives the same first impression without taking
    /// the map away from them.
    @State private var hasAutoZoomed = false

    private var maxValue: Double {
        max(store.areas.map { metric.value(for: $0) }.max() ?? 1, 1)
    }

    private var filtered: [Area] {
        guard !searchText.isEmpty else { return store.areasByCases }
        return store.areasByCases.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.displayName(loc.language).localizedCaseInsensitiveContains(searchText)
                || $0.division.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch store.state {
                case .idle, .loading:
                    mapLoadingState
                case .failed:
                    ErrorStateView(title: loc.t("dash.error.title"),
                                   message: loc.t("dash.error.message"),
                                   retry: { Task { await store.reload() } })
                case .loaded where store.areas.isEmpty:
                    EmptyStateView(symbol: "map",
                                   title: loc.t("map.state.emptyTitle"),
                                   message: loc.t("map.state.emptyMessage"))
                case .loaded:
                    if showsList { areaList } else { officialMap }
                }
            }
            .background(Palette.plane)
            .navigationTitle(loc.t("map.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { LanguageToggle() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { withAnimation { showsList.toggle() } } label: {
                        Image(systemName: showsList ? "map" : "list.bullet")
                    }
                    .accessibilityLabel(loc.t(showsList ? "map.showMap" : "map.showList"))
                }
            }
            .navigationDestination(for: Area.self) { AreaDetailView(area: $0) }
            .sheet(isPresented: $showingLocationExplainer) {
                LocationPermissionSheet {
                    location.requestWhenInUse()
                    location.startUpdatingCoarse()
                }
            }
            .sheet(item: $selectedArea) { area in
                AreaRiskSheet(area: area, lastUpdated: store.lastUpdated) { chosen in
                    pushedArea = chosen
                }
                .environment(loc)
                .environment(preferences)
            }
            .navigationDestination(item: $pushedArea) { AreaDetailView(area: $0) }
        }
    }

    private var mapLoadingState: some View {
        VStack(spacing: Space.stack) {
            ChartSkeleton(height: 260)
            RowsSkeleton(count: 3)
        }
        .padding(.horizontal, Space.screen)
        .padding(.top, Space.card)
        .accessibilityLabel(loc.t("map.state.loading"))
    }

    // MARK: - Official surveillance map

    private var officialMap: some View {
        VStack(spacing: 0) {
            Picker("", selection: $metric) {
                ForEach(MapMetric.allCases) { option in
                    Text(loc.t(option.labelKey)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .readableColumn()
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                ForEach(store.areas) { area in
                    Annotation(area.displayName(loc.language),
                               coordinate: CLLocationCoordinate2D(latitude: area.latitude,
                                                                  longitude: area.longitude),
                               anchor: .center) {
                        Button {
                            Haptic.selection()
                            selectedArea = area
                        } label: {
                            bubble(for: area)
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }

                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass() }
            .onAppear {
                // Only starts if permission is already granted; otherwise the
                // legend offers the button that asks for it.
                location.startUpdatingCoarse()
                autoZoomIfReady()
            }
            .onChange(of: location.lastKnownLocation) { _, _ in
                autoZoomIfReady()
            }
            .onChange(of: showsList) { _, isList in
                // Coming back from the list re-frames the country, so the next
                // fix is allowed to move the camera again.
                if !isList {
                    camera = .region(.bangladesh)
                    hasAutoZoomed = false
                    autoZoomIfReady()
                }
            }
            .onDisappear {
                location.stopUpdatingCoarse()
                hasAutoZoomed = false
            }
            .onChange(of: location.authorization) { _, _ in
                location.startUpdatingCoarse()
            }
            // An inset rather than an overlay: MapKit then frames the country in
            // the space the legend leaves, and keeps its attribution clear of it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    legend
                    // Under the map, not over it, so it never covers a area.
                    MapAsOfFooter()
                }
                .readableColumn()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    /// Area-proportional, so a circle twice as wide means four times the value.
    private func radius(for area: Area) -> CGFloat {
        5 + 22 * sqrt(max(metric.value(for: area) / maxValue, 0))
    }

    private func bubble(for area: Area) -> some View {
        let size = radius(for: area) * 2
        // The mark stays proportional to the data, but the tap area never
        // drops below Apple's 44pt minimum — a low-case area was a 10pt
        // target before, effectively unreachable.
        return Circle()
            .fill(area.risk.tint.opacity(0.75))
            .overlay(Circle().strokeBorder(Palette.card, lineWidth: 2))
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .frame(width: size, height: size)
            .frame(width: max(size, Hit.minimum), height: max(size, Hit.minimum))
            .contentShape(Circle())
            .accessibilityLabel(loc.t("map.bubble.a11y", area.displayName(loc.language),
                                      loc.num(area.seasonCases),
                                      loc.t(area.risk.labelKey)))
    }

    /// Which area the user is standing in, if a fix has come through.
    private var currentArea: Area? {
        location.lastKnownLocation.flatMap { store.nearestArea(to: $0) }
    }

    /// Frame the user on first fix, then leave the camera to them.
    ///
    /// Gated on being able to name an area, which means being inside
    /// Bangladesh. Without that, someone opening the app abroad would have a
    /// national dengue map thrown to street level over a city it has no data
    /// for — the country view is the more useful thing to show them.
    private func autoZoomIfReady() {
        guard !hasAutoZoomed, !showsList, currentArea != nil else { return }
        hasAutoZoomed = true
        zoomToUser()
    }

    /// Zoom to roughly a city around the user.
    private func zoomToUser() {
        guard let here = location.lastKnownLocation else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            camera = .region(MKCoordinateRegion(center: here.coordinate,
                                                latitudinalMeters: 30_000,
                                                longitudinalMeters: 30_000))
        }
    }

    @ViewBuilder
    private var youAreHereRow: some View {
        if let currentArea {
            HStack(spacing: 8) {
                Button(action: zoomToUser) {
                    HStack(spacing: 7) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(loc.t("map.you.inArea", currentArea.displayName(loc.language)))
                            .typo(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(Palette.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                Button {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        camera = .region(.bangladesh)
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(Palette.mutedInk.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(loc.t("map.you.wholeCountry"))

                RiskBadge(risk: currentArea.risk, compact: true)
            }
            Divider().overlay(Palette.hairline)
        } else if location.lastKnownLocation != nil {
            HStack(spacing: 7) {
                Image(systemName: "location.slash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(loc.t("map.you.outside"))
                    .typo(.micro)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        } else if location.isAuthorized {
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                Text(loc.t("map.you.locating"))
                    .typo(.micro)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        } else if location.authorization == .denied || location.authorization == .restricted {
            Text(loc.t("map.you.denied"))
                .typo(.micro)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button {
                showingLocationExplainer = true
            } label: {
                Label(loc.t("map.you.enable"), systemImage: "location")
                    .typo(.caption)
                    .fontWeight(.medium)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.accent)
        }
    }

    /// The entry-alert control, on the map itself.
    ///
    /// Previously shown only while the reader was standing in a high-risk area,
    /// which is backwards: the alert exists to warn you *before* you enter one,
    /// so the one person who could never turn it on from here was the person it
    /// was for. It now appears whenever there is a high-risk area to watch.
    @ViewBuilder
    private var geofencePrompt: some View {
        if !store.hotspots.isEmpty {
            if !preferences.geofenceAlertsEnabled {
                promptButton(title: loc.t("geo.prompt.title"),
                             action: loc.t("geo.prompt.enable"),
                             symbol: "bell.badge") { enableHighRiskAlerts() }
            } else if !location.hasBackgroundAuthorization {
                // Turned on, but iOS only granted "While Using", so nothing is
                // actually being watched. Saying "alerts on" here would be a lie.
                promptButton(title: loc.t("geo.prompt.title"),
                             action: loc.t("geo.permission"),
                             symbol: "exclamationmark.triangle") { location.requestAlways() }
            } else {
                HStack(spacing: Space.hair + 2) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(loc.t("geo.monitoring", loc.num(location.monitoredAreaCodes.count)))
                        .typo(.micro)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
            Divider().overlay(Palette.hairline)
        }
    }

    private func promptButton(title: String, action: String, symbol: String,
                              perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(alignment: .top, spacing: Space.tight) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .typo(.micro).fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(action)
                        .typo(.micro).fontWeight(.semibold)
                        .foregroundStyle(Palette.accent)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: Hit.minimum - 12)
    }


    private func enableHighRiskAlerts() {
        preferences.geofenceAlertsEnabled = true
        Haptic.success()
        Task {
            await NotificationManager.shared.requestAuthorization()
            location.requestAlways()
            if let hotspots = store.hotspotsToMonitor {
                location.monitorHighRiskAreas(hotspots)
            }
        }
    }

    private var legend: some View {
        MapLegend(
            metricExplanation: loc.t(metric.explanationKey),
            sizeSamples: [0.08, 0.35, 1.0].map { fraction in
                (label: metric == .total
                    ? loc.compact(Int(maxValue * fraction))
                    : loc.decimal(maxValue * fraction, places: 0),
                 diameter: (5 + 22 * sqrt(fraction)) * 1.2)
            }
        ) {
            youAreHereRow
            geofencePrompt
        }
    }

    // MARK: - List (also the accessible and offline path)

    private var areaList: some View {
        List {
            Section(loc.t("map.list.divisions")) {
                ForEach(store.divisionSummaries) { summary in
                    HStack(spacing: 10) {
                        Text(summary.division.displayName(loc.language)).typo(.subheadline)
                        Spacer(minLength: 6)
                        Text(loc.compact(summary.cases)).typo(.subheadline).monospacedDigit()
                        RiskBadge(risk: summary.risk, compact: true)
                    }
                }
            }

            Section {
                ForEach(filtered) { area in
                    NavigationLink(value: area) {
                        AreaRow(area: area, peak: store.peakAreaCases)
                    }
                }
            } header: {
                Text(loc.t("map.list.areas"))
            } footer: {
                Text(loc.t("map.list.footer"))
            }
        }
        .listStyle(.insetGrouped)
        .readableColumn()
        .searchable(text: $searchText, prompt: loc.t("map.search"))
    }
}

struct AreaRow: View {
    @Environment(LocalizationManager.self) private var loc
    let area: Area
    let peak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(area.displayName(loc.language)).typo(.subheadline)
                Text(area.division.displayName(loc.language))
                    .typo(.micro).foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text(loc.num(area.seasonCases)).typo(.subheadline).monospacedDigit()
                RiskBadge(risk: area.risk, compact: true)
            }
            // One measure, one hue: bar length is the season total for every row.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.grid).frame(height: 4)
                    Capsule()
                        .fill(Palette.cases)
                        .frame(width: max(2, geometry.size.width * CGFloat(area.seasonCases) / CGFloat(max(peak, 1))),
                               height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 3)
    }
}

extension MKCoordinateRegion {
    static let bangladesh = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 23.68, longitude: 90.35),
        span: MKCoordinateSpan(latitudeDelta: 6.1, longitudeDelta: 5.0)
    )
}
