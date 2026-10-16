import XCTest
@testable import DengueWatchBD

/// The decisions behind the alerts, apart from the notification centre: the
/// once-a-day gate, when the Sunday digest goes out, and what it says. Each is
/// a place where getting it slightly wrong turns a useful alert into one the
/// reader switches off. Android tests the same three in `AlertSchedulingTest`.
@MainActor
final class AlertDecisionTests: XCTestCase {

    func testAnAlertGoesOutOnceADay() {
        let today: TimeInterval = 1_760_000_000
        XCTAssertTrue(NotificationManager.isDueToday(lastAlertDay: 0, today: today), "never sent")
        XCTAssertTrue(NotificationManager.isDueToday(lastAlertDay: today - 86_400, today: today), "sent yesterday")
        XCTAssertFalse(NotificationManager.isDueToday(lastAlertDay: today, today: today), "sent today")
        XCTAssertFalse(NotificationManager.isDueToday(lastAlertDay: today + 86_400, today: today),
                       "a clock moved back is not a reason to repeat")
    }

    func testTheDigestIsSundayAtNine() {
        let schedule = NotificationManager.digestSchedule
        XCTAssertEqual(schedule.weekday, 1)
        XCTAssertEqual(schedule.hour, 9)
        XCTAssertEqual(schedule.minute ?? 0, 0)
    }

    func testTheDigestCarriesTheWeeksFigures() async throws {
        let store = DengueStore()
        await store.load()
        XCTAssertFalse(store.areas.isEmpty, "the bundled feed has areas")
        let loc = LocalizationManager()
        let body = NotificationManager.digestBody(store: store, localization: loc)
        XCTAssertTrue(body.contains(loc.num(store.last7Cases)), body)
        XCTAssertNotEqual(body, loc.t("dash.title"))
    }

    func testWithNoFiguresTheDigestNamesTheApp() {
        let loc = LocalizationManager()
        XCTAssertEqual(NotificationManager.digestBody(store: nil, localization: loc), loc.t("dash.title"))
    }
}
