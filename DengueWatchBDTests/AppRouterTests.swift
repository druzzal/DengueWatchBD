import XCTest
@testable import DengueWatchBD

/// Sending the reader from one tab to something on another.
///
/// The risk a request carries is outliving the moment it was made: the tab that
/// honours it presents a sheet, and a request still sitting there would present
/// that sheet again every time the reader came back to the tab.
@MainActor
final class AppRouterTests: XCTestCase {

    func testShowingATabSelectsIt() {
        let router = AppRouter()
        router.show(.health)
        XCTAssertEqual(router.selectedTab, .health)
    }

    func testATabWithoutARequestAsksForNothing() {
        let router = AppRouter()
        router.show(.health)
        XCTAssertNil(router.pending)
    }

    func testARequestReachesTheTabItWasSentTo() {
        let router = AppRouter()
        router.show(.health, requesting: .symptomCheck)
        XCTAssertEqual(router.selectedTab, .health)
        XCTAssertTrue(router.claim(.symptomCheck))
    }

    /// The whole point: claimed once, and then gone.
    func testARequestIsClaimedOnlyOnce() {
        let router = AppRouter()
        router.show(.health, requesting: .symptomCheck)
        XCTAssertTrue(router.claim(.symptomCheck))
        XCTAssertFalse(router.claim(.symptomCheck), "a claimed request must not fire again")
        XCTAssertNil(router.pending)
    }

    func testNothingPendingIsNotClaimable() {
        XCTAssertFalse(AppRouter().claim(.symptomCheck))
    }

    /// Leaving for a tab that was not asked for anything must not leave the old
    /// request waiting to fire on some later visit.
    func testMovingOnClearsAnUnclaimedRequest() {
        let router = AppRouter()
        router.show(.health, requesting: .symptomCheck)
        router.show(.map)
        XCTAssertNil(router.pending)
        XCTAssertFalse(router.claim(.symptomCheck))
    }

    func testEveryTabHasATitleAndASymbol() {
        for tab in AppRouter.Tab.allCases {
            XCTAssertEqual(tab.titleKey, "tab.\(tab.rawValue)")
            XCTAssertFalse(tab.symbol.isEmpty)
        }
    }
}
