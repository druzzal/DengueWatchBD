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
        guard Self.isDueToday(lastAlertDay: UserDefaults.standard.double(forKey: lastRiskAlertKey),
                              today: today) else { return }
        UserDefaults.standard.set(today, forKey: lastRiskAlertKey)

        let content = UNMutableNotificationContent()
        // The reader's own name for the place, as the geofence alert below
        // already uses. Left as area.name this was the one string in the app
        // that reached a Bengali reader in English — and it arrived on the
        // lock screen, above a body that was translated.
        content.title = "\(area.displayName(localization.language)): "
            + localization.t(area.risk.headlineKey)
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
    ///
    /// Takes the persisted snapshot rather than an `Area`, because this runs on
    /// a background relaunch where the feed has not loaded and there is no
    /// store to ask. Localisation is rebuilt from the stored language, so the
    /// notification still arrives in the reader's own language.
    ///
    /// Rate-limited per area per day, so a commute across a boundary does not
    /// produce a stream of notifications.
    func raiseGeofenceAlert(area: WatchedArea) async {
        guard await authorizationStatus() == .authorized else { return }

        let key = "\(lastGeofenceAlertKey).\(area.code)"
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        guard Self.isDueToday(lastAlertDay: UserDefaults.standard.double(forKey: key),
                              today: today) else { return }
        UserDefaults.standard.set(today, forKey: key)

        let localization = LocalizationManager()
        let name = PlaceNames.area(code: area.code,
                                   fallback: area.name,
                                   language: localization.language)

        let content = UNMutableNotificationContent()
        content.title = localization.t("geo.notification.title", name)
        content.body = localization.t("geo.notification.body",
                                      name,
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

    /// Schedules the Sunday digest with the latest figures in it.
    ///
    /// A calendar notification's text is fixed when it is scheduled, so this
    /// runs again whenever new figures land (see `RootView` and
    /// `BackgroundRefresh`) — otherwise the digest said only the app's name,
    /// every week, while Android's carried the week's cases and rate.
    func scheduleWeeklyDigest(enabled: Bool, localization: LocalizationManager,
                              store: DengueStore? = nil) async {
        center.removePendingNotificationRequests(withIdentifiers: [digestIdentifier])
        guard enabled, await authorizationStatus() == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = localization.t("alerts.weekly")
        content.body = Self.digestBody(store: store, localization: localization)
        content.sound = .default

        try? await center.add(UNNotificationRequest(
            identifier: digestIdentifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: Self.digestSchedule, repeats: true)
        ))
    }

    // MARK: - Decisions, apart from the notification centre

    /// Sunday at nine, the start of the working week in Bangladesh.
    static var digestSchedule: DateComponents {
        var components = DateComponents()
        components.weekday = 1
        components.hour = 9
        return components
    }

    /// The week's national figures, the same line Android posts. The app's
    /// name only when there are no figures to give.
    static func digestBody(store: DengueStore?, localization: LocalizationManager) -> String {
        guard let store, !store.areas.isEmpty else { return localization.t("dash.title") }
        return localization.t("dash.home.detail",
                              localization.num(store.last7Cases),
                              localization.decimal(store.nationalIncidencePer100k))
    }

    /// The once-a-day gate both alerts share: due unless one already went out
    /// on or after the start of today. A stored day later than today — a clock
    /// moved backwards — still counts as sent, so a wrong clock can delay an
    /// alert by a day but never repeat one.
    static func isDueToday(lastAlertDay: TimeInterval, today: TimeInterval) -> Bool {
        lastAlertDay < today
    }

}
