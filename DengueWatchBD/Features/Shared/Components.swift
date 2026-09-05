import SwiftUI
import Charts

// MARK: - Structure

/// A section heading with optional subtitle and trailing control.
/// Sections are separated by whitespace and a heading, not by nesting
/// everything in another card.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.tight) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).typo(.sectionTitle)
                if let subtitle {
                    Text(subtitle)
                        .typo(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Space.tight)
            trailing
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A titled card for chart and list content.
struct Card<Content: View>: View {
    var padding: CGFloat = Space.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }
}

struct CardSection<Content: View>: View {
    var title: String
    var subtitle: String?
    var accessory: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String, subtitle: String? = nil, accessory: AnyView? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.row) {
                HStack(alignment: .firstTextBaseline, spacing: Space.tight) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).typo(.headline)
                        if let subtitle {
                            Text(subtitle)
                                .typo(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: Space.hair)
                    accessory
                }
                content
            }
        }
    }
}

// MARK: - Risk

/// Risk as colour + icon + word. Never colour alone.
struct RiskBadge: View {
    @Environment(LocalizationManager.self) private var loc
    let risk: RiskLevel
    var compact = false

    var body: some View {
        HStack(spacing: Space.hair) {
            Image(systemName: risk.symbolName)
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
            Text(loc.t(risk.labelKey))
                .typo(compact ? .micro : .caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(risk.ink)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 6)
        .background(risk.soft, in: Capsule())
        .overlay(Capsule().strokeBorder(risk.tint.opacity(0.25), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loc.t("risk.a11y", loc.t(risk.labelKey)))
    }
}

/// Four segments, filled to the current band — a second, non-colour channel
/// for how severe things are.
struct RiskMeter: View {
    let risk: RiskLevel
    var height: CGFloat = 6

    /// Filled segments step up in strength toward the current band, so the
    /// meter reads as a scale rather than a solid bar. At Severe every segment
    /// is lit, and a single flat colour left it looking like one long block
    /// with no sense of how far up the scale it sat. One hue, light to dark —
    /// the band's own colour still carries the meaning.
    private func opacity(for level: RiskLevel) -> Double {
        guard level.rawValue <= risk.rawValue else { return 0 }
        let distance = risk.rawValue - level.rawValue
        return max(0.4, 1 - Double(distance) * 0.2)
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(RiskLevel.allCases) { level in
                Capsule()
                    .fill(Palette.hairline)
                    .overlay(Capsule().fill(risk.tint.opacity(opacity(for: level))))
                    .frame(height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Marks where a number came from. Official surveillance and educational
/// guidance must never look like the same class of information.
struct SourceBadge: View {
    enum Kind {
        case official
        case guidance

        var symbol: String {
            switch self {
            case .official: "checkmark.seal.fill"
            case .guidance: "book.closed.fill"
            }
        }

        var labelKey: String {
            switch self {
            case .official: "source.official"
            case .guidance: "source.guidance"
            }
        }
    }

    @Environment(LocalizationManager.self) private var loc
    let kind: Kind
    var detail: String?

    var body: some View {
        HStack(spacing: Space.hair) {
            Image(systemName: kind.symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(loc.t(kind.labelKey))
                .typo(.micro)
                .fontWeight(.semibold)
            if let detail {
                Text("· \(detail)")
                    .typo(.micro)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Palette.mutedInk.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Numbers

/// Week-on-week movement. Rising case counts are bad news, so the arrow and
/// wording say so rather than leaving colour to imply it.
struct TrendIndicator: View {
    @Environment(LocalizationManager.self) private var loc
    let change: Double?
    var inverted = false

    private var isRise: Bool { (change ?? 0) >= 0 }

    private var tint: Color {
        guard let change, abs(change) >= 0.005 else { return .secondary }
        return (inverted ? !isRise : isRise) ? Palette.upIsBad : Palette.downIsGood
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: isRise ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 11, weight: .bold))
            Text(loc.percentChange(change))
                .typo(.caption)
                .fontWeight(.semibold)
                .tabularFigures()
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loc.t("dash.delta.a11y", loc.percentChange(change)))
    }
}

/// One metric: a large figure, a quiet label, an optional trend and sparkline.
struct StatCard: View {
    let label: String
    let value: String
    var unit: String?
    var change: Double?
    var caption: String?
    var accent: Color = Palette.cases
    var series: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .typo(.statValue)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let unit {
                    Text(unit).typo(.statUnit).foregroundStyle(.secondary)
                }
            }

            Text(label)
                .typo(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !series.isEmpty {
                Sparkline(values: series, color: accent)
                    .frame(height: 26)
            }

            if change != nil || caption != nil {
                HStack(spacing: Space.hair + 2) {
                    if change != nil { TrendIndicator(change: change) }
                    if let caption {
                        Text(caption)
                            .typo(.micro)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.card)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .cardSurface(radius: Radius.card)
        .accessibilityElement(children: .combine)
    }
}

/// Trend shape only — no axes, no labels, one hue.
struct Sparkline: View {
    let values: [Double]
    var color: Color = Palette.cases

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { index, value in
            AreaMark(x: .value("i", index), y: .value("v", value))
                .foregroundStyle(LinearGradient(
                    colors: [color.opacity(0.22), color.opacity(0.01)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("i", index), y: .value("v", value))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityHidden(true)
    }
}

/// A legend is present whenever a plot carries two or more series.
struct ChartLegend: View {
    struct Item: Identifiable {
        let id = UUID()
        let label: String
        let color: Color
        var isLine = false
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: Space.row) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    if item.isLine {
                        Capsule().fill(item.color).frame(width: 14, height: 2.5)
                    } else {
                        RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 9, height: 9)
                    }
                    Text(item.label).typo(.micro).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Ordinal scale legend for the risk bands.
///
/// Band names differ a lot in width between English and Bengali, and at larger
/// Dynamic Type sizes four of them will not fit on one line. Rather than
/// truncating a band name — which would leave "Modera…" standing for a risk
/// level — the legend falls back to two rows.
struct RiskScaleLegend: View {
    @Environment(LocalizationManager.self) private var loc

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.tight) { swatches }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: Space.hair + 2) { swatches }
        }
    }

    private var swatches: some View {
        ForEach(RiskLevel.allCases) { level in
            HStack(spacing: Space.hair) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(level.tint)
                    .frame(width: 11, height: 8)
                Text(loc.t(level.labelKey))
                    .typo(.micro)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}
