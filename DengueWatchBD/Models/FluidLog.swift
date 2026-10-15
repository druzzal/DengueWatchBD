import Foundation

/// One thing written down about fluids: a drink and how much of it, or a time
/// the reader passed urine.
///
/// WHO's first recommendation for non-severe dengue is protocolized oral
/// fluids: measure each drink, write it down, total it at the end of the day,
/// and aim to pass urine at least four to six times a day. Source: WHO,
/// *Guidelines for clinical management of arboviral diseases* (2025), section
/// 4.1. This is that record and only that record.
///
/// There is deliberately no target volume. WHO sets the volume by age and by
/// conditions such as heart or kidney disease, which is a clinician's
/// calculation; a single number on this screen would be the app prescribing.
/// The urine count is the target WHO gives patients themselves, so that one
/// is shown.
struct FluidEntry: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case drink
        case urine
    }

    var id = UUID()
    var date = Date()
    var kind: Kind
    /// For drinks. Nil for urine: WHO asks for the count, and nobody measures
    /// it at home.
    var millilitres: Int?
}

/// One day's fluid record, totalled the way WHO asks for it.
struct FluidDay: Equatable {
    let drunkMillilitres: Int
    let drinks: Int
    let urinations: Int

    var isEmpty: Bool { drinks == 0 && urinations == 0 }
}

/// A whole fluid log, summed for the front of the report.
struct FluidSummary: Equatable {
    /// Every day with anything logged, today included.
    let daysLogged: Int
    /// Mean intake over whole days with at least one drink logged. Nil when
    /// there is no whole day yet.
    let averageMillilitres: Int?
    /// Whole days with at least one urination logged.
    let daysWithUrineLogged: Int
    /// Of those, the days that reached the bottom of WHO's aim.
    let daysUrineAimMet: Int
    /// Whether today is in the log, and so left out of the figures above.
    let includesToday: Bool
}

enum FluidLog {

    /// "Adequate oral fluid intake should result in urination at least four
    /// to six times per day." — WHO 2025, section 4.1.
    static let urinationAim = 4...6

    /// The app's own warning sign: little or no urine for six hours or more.
    /// The same number as the symptom check, so the two never disagree.
    static let urineGapHours: Double = 6

    /// The night the urine gap does not count, as hours of the day: from
    /// 11 pm to 7 am. Someone who passed urine at ten and slept until seven
    /// has not gone nine hours without, in the sense the warning sign means,
    /// and telling them so first thing every morning teaches them to ignore it.
    static let nightStartHour = 23
    static let nightEndHour = 7

    /// How long a silent log still counts as being kept. Past this the reader
    /// has stopped writing things down, and a gap says nothing about them.
    static let activeLogHours: Double = 24

    /// Choices offered when adding a drink, in millilitres.
    static let presetMillilitres = [100, 150, 200, 250, 300, 500]

    /// What a single drink could plausibly be. Wide, as with the readings:
    /// this only catches typing slips.
    static let plausibleMillilitres = 50...2000

    /// The day's totals. Entries on other days are ignored.
    static func day(_ date: Date, entries: [FluidEntry],
                    calendar: Calendar = .current) -> FluidDay {
        let todays = entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
        let drinks = todays.filter { $0.kind == .drink }
        return FluidDay(drunkMillilitres: drinks.compactMap(\.millilitres).reduce(0, +),
                        drinks: drinks.count,
                        urinations: todays.filter { $0.kind == .urine }.count)
    }

    /// Each logged day's totals, oldest first. Days with nothing logged are
    /// absent rather than zero: an empty day is a day nobody wrote anything
    /// down, not a day nobody drank.
    static func daily(_ entries: [FluidEntry],
                      calendar: Calendar = .current) -> [(date: Date, day: FluidDay)] {
        let starts = Set(entries.map { calendar.startOfDay(for: $0.date) })
        return starts.sorted().map { start in
            (date: start, day: day(start, entries: entries, calendar: calendar))
        }
    }

    /// The figures a doctor scans before reading the days one by one.
    ///
    /// Only whole days count towards the average and the urine aim. The day
    /// the report is made is still going on: three urinations by noon is on
    /// course, not short of four, and averaging half a day in would make every
    /// report look as if the reader drank less than they did.
    static func summary(_ entries: [FluidEntry], now: Date = Date(),
                        calendar: Calendar = .current) -> FluidSummary {
        let days = daily(entries, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let whole = days.filter { $0.date < today }.map(\.day)

        let drinkingDays = whole.filter { $0.drinks > 0 }
        let average = drinkingDays.isEmpty ? nil
            : Int((Double(drinkingDays.map(\.drunkMillilitres).reduce(0, +))
                   / Double(drinkingDays.count)).rounded())
        // A day with no urine logged is a day it was not written down, so it
        // is left out of the count rather than counted as short.
        let urineDays = whole.filter { $0.urinations > 0 }

        return FluidSummary(
            daysLogged: days.count,
            averageMillilitres: average,
            daysWithUrineLogged: urineDays.count,
            daysUrineAimMet: urineDays.filter { $0.urinations >= urinationAim.lowerBound }.count,
            includesToday: days.contains { $0.date == today })
    }

    /// Whether the log shows no urine for longer than the warning sign allows,
    /// counting waking hours only.
    ///
    /// Only while the reader is keeping the log: someone who logged once last
    /// week has not gone a week without passing urine, they have stopped
    /// writing it down. Nothing logged at all raises nothing — a missing
    /// record is not a finding.
    static func urineGapIsLong(entries: [FluidEntry], now: Date = Date(),
                               calendar: Calendar = .current) -> Bool {
        guard let last = entries.filter({ $0.kind == .urine }).map(\.date).max(),
              now.timeIntervalSince(last) <= activeLogHours * 3600 else { return false }
        return wakingHours(from: last, to: now, calendar: calendar) >= urineGapHours
    }

    /// Hours between two moments, less any time inside the night window.
    static func wakingHours(from start: Date, to end: Date,
                            calendar: Calendar = .current) -> Double {
        guard end > start else { return 0 }
        var asleep: TimeInterval = 0
        // Every night that could overlap: the one that began the evening
        // before `start`, through the one that begins on `end`'s day.
        var day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start))!
        while day <= end {
            guard let nightStart = calendar.date(bySettingHour: nightStartHour, minute: 0,
                                                 second: 0, of: day),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day),
                  let nightEnd = calendar.date(bySettingHour: nightEndHour, minute: 0,
                                               second: 0, of: nextDay) else { break }
            let overlap = min(end, nightEnd).timeIntervalSince(max(start, nightStart))
            if overlap > 0 { asleep += overlap }
            day = nextDay
        }
        return (end.timeIntervalSince(start) - asleep) / 3600
    }
}
