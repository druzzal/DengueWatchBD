import Foundation
import Observation

struct CaseLogEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var temperature: Double?
    var symptomIDs: [String] = []
    var outcomeRawValue: Int = TriageOutcome.selfCare.rawValue
    var districtCode: String?
    var note: String = ""

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

    func clear() {
        entries.removeAll()
        save()
    }

    /// The most severe outcome logged in the last week, for the dashboard banner.
    var recentWorstOutcome: TriageOutcome? {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        return entries.filter { $0.date >= cutoff }.map(\.outcome).max()
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
