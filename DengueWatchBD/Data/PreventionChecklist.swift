import Foundation
import Observation

/// The small set of things worth doing today to stop mosquitoes breeding.
///
/// Deliberately short and deliberately unrewarded. A prevention habit that
/// needs streaks and confetti to hold attention is one people abandon; the only
/// feedback here is an honest count of what is done.
enum PreventionTask: String, CaseIterable, Identifiable {
    case standingWater
    case plantTrays
    case containers
    case storedWater
    case protection

    var id: String { rawValue }

    /// Localization key. Text lives in the string tables, never inline.
    var titleKey: String { "checklist.task.\(rawValue)" }

    var symbol: String {
        switch self {
        case .standingWater: "drop.triangle"
        case .plantTrays: "leaf"
        case .containers: "trash"
        case .storedWater: "waterbottle"
        case .protection: "shield.lefthalf.filled"
        }
    }
}

/// Which tasks are done today, on this device.
///
/// Scoped to a calendar day on purpose: the point is that these are daily
/// chores, so yesterday's ticks must not read as today's protection. The stored
/// day is compared rather than a timer being scheduled, so the reset survives
/// the app being closed, the device being asleep, and the clock being changed.
@MainActor
@Observable
final class PreventionChecklist {
    private static let completedKey = "prevention.checklist.completed"
    private static let dayKey = "prevention.checklist.day"

    private let defaults: UserDefaults
    private let calendar: Calendar

    private(set) var completed: Set<PreventionTask> = []

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        completed = Self.load(defaults: defaults, calendar: calendar, now: Date())
    }

    var completedCount: Int { completed.count }
    var total: Int { PreventionTask.allCases.count }
    var isComplete: Bool { completedCount == total }

    /// 0…1, for a progress view. Zero tasks would divide by zero if the enum
    /// were ever emptied, so the denominator is guarded.
    var fraction: Double {
        total > 0 ? Double(completedCount) / Double(total) : 0
    }

    func isDone(_ task: PreventionTask) -> Bool { completed.contains(task) }

    func toggle(_ task: PreventionTask, now: Date = Date()) {
        refreshIfDayChanged(now: now)
        if completed.contains(task) {
            completed.remove(task)
        } else {
            completed.insert(task)
        }
        save(now: now)
    }

    /// Called when the view appears, so a checklist left open overnight does not
    /// keep yesterday's ticks on screen.
    func refreshIfDayChanged(now: Date = Date()) {
        let storedDay = defaults.object(forKey: Self.dayKey) as? Date
        if let storedDay, calendar.isDate(storedDay, inSameDayAs: now) { return }
        completed = []
        defaults.removeObject(forKey: Self.completedKey)
        defaults.removeObject(forKey: Self.dayKey)
    }

    private func save(now: Date) {
        defaults.set(completed.map(\.rawValue), forKey: Self.completedKey)
        defaults.set(calendar.startOfDay(for: now), forKey: Self.dayKey)
    }

    private static func load(defaults: UserDefaults,
                             calendar: Calendar,
                             now: Date) -> Set<PreventionTask> {
        guard let storedDay = defaults.object(forKey: dayKey) as? Date,
              calendar.isDate(storedDay, inSameDayAs: now),
              let raw = defaults.stringArray(forKey: completedKey) else {
            return []
        }
        // Unknown raw values are dropped rather than crashing: a task removed in
        // a later build must not break an older device's stored state.
        return Set(raw.compactMap(PreventionTask.init(rawValue:)))
    }
}
