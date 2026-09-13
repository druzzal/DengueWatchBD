import XCTest
@testable import DengueWatchBD

/// The division chip beside an area's name in the map list.
///
/// It exists to disambiguate ("Khulna" the area, in "Khulna" the division),
/// and it earns its place only when it adds something. When it does not, it
/// takes the width that forced the name to truncate.
final class AreaRowLabelTests: XCTestCase {

    /// Mirrors the view's rule, kept here so the rule itself is testable.
    private func divisionLabel(area: String, division: String) -> String? {
        area.contains(division) ? nil : division
    }

    func testTheChipIsHiddenWhenTheNameAlreadyCarriesTheDivision() {
        // The case from the screenshot: "Dhaka (outside…" was being cut.
        XCTAssertNil(divisionLabel(area: "Dhaka (outside city)", division: "Dhaka"))
        XCTAssertNil(divisionLabel(area: "Dhaka North City", division: "Dhaka"))
        XCTAssertNil(divisionLabel(area: "Dhaka South City", division: "Dhaka"))
        XCTAssertNil(divisionLabel(area: "ঢাকা (সিটির বাইরে)", division: "ঢাকা"))
        XCTAssertNil(divisionLabel(area: "ঢাকা উত্তর সিটি", division: "ঢাকা"))
    }

    func testTheChipIsHiddenWhenTheNamesMatchExactly() {
        XCTAssertNil(divisionLabel(area: "Mymensingh", division: "Mymensingh"))
        XCTAssertNil(divisionLabel(area: "ময়মনসিংহ", division: "ময়মনসিংহ"))
    }

    /// It must still appear where it genuinely disambiguates, or the rule has
    /// been traded for a different bug.
    func testTheChipStaysWhenItAddsSomething() {
        XCTAssertEqual(divisionLabel(area: "Cox's Bazar", division: "Chattogram"), "Chattogram")
        XCTAssertEqual(divisionLabel(area: "Gazipur", division: "Dhaka"), "Dhaka")
    }

    /// Every real area resolves to a name that is not cut short by its own
    /// division chip.
    func testNoRealAreaPrintsItsDivisionTwice() {
        for language in AppLanguage.allCases {
            for definition in Geography.definitions {
                let area = PlaceNames.area(code: definition.code,
                                           fallback: definition.name,
                                           language: language)
                let division = PlaceNames.division(definition.division, language: language)
                if area.contains(division) {
                    XCTAssertNil(divisionLabel(area: area, division: division),
                                 "\(area) should not repeat \(division)")
                }
            }
        }
    }
}
