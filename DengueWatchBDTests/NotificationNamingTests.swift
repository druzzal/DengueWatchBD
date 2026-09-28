import XCTest
@testable import DengueWatchBD

/// The place names that reach a notification.
///
/// A notification is read on the lock screen, away from the app and away from
/// any other context — so if the app has been switched to Bengali, an English
/// place name there is more jarring than anywhere inside the app, and there is
/// nothing around it to explain the switch.
final class NotificationNamingTests: XCTestCase {

    private func area(_ code: String, name: String) -> Area {
        Area(code: code, name: name, division: .dhaka,
             latitude: 23.8, longitude: 90.4, populationThousands: 5980,
             seasonCases: 100, seasonDeaths: 1, weeklyCases: [30, 40],
             weeklyIsApportioned: false, geofenceRadiusMeters: 12_000)
    }

    func testAnAreaNamesItselfInBengaliWhenAskedTo() {
        let dhakaNorth = area("DNCC", name: "Dhaka North City")
        XCTAssertEqual(dhakaNorth.displayName(.english), "Dhaka North City")
        XCTAssertNotEqual(dhakaNorth.displayName(.bangla), "Dhaka North City",
                          "a Bengali reader should get the Bengali name")
    }

    /// Every area the app knows has a Bengali name, since any of them can be
    /// the one a reader is standing in when an alert fires.
    func testEveryAreaHasABengaliName() {
        for definition in Geography.definitions {
            let name = PlaceNames.area(code: definition.code,
                                       fallback: definition.name,
                                       language: .bangla)
            XCTAssertNotEqual(name, definition.name,
                              "\(definition.code) falls back to its English name")
            XCTAssertFalse(name.isEmpty)
        }
    }

    /// An unknown code must fall back rather than show nothing — a blank title
    /// would be worse than an English one.
    func testAnUnknownAreaFallsBackToTheNameItWasGiven() {
        XCTAssertEqual(PlaceNames.area(code: "NOWHERE", fallback: "Somewhere",
                                       language: .bangla),
                       "Somewhere")
    }
}
