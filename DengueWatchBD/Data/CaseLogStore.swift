import Foundation
import Observation

struct CaseLogEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var temperature: Double?
    var symptomIDs: [String] = []
    var outcomeRawValue: Int = TriageOutcome.selfCare.rawValue
    var areaCode: String?
    var note: String = ""
    /// What the reader calls this record. Empty means it is shown by its
    /// number instead — see `HealthLog.numbers`.
    var name: String = ""

    /// Days since the fever began, zero-based, as the checker records it.
    /// Nil when there was no fever to date from.
    ///
    /// Persisted so the fever timeline and the WHO plan survive the check that
    /// produced them — without it, the day of illness is known for one screen
    /// and then forgotten, which is the one number dengue care turns on.
    /// Optional, so entries written before this existed still decode.
    var feverDaysAgo: Int?

    /// The co-existing conditions WHO singles out, as ticked at the time.
    /// They decide the WHO management group, so the plan cannot be rebuilt
    /// without them.
    var isPregnant = false
    var isUnderFiveOrOverSixty = false
    var hasChronicCondition = false
    var hadDengueBefore = false

    var triageContext: TriageEngine.Context {
        TriageEngine.Context(feverDaysAgo: feverDaysAgo,
                             isPregnant: isPregnant,
                             isUnderFiveOrOverSixty: isUnderFiveOrOverSixty,
                             hasChronicCondition: hasChronicCondition,
                             hadDengueBefore: hadDengueBefore)
    }

    /// The day the fever began, for the timeline.
    var feverStarted: Date? {
        feverDaysAgo.flatMap {
            Calendar.current.date(byAdding: .day, value: -$0,
                                  to: Calendar.current.startOfDay(for: date))
        }
    }

    var outcome: TriageOutcome { TriageOutcome(rawValue: outcomeRawValue) ?? .selfCare }
}

/// The user's own check-ins, kept on device in Application Support.
/// Nothing here leaves the phone.
@MainActor
@Observable
final class CaseLogStore {
    private(set) var entries: [CaseLogEntry] = []

    private let fileURL: URL

    init(filename: String = "case-log.json") {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent(filename)
        load()
    }

    func add(_ entry: CaseLogEntry) {
        entries.insert(entry, at: 0)
        save()
    }

    func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    /// Delete one entry by identity. The combined log groups both stores by
    /// day, so a row's position there says nothing about its index here.
    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// Rename one record. Trimmed, and an empty name puts it back to its
    /// number rather than leaving it blank.
    func rename(id: UUID, to name: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }


    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        entries = (try? JSONDecoder().decode([CaseLogEntry].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
