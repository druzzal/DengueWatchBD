#if DEBUG
import UIKit

/// Puts the app in a known state for the UI tests, before any store exists.
///
/// UI tests drive the real app, so they meet whatever the last run left
/// behind: yesterday's fluid log, a check from another test, the first-run
/// disclaimer. Launched with `DW_UITEST=1`, the app instead starts empty, in
/// English, past the disclaimer, without animations — and, with
/// `DW_UITEST_SEED`, holding exactly the records a test asks for.
///
/// Compiled out of release builds, like `DW_START_TAB`.
enum UITestSupport {

    static var isActive: Bool {
        ProcessInfo.processInfo.environment["DW_UITEST"] == "1"
    }

    /// Called from the app's initialiser, which runs before the root view
    /// creates the stores, so they load what is written here.
    @MainActor
    static func prepare() {
        guard isActive else { return }
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["case-log.json", "vitals.json", "lab-reports.json", "fluids.json",
                     "log-names.json"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "hasSeenDisclaimer")
        defaults.set(AppLanguage.english.rawValue, forKey: "appLanguage")
        UIView.setAnimationsEnabled(false)

        let seeds = Set((ProcessInfo.processInfo.environment["DW_UITEST_SEED"] ?? "")
            .split(separator: ",").map(String.init))
        if seeds.contains("checks") {
            // Newest first, as the store keeps them: an emergency check an
            // hour ago over a plain fever two days ago.
            let checks = [
                CaseLogEntry(date: Date().addingTimeInterval(-3600),
                             symptomIDs: ["fever", "faint"],
                             outcomeRawValue: TriageOutcome.emergency.rawValue,
                             feverDaysAgo: 2),
                CaseLogEntry(date: Date().addingTimeInterval(-2 * 86_400),
                             symptomIDs: ["fever"],
                             outcomeRawValue: TriageOutcome.testAdvised.rawValue,
                             feverDaysAgo: 0),
            ]
            write(checks, to: directory.appendingPathComponent("case-log.json"))
        }
        if seeds.contains("vitals") {
            write([VitalsEntry(date: Date().addingTimeInterval(-1800), temperature: 38.6,
                               pulse: 96, systolic: 112, diastolic: 74, oxygenSaturation: 98)],
                  to: directory.appendingPathComponent("vitals.json"))
        }
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
#endif
