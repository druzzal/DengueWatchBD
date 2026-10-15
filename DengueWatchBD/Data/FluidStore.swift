import Foundation
import Observation

/// The reader's fluid log, kept on device.
///
/// Same shape and same promise as VitalsStore: a file in Application Support,
/// nothing leaving the phone, no account.
@MainActor
@Observable
final class FluidStore {
    private(set) var entries: [FluidEntry] = []

    private let fileURL: URL

    init(filename: String = "fluids.json") {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent(filename)
        load()
    }

    /// Newest first, matching the other stores.
    func add(_ entry: FluidEntry) {
        // A drink with no amount, or an impossible one, is not a record.
        if entry.kind == .drink {
            guard let millilitres = entry.millilitres,
                  FluidLog.plausibleMillilitres.contains(millilitres) else { return }
        }
        entries.insert(entry, at: 0)
        entries.sort { $0.date > $1.date }
        save()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    func day(_ date: Date) -> FluidDay {
        FluidLog.day(date, entries: entries)
    }

    /// One day's entries, oldest first, the way a day is read.
    func entries(on date: Date, calendar: Calendar = .current) -> [FluidEntry] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: date) }.reversed()
    }

    /// Sorted here rather than trusted from the file, as in CaseLogStore.
    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([FluidEntry].self, from: data) else { return }
        entries = decoded.sorted { $0.date > $1.date }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
