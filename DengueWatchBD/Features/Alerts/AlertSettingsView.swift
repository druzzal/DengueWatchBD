import SwiftUI
import CoreLocation

struct AlertSettingsView: View {
    @Environment(DengueStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(LocalizationManager.self) private var loc
    @Environment(LocationManager.self) private var location

    @State private var permissionDenied = false

    private var homeArea: Area? {
        preferences.homeAreaCode.flatMap { store.area(code: $0) }
    }

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            // First, because it is the alert that works on its own: no home
            // area to pick, nothing to keep current, and it fires wherever the
            // reader happens to be. The rest of this screen depends on them
            // choosing an area first.
            geofenceSection

            Section {
                if let homeArea {
                    HStack {
                        Text(homeArea.displayName(loc.language))
                        Spacer()
                        RiskBadge(risk: homeArea.risk, compact: true)
                    }
                } else {
                    Text(loc.t("alerts.noArea")).foregroundStyle(.secondary)
                }
                NavigationLink(loc.t("alerts.chooseArea")) { AreaPickerView() }
            } header: {
                Text(loc.t("alerts.myArea"))
            } footer: {
                Text(loc.t("alerts.areaFooter"))
            }

            Section {
                Toggle(loc.t("alerts.riseToggle"), isOn: $preferences.alertsEnabled)
                    .onChange(of: preferences.alertsEnabled) { _, isOn in
                        Task {
                            guard isOn else { return }
                            let granted = await NotificationManager.shared.requestAuthorization()
                            if !granted {
                                preferences.alertsEnabled = false
                                permissionDenied = true
                            } else if let homeArea {
                                await NotificationManager.shared.raiseRiskAlertIfNeeded(
                                    area: homeArea,
                                    threshold: preferences.alertThreshold,
                                    localization: loc)
                            }
                        }
                    }

                if preferences.alertsEnabled {
                    Picker(loc.t("alerts.threshold"), selection: $preferences.alertThreshold) {
                        ForEach(RiskLevel.allCases) { level in
                            Text(loc.t("alerts.thresholdOption", loc.t(level.labelKey))).tag(level)
                        }
                    }
                }

                Toggle(loc.t("alerts.weekly"), isOn: $preferences.weeklyDigestEnabled)
                    .onChange(of: preferences.weeklyDigestEnabled) { _, isOn in
                        Task {
                            if isOn { await NotificationManager.shared.requestAuthorization() }
                            await NotificationManager.shared.scheduleWeeklyDigest(enabled: isOn,
                                                                                  localization: loc)
                        }
                    }
            } header: {
                Text(loc.t("alerts.notifications"))
            } footer: {
                Text(loc.t("alerts.footer"))
            }

            if let homeArea {
                Section(loc.t("alerts.preview")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(homeArea.risk >= preferences.alertThreshold
                             ? loc.t("alerts.preview.would", homeArea.displayName(loc.language),
                                     loc.t(homeArea.risk.labelKey))
                             : loc.t("alerts.preview.wouldNot", homeArea.displayName(loc.language),
                                     loc.t(homeArea.risk.labelKey)))
                            .typo(.subheadline)
                        Text(loc.t(homeArea.risk.guidanceKey))
                            .typo(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(loc.t("alerts.title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(loc.t("alerts.denied.title"), isPresented: $permissionDenied) {
            Button(loc.t("common.ok"), role: .cancel) {}
        } message: {
            Text(loc.t("alerts.denied.message"))
        }
    }

    /// Location-based warning when the user enters a high-risk area.
    @ViewBuilder
    private var geofenceSection: some View {
        @Bindable var preferences = preferences

        Section {
            Toggle(loc.t("geo.toggle"), isOn: $preferences.geofenceAlertsEnabled)
                .onChange(of: preferences.geofenceAlertsEnabled) { _, isOn in
                    Task {
                        guard isOn else {
                            location.stopMonitoringAll()
                            return
                        }
                        await NotificationManager.shared.requestAuthorization()
                        location.requestAlways()
                        if let hotspots = store.hotspotsToMonitor {
                            location.monitorHighRiskAreas(hotspots)
                        }
                    }
                }

            if preferences.geofenceAlertsEnabled {
                HStack {
                    Text(loc.t("geo.status.off").isEmpty ? "" : statusLabel)
                        .typo(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !location.monitoredAreaCodes.isEmpty {
                        Text(loc.t("geo.monitoring",
                                   loc.num(location.monitoredAreaCodes.count)))
                            .typo(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !location.hasBackgroundAuthorization {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc.t("geo.permissionDetail"))
                            .typo(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(loc.t("geo.permission")) { location.requestAlways() }
                            .buttonStyle(.bordered)
                    }
                }
            }
        } header: {
            Text(loc.t("geo.section"))
        } footer: {
            Text(loc.t("geo.footer"))
        }
    }

    private var statusLabel: String {
        if location.hasBackgroundAuthorization { return loc.t("geo.status.always") }
        if location.isAuthorized { return loc.t("geo.status.foreground") }
        return loc.t("geo.status.off")
    }
}

struct AreaPickerView: View {
    @Environment(DengueStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""

    private var grouped: [(division: Division, areas: [Area])] {
        Division.allCases.compactMap { division in
            let members = store.areas(in: division)
                .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                              || $0.displayName(loc.language).localizedCaseInsensitiveContains(search) }
                .sorted { $0.name < $1.name }
            return members.isEmpty ? nil : (division, members)
        }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.division) { group in
                Section(group.division.displayName(loc.language)) {
                    ForEach(group.areas) { area in
                        Button {
                            preferences.homeAreaCode = area.code
                            dismiss()
                        } label: {
                            HStack {
                                Text(area.displayName(loc.language)).foregroundStyle(.primary)
                                Spacer()
                                if preferences.homeAreaCode == area.code {
                                    Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: loc.t("area.picker.search"))
        .navigationTitle(loc.t("area.picker.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
