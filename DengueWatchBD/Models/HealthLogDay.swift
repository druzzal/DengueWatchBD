import Foundation

/// One day of the reader's own record: the symptom checks they ran and the
/// readings they took, together.
///
/// They were always two separate stores, which is right — a check and a blood
/// pressure are different things recorded at different moments. But a person
/// looking back at an illness, or handing the record to a doctor, thinks in
/// days: "Tuesday I felt awful and my temperature was 39.2". Keeping them
/// apart on screen makes the reader do that join in their head.
struct HealthLogDay: Identifiable, Equatable {
    /// Start of the day, in the reader's calendar.
    let date: Date
    /// Newest first, matching both stores.
    let checks: [CaseLogEntry]
    let vitals: [VitalsEntry]

    var id: Date { date }

    var isEmpty: Bool { checks.isEmpty && vitals.isEmpty }

    /// Everything recorded that day, newest first, so a day reads as one list.
    var itemsNewestFirst: [Item] {
        let combined = checks.map(Item.check) + vitals.map(Item.vitals)
        return combined.sorted { $0.date > $1.date }
    }

    enum Item: Identifiable, Equatable {
        case check(CaseLogEntry)
        case vitals(VitalsEntry)

        var id: UUID {
            switch self {
            case .check(let entry): entry.id
            case .vitals(let entry): entry.id
            }
        }

        var date: Date {
            switch self {
            case .check(let entry): entry.date
            case .vitals(let entry): entry.date
            }
        }
    }
}

enum HealthLog {
    /// Groups both stores by calendar day, newest day first.
    ///
    /// Days with nothing in them are absent rather than empty: a gap in the
    /// record is a day the reader did not write anything down, and inventing a
    /// row for it would suggest they recorded "nothing wrong".
    static func days(checks: [CaseLogEntry],
                     vitals: [VitalsEntry],
                     calendar: Calendar = .current) -> [HealthLogDay] {
        var checksByDay: [Date: [CaseLogEntry]] = [:]
        for entry in checks {
            checksByDay[calendar.startOfDay(for: entry.date), default: []].append(entry)
        }
        var vitalsByDay: [Date: [VitalsEntry]] = [:]
        for entry in vitals {
            vitalsByDay[calendar.startOfDay(for: entry.date), default: []].append(entry)
        }

        return Set(checksByDay.keys).union(vitalsByDay.keys)
            .sorted(by: >)
            .map { day in
                HealthLogDay(
                    date: day,
                    checks: (checksByDay[day] ?? []).sorted { $0.date > $1.date },
                    vitals: (vitalsByDay[day] ?? []).sorted { $0.date > $1.date })
            }
    }
}
