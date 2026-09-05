import SwiftUI

struct RootView: View {
    @State private var store = DengueStore()
    @State private var caseLog = CaseLogStore()
    @State private var preferences = Preferences()
    @State private var localization = LocalizationManager()
    @State private var location = LocationManager()
    @State private var sync = FeedSync()
    @State private var router = AppRouter()

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: tabSelection) {
            DashboardView()
                .tabItem { Label(localization.t("tab.home"), systemImage: AppRouter.Tab.home.symbol) }
                .tag(AppRouter.Tab.home)

            AreaMapView()
                .tabItem { Label(localization.t("tab.map"), systemImage: AppRouter.Tab.map.symbol) }
                .tag(AppRouter.Tab.map)

            SymptomCheckerView()
                .tabItem { Label(localization.t("tab.check"), systemImage: AppRouter.Tab.check.symbol) }
                .tag(AppRouter.Tab.check)

            CareView()
                .tabItem { Label(localization.t("tab.care"), systemImage: AppRouter.Tab.care.symbol) }
                .tag(AppRouter.Tab.care)

            PreventionView()
                .tabItem { Label(localization.t("tab.prevent"), systemImage: AppRouter.Tab.prevent.symbol) }
                .tag(AppRouter.Tab.prevent)
        }
        .tint(Palette.accent)
        .environment(store)
        .environment(caseLog)
        .environment(preferences)
        .environment(localization)
        .environment(location)
        .environment(sync)
        .environment(router)
        .task {
            await store.load()
            sync.start(store: store)
            await sync.sync(force: false)
            configureLocationHandling()
            await evaluateAlerts()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await sync.sync(force: false)
                await evaluateAlerts()
            }
        }
        // Driven directly by the stored preference. Mirroring it into @State and
        // setting that inside `.task` looked correct but never presented: a
        // sheet whose binding flips while TabView is still building its tabs is
        // silently dropped. A derived binding avoids the race, and a
        // full-screen cover is the right affordance for a notice the user must
        // acknowledge before seeing any figures.
        .fullScreenCover(isPresented: Binding(
            get: { !preferences.hasSeenDisclaimer },
            set: { presented in
                if !presented { preferences.hasSeenDisclaimer = true }
            }
        )) {
            FirstRunDisclaimerView()
                .environment(preferences)
                .environment(localization)
        }
    }

    /// Selection is owned by the router so any screen can send the user to
    /// another tab, and a debug hook can open one directly.
    private var tabSelection: Binding<AppRouter.Tab> {
        Binding(get: { router.selectedTab },
                set: { router.selectedTab = $0 })
    }

    /// Wires region entry to a notification, and re-arms the geofences against
    /// whatever the current hotspot list is.
    private func configureLocationHandling() {
        location.onRegionEntry = { code in
            guard let area = store.area(code: code) else { return }
            Task {
                await NotificationManager.shared.raiseGeofenceAlert(area: area,
                                                                    localization: localization)
            }
        }
        if preferences.geofenceAlertsEnabled {
            location.monitorHighRiskAreas(store.hotspots)
        }
        #if DEBUG
        // Screenshot and UI-test hook:
        // SIMCTL_CHILD_DW_START_TAB=map xcrun simctl launch ...
        if let raw = ProcessInfo.processInfo.environment["DW_START_TAB"],
           let tab = AppRouter.Tab(rawValue: raw) {
            router.selectedTab = tab
        }
        #endif
    }

    private func evaluateAlerts() async {
        guard preferences.alertsEnabled,
              let code = preferences.homeAreaCode,
              let area = store.area(code: code) else { return }
        await NotificationManager.shared.raiseRiskAlertIfNeeded(area: area,
                                                                threshold: preferences.alertThreshold,
                                                                localization: localization)
    }
}
