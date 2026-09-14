import Foundation
import Observation

/// The reader's own vital-sign readings, kept on device.
///
/// Same shape and same promise as CaseLogStore: a file in Application Support,
/// nothing leaving the phone, no account. Health readings are the most private
/// thing this app holds, and the architecture that keeps them private is the
/// absence of anywhere to send them.
@MainActor
@Observable
final class VitalsStore {
    private(set) var entries: [VitalsEntry] = []

    private let fileURL: URL

    init(filename: String = "vitals.json") {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent(filename)
        load()
    }

    /// Newest first, matching the case log.
    func add(_ entry: VitalsEntry) {
        guard !entry.isEmpty else { return }   // an entry with no readings is not a record
        entries.insert(entry, at: 0)
        entries.sort { $0.date > $1.date }
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


    func clear() {
        entries.removeAll()
        save()
    }

    var latest: VitalsEntry? { entries.first }

    /// Readings for one measure, oldest first, for charting.
    ///
    /// Entries with that measure missing are skipped rather than plotted as
    /// zero — a blank blood-pressure day is not a blood pressure of nothing.
    func series(for kind: VitalKind) -> [(date: Date, value: Double)] {
        entries
            .compactMap { entry in entry.value(for: kind).map { (entry.date, $0) } }
            .sorted { $0.date < $1.date }
    }

    /// The most recent reading of one measure, which may be older than `latest`
    /// if that entry did not include it.
    func mostRecent(_ kind: VitalKind) -> (date: Date, value: Double)? {
        series(for: kind).last
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([VitalsEntry].self, from: data) else { return }
        entries = decoded.sorted { $0.date > $1.date }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
