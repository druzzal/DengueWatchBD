import Observation
import SwiftUI

/// Lets a card on one screen send the user to another tab — the map preview
/// opening the full map, an alert opening the area list.
@MainActor
@Observable
final class AppRouter {
    enum Tab: String, CaseIterable {
        case home, map, health, care, prevent

        var titleKey: String { "tab.\(rawValue)" }

        var symbol: String {
            switch self {
            case .home: "chart.line.uptrend.xyaxis"
            case .map: "map"
            case .health: "heart.text.square"
            case .care: "cross.case"
            case .prevent: "shield.lefthalf.filled"
            }
        }

    }

    /// Something a card on one tab asks the destination tab to open.
    ///
    /// A request rather than a binding, because the sender has no business
    /// owning the receiver's sheet — Home knows the reader wants to run a
    /// symptom check, and My Health knows how to present one.
    enum Request: Equatable {
        case symptomCheck
    }

    var selectedTab: Tab = .home

    /// Cleared by whoever acts on it. Left set, it would reopen the sheet every
    /// time the reader came back to the tab.
    private(set) var pending: Request?

    func show(_ tab: Tab, requesting request: Request? = nil) {
        pending = request
        withAnimation(Motion.interactive) { selectedTab = tab }
    }

    /// True once, for the tab that can honour it.
    func claim(_ request: Request) -> Bool {
        guard pending == request else { return false }
        pending = nil
        return true
    }
}
