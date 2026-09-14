import Foundation
import Observation

/// The reader's own lab reports, kept on device.
///
/// Same promise as the case log and vitals: a file in Application Support,
/// nothing leaving the phone. Lab results are the most identifying health data
/// this app holds, and it holds them the only way it safely can — locally,
/// with nowhere to send them.
@MainActor
@Observable
final class LabStore {
    private(set) var reports: [LabReport] = []

    private let fileURL: URL

    init(filename: String = "lab-reports.json") {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent(filename)
        load()
    }

    func add(_ report: LabReport) {
        guard !report.isEmpty else { return }
        reports.insert(report, at: 0)
        reports.sort { $0.date > $1.date }
        save()
    }

    func delete(at offsets: IndexSet) {
        reports.remove(atOffsets: offsets)
        save()
    }

    /// Delete one report by identity. The combined log groups every store by
    /// day, so a row's position there says nothing about its index here.
    func delete(id: UUID) {
        reports.removeAll { $0.id == id }
        save()
    }

    /// Rename one record. Trimmed, and an empty name puts it back to its
    /// number rather than leaving it blank.
    func rename(id: UUID, to name: String) {
        guard let index = reports.firstIndex(where: { $0.id == id }) else { return }
        reports[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func clear() {
        reports.removeAll()
        save()
    }

    var latest: LabReport? { reports.first }

    /// Oldest first, for charting a measure over the course of an illness.
    /// Reports without that measure are skipped rather than plotted as zero.
    func series(for measure: LabMeasure) -> [(date: Date, value: Double)] {
        reports
            .compactMap { report in report.value(for: measure).map { (report.date, $0) } }
            .sorted { $0.date < $1.date }
    }

    func mostRecent(_ measure: LabMeasure) -> (date: Date, value: Double)? {
        series(for: measure).last
    }

    /// The newest report that actually recorded this test, which may be older
    /// than `latest` if the most recent report did not include it.
    func mostRecentResult(_ test: DengueTest) -> (date: Date, result: TestResult)? {
        reports
            .first { $0.result(for: test) != .notDone }
            .map { ($0.date, $0.result(for: test)) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([LabReport].self, from: data) else { return }
        reports = decoded.sorted { $0.date > $1.date }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(reports) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
