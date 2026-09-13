import XCTest
import CoreLocation
@testable import DengueWatchBD

/// Contracts CoreLocation enforces at runtime rather than at compile time.
@MainActor
final class LocationManagerContractTests: XCTestCase {

    /// `requestLocation()` raises an assertion — and terminates the app — if
    /// the delegate does not implement `didFailWithError`. Home and Care both
    /// take a one-shot fix, so this is a launch crash if it ever goes missing
    /// again. It went missing once: the delegate had the three methods the
    /// streaming API needs and not this one, and the app aborted on the first
    /// launch of the Home tab.
    func testTheDelegateImplementsTheMethodRequestLocationRequires() {
        let manager = LocationManager()
        XCTAssertTrue(
            manager.responds(to: #selector(CLLocationManagerDelegate.locationManager(_:didFailWithError:))),
            "requestLocation() aborts without didFailWithError")
    }

    /// The other delegate methods the app relies on, for the same reason.
    func testTheDelegateImplementsTheMethodsTheAppRelieson() {
        let manager = LocationManager()
        for selector in [
            #selector(CLLocationManagerDelegate.locationManager(_:didUpdateLocations:)),
            #selector(CLLocationManagerDelegate.locationManager(_:didEnterRegion:)),
        ] {
            XCTAssertTrue(manager.responds(to: selector), "\(selector)")
        }
    }
}
