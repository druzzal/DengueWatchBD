import XCTest
@testable import DengueWatchBD

/// The dates the feed carries, parsed.
///
/// `last_updated` decides whether the app calls its own figures fresh, stale
/// or outdated, and every "Reported 12 Sep" on screen comes from it. The
/// parser behind it was changed from a shared ISO8601DateFormatter — a class
/// with mutable state, unsafe to share across actors — to a value-type format
/// style. These pin that the swap did not change what it reads.
@MainActor
final class FeedDateParsingTests: XCTestCase {

    private var dhaka: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Dhaka")!
        return c
    }

    func testTheFeedsFullDateIsParsed() throws {
        let date = try XCTUnwrap(FeedDate.iso(from: "2026-09-05"),
                                 "the feed's own last_updated format")
        let parts = dhaka.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 9)
        XCTAssertEqual(parts.day, 5)
    }

    func testItReadsDatesAcrossTheYear() throws {
        for (text, month, day) in [("2026-01-01", 1, 1), ("2026-12-31", 12, 31),
                                   ("2026-02-29", 3, 1)] {   // 2026 is not a leap year
            let date = try XCTUnwrap(FeedDate.iso(from: text), text)
            let parts = dhaka.dateComponents([.month, .day], from: date)
            XCTAssertEqual(parts.month, month, text)
            XCTAssertEqual(parts.day, day, text)
        }
    }

    func testRubbishIsRejectedRatherThanGuessedAt() {
        // A date the app cannot read must come back nil, so freshness falls
        // back rather than inventing a day.
        for text in ["", "not a date", "05-09-2026", "2026/09/05"] {
            XCTAssertNil(FeedDate.iso(from: text), text)
        }
    }

    /// The press-release label, which is a different shape again.
    func testTheDayLabelFormatStillParses() throws {
        let date = try XCTUnwrap(FeedDate.day(from: "05-Sep-26"))
        let parts = dhaka.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual([parts.year, parts.month, parts.day], [2026, 9, 5])
    }
}
