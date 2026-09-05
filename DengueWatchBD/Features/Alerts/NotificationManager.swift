import CoreLocation
import Foundation
import UserNotifications

/// Local notifications only — nothing is registered with a push server, and no
/// location or identity leaves the phone. Notification text is localised at the
/// moment of scheduling, so it arrives in whichever language the app is set to.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let lastRiskAlertKey = "lastRiskAlertDay"
    private let lastGeofenceAlertKey = "lastGeofenceAlert"
    private let digestIdentifier = "weekly-digest"

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: - Home area risk

    /// Fires at most once a day, and only when the home area has actually
    /// reached the band the user asked to hear about.
    func raiseRiskAlertIfNeeded(area: Area,
                                threshold: RiskLevel,
                                localization: LocalizationManager) async {
        guard area.risk >= threshold else { return }
        guard await authorizationStatus() == .authorized else { return }

        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        guard today > UserDefaults.standard.double(forKey: lastRiskAlertKey) else { return }
        UserDefaults.standard.set(today, forKey: lastRiskAlertKey)

        let content = UNMutableNotificationContent()
        content.title = "\(area.name): \(localization.t(area.risk.headlineKey))"
        content.body = localization.t("dash.home.detail",
                                      localization.num(area.lastWeekCases),
                                      localization.decimal(area.incidencePer100k))
            + " " + localization.t(area.risk.guidanceKey)
        content.sound = .default

        try? await center.add(UNNotificationRequest(
            identifier: "risk-\(area.code)-\(Int(today))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        ))
    }

    // MARK: - Entering a high-risk area

    /// Raised when the device crosses into a monitored high-risk area.
    /// Rate-limited per area per day, so a commute across a boundary does
    /// not produce a stream of notifications.
    func raiseGeofenceAlert(area: Area, localization: LocalizationManager) async {
        guard await authorizationStatus() == .authorized else { return }

        let key = "\(lastGeofenceAlertKey).\(area.code)"
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        guard today > UserDefaults.standard.double(forKey: key) else { return }
        UserDefaults.standard.set(today, forKey: key)

        let content = UNMutableNotificationContent()
        content.title = localization.t("geo.notification.title", area.name)
        content.body = localization.t("geo.notification.body",
                                      area.name,
                                      localization.t(area.risk.labelKey),
                                      localization.num(area.lastWeekCases))
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        try? await center.add(UNNotificationRequest(
            identifier: "geo-\(area.code)-\(Int(today))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        ))
    }

    // MARK: - Weekly digest

    func scheduleWeeklyDigest(enabled: Bool, localization: LocalizationManager) async {
        center.removePendingNotificationRequests(withIdentifiers: [digestIdentifier])
        guard enabled, await authorizationStatus() == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = localization.t("alerts.weekly")
        content.body = localization.t("dash.title")
        content.sound = .default

        var components = DateComponents()
        components.weekday = 1        // Sunday, the start of the working week in Bangladesh
        components.hour = 9

        try? await center.add(UNNotificationRequest(
            identifier: digestIdentifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        ))
    }

}
