import Foundation

/// Date parsing for the two formats the feed uses: `05-Sep-2026` style labels on
/// chart categories (`01-Jan-26`) and ISO dates in the metadata.
enum FeedDate {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Dhaka")
        formatter.dateFormat = "dd-MMM-yy"
        return formatter
    }()

    /// A value type rather than a shared `ISO8601DateFormatter`: that class
    /// holds mutable state, and one instance shared across actors is a data
    /// race waiting for the day two parses overlap.
    private static let isoStyle = Date.ISO8601FormatStyle(
        timeZone: TimeZone(identifier: "Asia/Dhaka") ?? .gmt
    ).year().month().day()

    /// `01-Jan-26` → that day.
    static func day(from label: String) -> Date? {
        dayFormatter.date(from: label)
    }

    /// `2026-09-05` → that day.
    static func iso(from label: String) -> Date? {
        try? Date(label, strategy: isoStyle)
    }
}
