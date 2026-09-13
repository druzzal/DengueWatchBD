import XCTest
import CoreLocation
@testable import DengueWatchBD

/// Which reporting area a coordinate resolves to. The home hero now reads its
/// risk from this, so being wrong here means showing someone another area's
/// risk as their own.
final class NearestAreaTests: XCTestCase {

    func testDhakaCityCorporationsAreSeparatedByTheirBoundaries() {
        // Gulshan is DNCC; Motijheel is DSCC. The two sit a few km apart, and
        // the centroid test alone cannot tell them apart — which is why the
        // boundaries exist.
        XCTAssertEqual(Geography.cityCorporationCode(latitude: 23.7925, longitude: 90.4078), "DNCC")
        XCTAssertEqual(Geography.cityCorporationCode(latitude: 23.7330, longitude: 90.4172), "DSCC")
    }

    func testThePointsUsedToCheckTheMapResolveAsExpected() {
        XCTAssertEqual(Geography.cityCorporationCode(latitude: 23.8103, longitude: 90.4125), "DNCC")
        XCTAssertEqual(Geography.cityCorporationCode(latitude: 23.7104, longitude: 90.4074), "DSCC")
    }

    func testSomewhereOutsideBothCorporationsIsNeither() {
        // Savar is in Dhaka division but outside both city corporations.
        XCTAssertNil(Geography.cityCorporationCode(latitude: 23.8583, longitude: 90.2667))
    }

    func testCoordinatesOutsideBangladeshAreRejected() {
        // Kolkata is nearer to several area centres than St Martin's Island is,
        // so containment has to do this, not distance.
        XCTAssertFalse(Geography.containsBangladesh(latitude: 22.5726, longitude: 88.3639))
        XCTAssertTrue(Geography.containsBangladesh(latitude: 23.8103, longitude: 90.4125))
    }
}
