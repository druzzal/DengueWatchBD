import Foundation
import Observation

/// The names a reader gives to days of their record.
///
/// Kept apart from the three entry stores because a name belongs to the day,
/// not to any one reading in it — a day holds a temperature, a blood pressure
/// and a blood count, and "the day I went to the clinic" names all of them at
/// once. Keyed by the start of the day so it survives whatever time the
/// readings were taken at.
@MainActor
@Observable
final class LogNameStore {
    private(set) var names: [Date: String] = [:]

    private let fileURL: URL

    init(filename: String = "log-names.json") {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent(filename)
        load()
    }

    func name(for day: Date) -> String? {
        let key = Calendar.current.startOfDay(for: day)
        guard let name = names[key], !name.isEmpty else { return nil }
        return name
    }

    /// An empty name removes it, putting the day back to its number rather
    /// than leaving it blank.
    func rename(day: Date, to name: String) {
        let key = Calendar.current.startOfDay(for: day)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { names.removeValue(forKey: key) } else { names[key] = trimmed }
        save()
    }

    /// Called when a day's records are all deleted, so a name does not outlive
    /// the day it belonged to.
    func forget(day: Date) {
        names.removeValue(forKey: Calendar.current.startOfDay(for: day))
        save()
    }

    func clear() {
        names.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([Date: String].self, from: data)
        else { return }
        names = stored
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(names) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
