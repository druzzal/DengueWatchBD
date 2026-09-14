import Foundation

/// One day of the reader's own record: the symptom checks they ran, the
/// readings they took and the lab reports they were given, together.
///
/// They were always two separate stores, which is right — a check and a blood
/// pressure are different things recorded at different moments. But a person
/// looking back at an illness, or handing the record to a doctor, thinks in
/// days: "Tuesday I felt awful and my temperature was 39.2". Keeping them
/// apart on screen makes the reader do that join in their head.
struct HealthLogDay: Identifiable, Equatable {
    /// Start of the day, in the reader's calendar.
    let date: Date
    /// Newest first, matching the stores.
    let checks: [CaseLogEntry]
    let vitals: [VitalsEntry]
    let labs: [LabReport]

    var id: Date { date }

    var isEmpty: Bool { checks.isEmpty && vitals.isEmpty && labs.isEmpty }

    /// Everything recorded that day, newest first, so a day reads as one list.
    var itemsNewestFirst: [Item] {
        let combined = checks.map(Item.check) + vitals.map(Item.vitals) + labs.map(Item.lab)
        return combined.sorted { $0.date > $1.date }
    }

    enum Item: Identifiable, Equatable {
        case check(CaseLogEntry)
        case vitals(VitalsEntry)
        case lab(LabReport)

        var id: UUID {
            switch self {
            case .check(let entry): entry.id
            case .vitals(let entry): entry.id
            case .lab(let report): report.id
            }
        }

        /// The name the reader gave this record, or empty if they have not.
        var name: String {
            switch self {
            case .check(let entry): entry.name
            case .vitals(let entry): entry.name
            case .lab(let report): report.name
            }
        }

        var date: Date {
            switch self {
            case .check(let entry): entry.date
            case .vitals(let entry): entry.date
            case .lab(let report): report.date
            }
        }
    }
}

enum HealthLog {

    /// Numbers every record in the order it was made, oldest first.
    ///
    /// Counting from the oldest is what keeps a number attached to a record:
    /// numbering the list as displayed would renumber everything each time a
    /// new reading arrived, so "Log 3" would mean a different afternoon every
    /// day. Deleting an earlier record does shift the ones after it, which is
    /// the price of numbering at all — a reader who cares gives it a name.
    static func numbers(checks: [CaseLogEntry],
                        vitals: [VitalsEntry],
                        labs: [LabReport]) -> [UUID: Int] {
        let all: [(id: UUID, date: Date)] =
            checks.map { ($0.id, $0.date) }
            + vitals.map { ($0.id, $0.date) }
            + labs.map { ($0.id, $0.date) }
        // Ties break on the id so the numbering is the same on every render.
        let ordered = all.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
        return Dictionary(uniqueKeysWithValues:
            ordered.enumerated().map { ($0.element.id, $0.offset + 1) })
    }

    /// Groups both stores by calendar day, newest day first.
    ///
    /// Days with nothing in them are absent rather than empty: a gap in the
    /// record is a day the reader did not write anything down, and inventing a
    /// row for it would suggest they recorded "nothing wrong".
    static func days(checks: [CaseLogEntry],
                     vitals: [VitalsEntry],
                     labs: [LabReport] = [],
                     calendar: Calendar = .current) -> [HealthLogDay] {
        var checksByDay: [Date: [CaseLogEntry]] = [:]
        for entry in checks {
            checksByDay[calendar.startOfDay(for: entry.date), default: []].append(entry)
        }
        var vitalsByDay: [Date: [VitalsEntry]] = [:]
        for entry in vitals {
            vitalsByDay[calendar.startOfDay(for: entry.date), default: []].append(entry)
        }

        var labsByDay: [Date: [LabReport]] = [:]
        for report in labs {
            labsByDay[calendar.startOfDay(for: report.date), default: []].append(report)
        }

        return Set(checksByDay.keys).union(vitalsByDay.keys).union(labsByDay.keys)
            .sorted(by: >)
            .map { day in
                HealthLogDay(
                    date: day,
                    checks: (checksByDay[day] ?? []).sorted { $0.date > $1.date },
                    vitals: (vitalsByDay[day] ?? []).sorted { $0.date > $1.date },
                    labs: (labsByDay[day] ?? []).sorted { $0.date > $1.date })
            }
    }
}
