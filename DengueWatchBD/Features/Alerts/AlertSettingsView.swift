import SwiftUI
import CoreLocation

struct AlertSettingsView: View {
    @Environment(SurveillanceStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(LocalizationManager.self) private var loc
    @Environment(LocationManager.self) private var location

    @State private var permissionDenied = false

    private var homeDistrict: District? {
        preferences.homeDistrictCode.flatMap { store.district(code: $0) }
    }

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section {
                if let homeDistrict {
                    HStack {
                        Text(homeDistrict.displayName(loc.language))
                        Spacer()
                        RiskBadge(risk: homeDistrict.risk, compact: true)
                    }
                } else {
                    Text(loc.t("alerts.noDistrict")).foregroundStyle(.secondary)
                }
                NavigationLink(loc.t("alerts.chooseDistrict")) { DistrictPickerView() }
            } header: {
                Text(loc.t("alerts.myDistrict"))
            } footer: {
                Text(loc.t("alerts.districtFooter"))
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
                            } else if let homeDistrict {
                                await NotificationManager.shared.raiseRiskAlertIfNeeded(
                                    district: homeDistrict,
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

            geofenceSection

            if let homeDistrict {
                Section(loc.t("alerts.preview")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(homeDistrict.risk >= preferences.alertThreshold
                             ? loc.t("alerts.preview.would", homeDistrict.displayName(loc.language),
                                     loc.t(homeDistrict.risk.labelKey))
                             : loc.t("alerts.preview.wouldNot", homeDistrict.displayName(loc.language),
                                     loc.t(homeDistrict.risk.labelKey)))
                            .typo(.subheadline)
                        Text(loc.t(homeDistrict.risk.guidanceKey))
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

    /// Location-based warning when the user enters a high-risk district.
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
                        location.monitorHighRiskDistricts(store.hotspots)
                    }
                }

            if preferences.geofenceAlertsEnabled {
                HStack {
                    Text(loc.t("geo.status.off").isEmpty ? "" : statusLabel)
                        .typo(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !location.monitoredDistrictCodes.isEmpty {
                        Text(loc.t("geo.monitoring",
                                   loc.num(location.monitoredDistrictCodes.count)))
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

struct DistrictPickerView: View {
    @Environment(SurveillanceStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""

    private var grouped: [(division: Division, districts: [District])] {
        Division.allCases.compactMap { division in
            let members = store.districts(in: division)
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
                    ForEach(group.districts) { district in
                        Button {
                            preferences.homeDistrictCode = district.code
                            dismiss()
                        } label: {
                            HStack {
                                Text(district.displayName(loc.language)).foregroundStyle(.primary)
                                Spacer()
                                if preferences.homeDistrictCode == district.code {
                                    Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: loc.t("district.picker.search"))
        .navigationTitle(loc.t("district.picker.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
