import SwiftUI

// MARK: - Skeletons

/// A slow diagonal sheen. Used only while real content is on its way, never
/// as decoration.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.28), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(width: geometry.size.width * 1.6)
                    .offset(x: phase * geometry.size.width * 1.6)
                }
                .allowsHitTesting(false)
                .task {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1.2
                    }
                }
            }
        }
        .clipped()
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

/// A neutral block standing in for text or a figure that has not loaded.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat = 12
    var radius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Palette.mutedInk.opacity(0.16))
            .frame(width: width, height: height)
    }
}

/// Placeholder for the hero risk card.
struct RiskCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            SkeletonBlock(width: 96, height: 11)
            SkeletonBlock(width: 168, height: 34, radius: 9)
            SkeletonBlock(width: 132, height: 11)
            SkeletonBlock(height: 6, radius: 3)
        }
        .padding(Space.card + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.hero)
        .shimmering()
        .accessibilityLabel(Text(verbatim: "Loading"))
    }
}

/// Placeholder grid for the activity metrics.
struct StatGridSkeleton: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.row),
                            GridItem(.flexible(), spacing: Space.row)],
                  spacing: Space.row) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Space.tight) {
                    SkeletonBlock(width: 74, height: 26, radius: 7)
                    SkeletonBlock(width: 92, height: 10)
                    SkeletonBlock(height: 22, radius: 5)
                }
                .padding(Space.card)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        }
        .shimmering()
        .accessibilityHidden(true)
    }
}

/// Placeholder for a chart card.
struct ChartSkeleton: View {
    var height: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            SkeletonBlock(width: 128, height: 13)
            SkeletonBlock(height: height, radius: 10)
        }
        .padding(Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .shimmering()
        .accessibilityHidden(true)
    }
}

/// Placeholder rows for lists.
struct RowsSkeleton: View {
    var count = 4

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: Space.row) {
                    SkeletonBlock(width: 34, height: 34, radius: 10)
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock(width: 150, height: 11)
                        SkeletonBlock(width: 92, height: 9)
                    }
                    Spacer()
                }
                .padding(.vertical, Space.row)
                if index < count - 1 { Divider().overlay(Palette.hairline) }
            }
        }
        .padding(.horizontal, Space.card)
        .cardSurface()
        .shimmering()
        .accessibilityHidden(true)
    }
}

// MARK: - Empty and error

/// A designed empty state: icon, explanation, and something to do about it.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Space.row) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.mutedInk)
                .padding(Space.card)
                .background(Palette.mutedInk.opacity(0.10), in: Circle())

            VStack(spacing: Space.hair + 2) {
                Text(title)
                    .typo(.headline)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .typo(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.section)
        .padding(.horizontal, Space.card)
        .accessibilityElement(children: .combine)
    }
}

/// A friendly failure. The underlying error is never shown to the user; it is
/// logged for us and summarised for them.
struct ErrorStateView: View {
    @Environment(LocalizationManager.self) private var loc
    var title: String
    var message: String?
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: Space.row) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Palette.mutedInk)
                .padding(Space.card)
                .background(Palette.mutedInk.opacity(0.10), in: Circle())

            Text(title)
                .typo(.headline)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .typo(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let retry {
                Button(loc.t("common.tryAgain"), action: retry)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.section)
        .padding(.horizontal, Space.card)
        .accessibilityElement(children: .combine)
    }
}
