import Foundation

/// One day of the reader's measurements: the readings they took and the lab
/// reports they were given, together.
///
/// Two separate stores, which is right — a blood pressure and a blood count
/// are taken at different moments. But a person looking back at an illness, or
/// handing the record to a doctor, thinks in days: "Tuesday my temperature was
/// 39.2 and my platelets were 96". Keeping them apart on screen makes the
/// reader do that join in their head.
///
/// Symptom checks are deliberately not here. They are not measurements — they
/// are what the reader felt, answered against WHO criteria — and they have
/// their own place in My Health, where the latest one drives the care plan and
/// the fever timeline. A log handed to a doctor is a list of numbers.
struct HealthLogDay: Identifiable, Equatable {
    /// Start of the day, in the reader's calendar.
    let date: Date
    /// Newest first, matching the stores.
    let vitals: [VitalsEntry]
    let labs: [LabReport]

    var id: Date { date }

    var isEmpty: Bool { vitals.isEmpty && labs.isEmpty }

    /// Everything recorded that day, newest first, so a day reads as one list.
    var itemsNewestFirst: [Item] {
        let combined = vitals.map(Item.vitals) + labs.map(Item.lab)
        return combined.sorted { $0.date > $1.date }
    }

    enum Item: Identifiable, Equatable {
        case vitals(VitalsEntry)
        case lab(LabReport)

        var id: UUID {
            switch self {
            case .vitals(let entry): entry.id
            case .lab(let report): report.id
            }
        }

        var date: Date {
            switch self {
            case .vitals(let entry): entry.date
            case .lab(let report): report.date
            }
        }
    }
}

enum HealthLog {

    /// Numbers each day of the record, oldest first.
    ///
    /// Counting from the oldest day is what keeps a number attached to a day:
    /// numbering the list as displayed would renumber everything each time a
    /// reading arrived, so "Log 3" would mean a different day every day.
    static func numbers(for days: [HealthLogDay]) -> [Date: Int] {
        let ordered = days.map(\.date).sorted()
        return Dictionary(uniqueKeysWithValues:
            ordered.enumerated().map { ($0.element, $0.offset + 1) })
    }



    /// Groups the two measurement stores by calendar day, newest day first.
    ///
    /// Days with nothing in them are absent rather than empty: a gap in the
    /// record is a day the reader did not write anything down, and inventing a
    /// row for it would suggest they recorded "nothing wrong".
    static func days(vitals: [VitalsEntry],
                     labs: [LabReport] = [],
                     calendar: Calendar = .current) -> [HealthLogDay] {
        var vitalsByDay: [Date: [VitalsEntry]] = [:]
        for entry in vitals {
            vitalsByDay[calendar.startOfDay(for: entry.date), default: []].append(entry)
        }

        var labsByDay: [Date: [LabReport]] = [:]
        for report in labs {
            labsByDay[calendar.startOfDay(for: report.date), default: []].append(report)
        }

        return Set(vitalsByDay.keys).union(labsByDay.keys)
            .sorted(by: >)
            .map { day in
                HealthLogDay(
                    date: day,
                    vitals: (vitalsByDay[day] ?? []).sorted { $0.date > $1.date },
                    labs: (labsByDay[day] ?? []).sorted { $0.date > $1.date })
            }
    }
}
