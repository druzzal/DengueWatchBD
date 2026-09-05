import Foundation

/// What the app needs to raise an entry alert, without any of the rest of the app.
///
/// When iOS relaunches the app in the background for a boundary crossing, there
/// is no guarantee the UI has been built or the feed has loaded — the alert has
/// to be composed from something already on disk. This is that something:
/// written whenever the geofences are armed, read when a region fires.
struct WatchedArea: Codable, Hashable {
    let code: String
    /// English name; the Bengali one is looked up by `code` at fire time, so a
    /// reader who switches language still gets the notification in it.
    let name: String
    let riskRawValue: Int
    let lastWeekCases: Int
    /// Enough to rebuild the region without the feed, so monitoring can be
    /// re-armed the moment "Always" is granted rather than waiting for the next
    /// time someone opens the app.
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double

    var risk: RiskLevel { RiskLevel(rawValue: riskRawValue) ?? .high }

    init(area: Area) {
        code = area.code
        name = area.name
        riskRawValue = area.risk.rawValue
        lastWeekCases = area.lastWeekCases
        latitude = area.latitude
        longitude = area.longitude
        radiusMeters = area.geofenceRadiusMeters
    }
}

/// The armed set, on disk.
enum WatchedAreaStore {
    private static let key = "geofence.watchedAreas"

    static func save(_ areas: [WatchedArea], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(areas) else { return }
        defaults.set(data, forKey: key)
    }

    static func load(from defaults: UserDefaults = .standard) -> [WatchedArea] {
        guard let data = defaults.data(forKey: key),
              let areas = try? JSONDecoder().decode([WatchedArea].self, from: data) else {
            return []
        }
        return areas
    }

    static func area(code: String, in defaults: UserDefaults = .standard) -> WatchedArea? {
        load(from: defaults).first { $0.code == code }
    }

    static func clear(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
