import Observation
import SwiftUI

/// Lets a card on one screen send the user to another tab — the map preview
/// opening the full map, an alert opening the area list.
@MainActor
@Observable
final class AppRouter {
    enum Tab: String, CaseIterable {
        case home, map, check, care, prevent

        var titleKey: String { "tab.\(rawValue)" }

        var symbol: String {
            switch self {
            case .home: "chart.line.uptrend.xyaxis"
            case .map: "map"
            case .check: "stethoscope"
            case .care: "cross.case"
            case .prevent: "shield.lefthalf.filled"
            }
        }

        var selectedSymbol: String {
            switch self {
            case .home: "chart.line.uptrend.xyaxis"
            case .map: "map.fill"
            case .check: "stethoscope"
            case .care: "cross.case.fill"
            case .prevent: "shield.lefthalf.filled"
            }
        }
    }

    var selectedTab: Tab = .home

    func show(_ tab: Tab) {
        withAnimation(Motion.interactive) { selectedTab = tab }
    }
}
