import CoreLocation
import Foundation
import Observation

/// The single owner of CoreLocation in the app.
///
/// Two jobs, deliberately kept apart:
///   1. region monitoring for high-risk areas,
///   2. a coarse "where am I" for the nearby-hospital search.
///
/// Nothing here uploads a coordinate. Everything is evaluated on the device.
@MainActor
@Observable
final class LocationManager: NSObject {
    /// One instance for the process, created at launch by `AppDelegate`.
    ///
    /// It used to be a `@State` inside `RootView`, which meant CoreLocation was
    /// only wired up once SwiftUI built the view. When iOS relaunches the app in
    /// the background for a boundary crossing there is no such guarantee, so
    /// entry events could arrive with nothing listening and be dropped — the
    /// alert silently not firing in exactly the case it exists for.
    static let shared = LocationManager()

    private(set) var authorization: CLAuthorizationStatus
    private(set) var lastKnownLocation: CLLocation?
    private(set) var monitoredAreaCodes: Set<String> = []

    /// Optional hook for the UI. The notification does not depend on it.
    var onRegionEntry: ((String) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // iOS keeps monitored regions across launches, so what is already being
        // watched is authoritative — not whatever the UI last happened to arm.
        monitoredAreaCodes = Set(manager.monitoredRegions.map(\.identifier))
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var hasBackgroundAuthorization: Bool { authorization == .authorizedAlways }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    /// Region monitoring keeps working with the app closed only under "Always".
    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    // MARK: - Coarse location for nearby search

    func startUpdatingCoarse() {
        guard isAuthorized else { return }
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.startUpdatingLocation()
    }

    func stopUpdatingCoarse() {
        manager.stopUpdatingLocation()
    }

    // MARK: - High-risk area geofences

    /// iOS allows 20 monitored regions per app, so only the worst areas are
    /// watched — sorted by incidence, which is what `areas` should already be.
    /// Record what should be watched, then watch it if iOS currently allows.
    ///
    /// The order matters. This used to stop monitoring before checking
    /// authorization, so a call made without "Always" tore down every region
    /// and cleared the snapshot on its way to returning early. And the intent
    /// is saved even when arming is not yet possible, because the usual path is
    /// exactly that: the toggle asks for permission and calls this immediately,
    /// long before the reader has answered the prompt.
    func monitorHighRiskAreas(_ areas: [Area]) {
        let watched = areas.prefix(20).map(WatchedArea.init)
        WatchedAreaStore.save(watched)

        guard hasBackgroundAuthorization,
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        stopMonitoringRegions()
        for area in areas.prefix(20) {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: area.latitude,
                                               longitude: area.longitude),
                // Areas are not circles, so this is an approximation around the
                // centre — but sized per area, because one radius cannot serve
                // both a 12 km city corporation and a 200 km division. Clamped
                // to what the device will monitor.
                radius: min(area.geofenceRadiusMeters,
                            manager.maximumRegionMonitoringDistance),
                identifier: area.code
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
            monitoredAreaCodes.insert(area.code)
        }
    }

    /// Arm from the saved intent, with no need for the feed or the store.
    ///
    /// Called when authorization becomes "Always": the reader has just answered
    /// the prompt the toggle raised, and without this nothing would be watched
    /// until they next opened the app.
    func rearmFromSnapshot() {
        let watched = WatchedAreaStore.load()
        guard !watched.isEmpty,
              hasBackgroundAuthorization,
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        stopMonitoringRegions()
        for area in watched {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: area.latitude,
                                               longitude: area.longitude),
                radius: min(area.radiusMeters, manager.maximumRegionMonitoringDistance),
                identifier: area.code
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
            monitoredAreaCodes.insert(area.code)
        }
    }

    /// Regions only. `stopMonitoringAll` also forgets the intent.
    private func stopMonitoringRegions() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        monitoredAreaCodes.removeAll()
    }

    /// Stop watching and forget what we meant to watch — the toggle being
    /// switched off, not a temporary loss of permission.
    func stopMonitoringAll() {
        stopMonitoringRegions()
        WatchedAreaStore.clear()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            let wasBackground = self.hasBackgroundAuthorization
            self.authorization = status
            // The moment "Always" is granted, arm what the toggle already asked
            // for. Until this, enabling alerts armed nothing until relaunch.
            if !wasBackground, self.hasBackgroundAuthorization {
                self.rearmFromSnapshot()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.lastKnownLocation = location
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didEnterRegion region: CLRegion) {
        Task { @MainActor in
            // Raised from the persisted snapshot rather than from the store, so
            // this works on a cold background launch where nothing else is up.
            if let watched = WatchedAreaStore.area(code: region.identifier) {
                await NotificationManager.shared.raiseGeofenceAlert(area: watched)
            }
            self.onRegionEntry?(region.identifier)
        }
    }
}
