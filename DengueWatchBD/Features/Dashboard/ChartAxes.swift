import Charts
import SwiftUI

// MARK: - Shared axes
//
// Free functions rather than `AxisContent` types: axis builders are nonisolated,
// so they take the `Sendable` `NumberStyle` instead of the localization object.

/// Y axis in compact, language-aware counts.
@AxisContentBuilder
func countAxis(_ style: NumberStyle) -> some AxisContent {
    AxisMarks(position: .leading) { value in
        AxisGridLine().foregroundStyle(Palette.grid)
        AxisValueLabel {
            if let count = value.as(Int.self) {
                Text(style.compact(count))
                    .typoStatic(.micro)
                    .foregroundStyle(Palette.mutedInk)
            }
        }
    }
}

/// X axis of dates. Collision resolution is off because it truncates the
/// right-most label ("Sep 1" → "Se…") rather than laying it out.
@AxisContentBuilder
func dateAxis(_ style: NumberStyle, desiredCount: Int = 4) -> some AxisContent {
    AxisMarks(values: .automatic(desiredCount: desiredCount)) { value in
        AxisValueLabel(collisionResolution: .disabled) {
            if let date = value.as(Date.self) {
                Text(style.dayMonth(date))
                    .typoStatic(.micro)
                    .foregroundStyle(Palette.mutedInk)
            }
        }
    }
}

/// X axis for the weekly area charts.
///
/// A season runs to 52 categories, so every label would collide. Showing every
/// fourth keeps roughly monthly gridposts, which is what a reader scans for.
func weekAxis(every stride: Int = 4) -> some AxisContent {
    AxisMarks { value in
        if let week = value.as(String.self),
           let number = Int(week.dropFirst()),
           number % stride == 0 {
            AxisValueLabel {
                Text(week)
                    .typoStatic(.micro)
                    .foregroundStyle(Palette.mutedInk)
            }
        }
    }
}
