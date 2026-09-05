import Foundation
import Observation

/// User settings. Small enough to live in UserDefaults, and none of it leaves
/// the device.
@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let homeDistrict = "homeDistrictCode"
        static let alertsEnabled = "alertsEnabled"
        static let alertThreshold = "alertThresholdRawValue"
        static let weeklyDigest = "weeklyDigestEnabled"
        static let hasSeenDisclaimer = "hasSeenDisclaimer"
        static let geofenceAlerts = "geofenceAlertsEnabled"
    }

    private let defaults: UserDefaults

    var homeDistrictCode: String? {
        didSet { defaults.set(homeDistrictCode, forKey: Key.homeDistrict) }
    }

    var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Key.alertsEnabled) }
    }

    /// Raise a local alert once the home district reaches this band.
    var alertThreshold: RiskLevel {
        didSet { defaults.set(alertThreshold.rawValue, forKey: Key.alertThreshold) }
    }

    var weeklyDigestEnabled: Bool {
        didSet { defaults.set(weeklyDigestEnabled, forKey: Key.weeklyDigest) }
    }

    var hasSeenDisclaimer: Bool {
        didSet { defaults.set(hasSeenDisclaimer, forKey: Key.hasSeenDisclaimer) }
    }

    /// Warn the user when they physically enter a high-risk district.
    var geofenceAlertsEnabled: Bool {
        didSet { defaults.set(geofenceAlertsEnabled, forKey: Key.geofenceAlerts) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        homeDistrictCode = defaults.string(forKey: Key.homeDistrict)
        alertsEnabled = defaults.bool(forKey: Key.alertsEnabled)
        alertThreshold = defaults.object(forKey: Key.alertThreshold)
            .flatMap { RiskLevel(rawValue: $0 as? Int ?? -1) } ?? .high
        weeklyDigestEnabled = defaults.bool(forKey: Key.weeklyDigest)
        hasSeenDisclaimer = defaults.bool(forKey: Key.hasSeenDisclaimer)
        geofenceAlertsEnabled = defaults.bool(forKey: Key.geofenceAlerts)
    }
}
