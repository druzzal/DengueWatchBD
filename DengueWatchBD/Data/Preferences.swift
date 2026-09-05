import Foundation
import Observation

/// User settings. Small enough to live in UserDefaults, and none of it leaves
/// the device.
@MainActor
@Observable
final class Preferences {
    private enum Key {
        /// Deliberately a new key, not the old "homeDistrictCode".
        ///
        /// Geography changed meaning in this version: the app used to store one
        /// of 64 district codes and now stores one of 10 reporting areas. Seven
        /// of the old codes ("KHULNA", "SYLHET", …) are also valid area codes,
        /// so reusing the key would silently promote someone's home district to
        /// the whole division without telling them. A new key drops the stale
        /// value and asks them to choose again.
        static let homeArea = "homeAreaCode"
        static let alertsEnabled = "alertsEnabled"
        static let alertThreshold = "alertThresholdRawValue"
        static let weeklyDigest = "weeklyDigestEnabled"
        static let hasSeenDisclaimer = "hasSeenDisclaimer"
        static let geofenceAlerts = "geofenceAlertsEnabled"
    }

    private let defaults: UserDefaults

    var homeAreaCode: String? {
        didSet { defaults.set(homeAreaCode, forKey: Key.homeArea) }
    }

    var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Key.alertsEnabled) }
    }

    /// Raise a local alert once the home area reaches this band.
    var alertThreshold: RiskLevel {
        didSet { defaults.set(alertThreshold.rawValue, forKey: Key.alertThreshold) }
    }

    var weeklyDigestEnabled: Bool {
        didSet { defaults.set(weeklyDigestEnabled, forKey: Key.weeklyDigest) }
    }

    var hasSeenDisclaimer: Bool {
        didSet { defaults.set(hasSeenDisclaimer, forKey: Key.hasSeenDisclaimer) }
    }

    /// Warn the user when they physically enter a high-risk area.
    var geofenceAlertsEnabled: Bool {
        didSet { defaults.set(geofenceAlertsEnabled, forKey: Key.geofenceAlerts) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        homeAreaCode = defaults.string(forKey: Key.homeArea)
        alertsEnabled = defaults.bool(forKey: Key.alertsEnabled)
        alertThreshold = defaults.object(forKey: Key.alertThreshold)
            .flatMap { RiskLevel(rawValue: $0 as? Int ?? -1) } ?? .high
        weeklyDigestEnabled = defaults.bool(forKey: Key.weeklyDigest)
        hasSeenDisclaimer = defaults.bool(forKey: Key.hasSeenDisclaimer)
        geofenceAlertsEnabled = defaults.bool(forKey: Key.geofenceAlerts)
    }
}
