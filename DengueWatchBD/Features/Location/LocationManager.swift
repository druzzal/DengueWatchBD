import CoreLocation
import Foundation
import Observation

/// The single owner of CoreLocation in the app.
///
/// Two jobs, deliberately kept apart:
///   1. region monitoring for high-risk districts,
///   2. a coarse "where am I" for the nearby-hospital search.
///
/// Nothing here uploads a coordinate. Everything is evaluated on the device.
@MainActor
@Observable
final class LocationManager: NSObject {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var lastKnownLocation: CLLocation?
    private(set) var monitoredDistrictCodes: Set<String> = []

    /// Called when the device enters a monitored high-risk district.
    var onRegionEntry: ((String) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
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

    // MARK: - High-risk district geofences

    /// iOS allows 20 monitored regions per app, so only the worst districts are
    /// watched — sorted by incidence, which is what `districts` should already be.
    func monitorHighRiskDistricts(_ districts: [District]) {
        stopMonitoringAll()
        guard hasBackgroundAuthorization else { return }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        for district in districts.prefix(20) {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: district.latitude,
                                               longitude: district.longitude),
                // Districts are not circles; this is a deliberate approximation
                // around the district centre, wide enough to catch arrival in
                // the populated core without covering neighbours entirely.
                radius: 18_000,
                identifier: district.code
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
            monitoredDistrictCodes.insert(district.code)
        }
    }

    func stopMonitoringAll() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        monitoredDistrictCodes.removeAll()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorization = status
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
            self.onRegionEntry?(region.identifier)
        }
    }
}
