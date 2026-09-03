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

    // MARK: - Home district risk

    /// Fires at most once a day, and only when the home district has actually
    /// reached the band the user asked to hear about.
    func raiseRiskAlertIfNeeded(district: District,
                                threshold: RiskLevel,
                                localization: LocalizationManager) async {
        guard district.risk >= threshold else { return }
        guard await authorizationStatus() == .authorized else { return }

        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        guard today > UserDefaults.standard.double(forKey: lastRiskAlertKey) else { return }
        UserDefaults.standard.set(today, forKey: lastRiskAlertKey)

        let content = UNMutableNotificationContent()
        content.title = "\(district.name): \(localization.t(district.risk.headlineKey))"
        content.body = localization.t("dash.home.detail",
                                      localization.num(district.last7Cases),
                                      localization.decimal(district.incidencePer100k))
            + " " + localization.t(district.risk.guidanceKey)
        content.sound = .default

        try? await center.add(UNNotificationRequest(
            identifier: "risk-\(district.code)-\(Int(today))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        ))
    }

    // MARK: - Entering a high-risk district

    /// Raised when the device crosses into a monitored high-risk district.
    /// Rate-limited per district per day, so a commute across a boundary does
    /// not produce a stream of notifications.
    func raiseGeofenceAlert(district: District, localization: LocalizationManager) async {
        guard await authorizationStatus() == .authorized else { return }

        let key = "\(lastGeofenceAlertKey).\(district.code)"
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        guard today > UserDefaults.standard.double(forKey: key) else { return }
        UserDefaults.standard.set(today, forKey: key)

        let content = UNMutableNotificationContent()
        content.title = localization.t("geo.notification.title", district.name)
        content.body = localization.t("geo.notification.body",
                                      district.name,
                                      localization.t(district.risk.labelKey),
                                      localization.num(district.last7Cases))
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        try? await center.add(UNNotificationRequest(
            identifier: "geo-\(district.code)-\(Int(today))",
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

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}
