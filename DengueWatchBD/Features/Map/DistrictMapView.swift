import SwiftUI
import MapKit

enum MapMetric: String, CaseIterable, Identifiable {
    case total, rate
    var id: String { rawValue }
    var labelKey: String { "map.metric.\(rawValue)" }
    var explanationKey: String { "map.explain.\(rawValue)" }

    func value(for district: District) -> Double {
        switch self {
        case .total: Double(district.seasonCases)
        case .rate: district.incidencePer100k
        }
    }
}

struct DistrictMapView: View {
    @Environment(SurveillanceStore.self) private var store
    @Environment(LocalizationManager.self) private var loc
    @Environment(LocationManager.self) private var location
    @Environment(Preferences.self) private var preferences
    @State private var metric: MapMetric = .total
    @State private var showsList = false
    @State private var searchText = ""
    @State private var showingLocationExplainer = false
    @State private var camera: MapCameraPosition = .region(.bangladesh)
    @State private var selectedDistrict: District?
    @State private var pushedDistrict: District?

    private var maxValue: Double {
        max(store.districts.map { metric.value(for: $0) }.max() ?? 1, 1)
    }

    private var filtered: [District] {
        guard !searchText.isEmpty else { return store.districtsByCases }
        return store.districtsByCases.filter {
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
                case .loaded where store.districts.isEmpty:
                    EmptyStateView(symbol: "map",
                                   title: loc.t("map.state.emptyTitle"),
                                   message: loc.t("map.state.emptyMessage"))
                case .loaded:
                    if showsList { districtList } else { officialMap }
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
            .navigationDestination(for: District.self) { DistrictDetailView(district: $0) }
            .sheet(isPresented: $showingLocationExplainer) {
                LocationPermissionSheet {
                    location.requestWhenInUse()
                    location.startUpdatingCoarse()
                }
            }
            .sheet(item: $selectedDistrict) { district in
                AreaRiskSheet(district: district, lastUpdated: store.lastUpdated) { chosen in
                    pushedDistrict = chosen
                }
                .environment(loc)
                .environment(preferences)
            }
            .navigationDestination(item: $pushedDistrict) { DistrictDetailView(district: $0) }
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                ForEach(store.districts) { district in
                    Annotation(district.displayName(loc.language),
                               coordinate: CLLocationCoordinate2D(latitude: district.latitude,
                                                                  longitude: district.longitude),
                               anchor: .center) {
                        Button {
                            Haptic.selection()
                            selectedDistrict = district
                        } label: {
                            bubble(for: district)
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
            }
            .onChange(of: showsList) { _, isList in
                if !isList { camera = .region(.bangladesh) }
            }
            .onDisappear { location.stopUpdatingCoarse() }
            .onChange(of: location.authorization) { _, _ in
                location.startUpdatingCoarse()
            }
            // An inset rather than an overlay: MapKit then frames the country in
            // the space the legend leaves, and keeps its attribution clear of it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                legend.padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
    }

    /// Area-proportional, so a circle twice as wide means four times the value.
    private func radius(for district: District) -> CGFloat {
        5 + 22 * sqrt(max(metric.value(for: district) / maxValue, 0))
    }

    private func bubble(for district: District) -> some View {
        let size = radius(for: district) * 2
        // The mark stays proportional to the data, but the tap area never
        // drops below Apple's 44pt minimum — a low-case district was a 10pt
        // target before, effectively unreachable.
        return Circle()
            .fill(district.risk.tint.opacity(0.75))
            .overlay(Circle().strokeBorder(Palette.card, lineWidth: 2))
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .frame(width: size, height: size)
            .frame(width: max(size, Hit.minimum), height: max(size, Hit.minimum))
            .contentShape(Circle())
            .accessibilityLabel(loc.t("map.bubble.a11y", district.displayName(loc.language),
                                      loc.num(district.seasonCases),
                                      loc.t(district.risk.labelKey)))
    }

    /// Which district the user is standing in, if a fix has come through.
    private var currentDistrict: District? {
        location.lastKnownLocation.flatMap { store.nearestDistrict(to: $0) }
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
        if let currentDistrict {
            HStack(spacing: 8) {
                Button(action: zoomToUser) {
                    HStack(spacing: 7) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(loc.t("map.you.inDistrict", currentDistrict.displayName(loc.language)))
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

                RiskBadge(risk: currentDistrict.risk, compact: true)
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

    /// Shown when the user is in a high-risk district and has not yet enabled
    /// the crossing-into-a-high-risk-area warning.
    @ViewBuilder
    private var geofencePrompt: some View {
        if let district = currentDistrict, district.risk >= .high {
            if preferences.geofenceAlertsEnabled {
                HStack(spacing: Space.hair + 2) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(loc.t("geo.prompt.enabled")).typo(.micro)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
            } else {
                Button {
                    enableHighRiskAlerts()
                } label: {
                    HStack(alignment: .top, spacing: Space.tight) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(loc.t("geo.prompt.title"))
                                .typo(.micro).fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Text(loc.t("geo.prompt.enable"))
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
            Divider().overlay(Palette.hairline)
        }
    }

    private func enableHighRiskAlerts() {
        preferences.geofenceAlertsEnabled = true
        Haptic.success()
        Task {
            await NotificationManager.shared.requestAuthorization()
            location.requestAlways()
            location.monitorHighRiskDistricts(store.hotspots)
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

    private var districtList: some View {
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
                ForEach(filtered) { district in
                    NavigationLink(value: district) {
                        DistrictRow(district: district, peak: store.peakDistrictCases)
                    }
                }
            } header: {
                Text(loc.t("map.list.districts"))
            } footer: {
                Text(loc.t("map.list.footer"))
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: loc.t("map.search"))
    }
}

struct DistrictRow: View {
    @Environment(LocalizationManager.self) private var loc
    let district: District
    let peak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(district.displayName(loc.language)).typo(.subheadline)
                Text(district.division.displayName(loc.language))
                    .typo(.micro).foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text(loc.num(district.seasonCases)).typo(.subheadline).monospacedDigit()
                RiskBadge(risk: district.risk, compact: true)
            }
            // One measure, one hue: bar length is the season total for every row.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.grid).frame(height: 4)
                    Capsule()
                        .fill(Palette.cases)
                        .frame(width: max(2, geometry.size.width * CGFloat(district.seasonCases) / CGFloat(max(peak, 1))),
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
