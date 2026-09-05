import SwiftUI

/// The one thing the screen exists to answer: what is the dengue risk where I
/// am, and is it getting worse?
///
/// The card is tinted by band rather than flooded with it — a severe reading
/// should be unmistakable without turning the phone into a red rectangle.
struct DengueRiskCard: View {
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    let risk: RiskLevel
    let areaName: String
    /// Week-on-week change in reported cases, if known.
    let change: Double?
    let lastUpdated: Date?
    /// 14-day cases per 100,000 — spoken, since the meter is decorative.
    var incidence: Double?
    var isNationwide = false
    var onTap: () -> Void

    @State private var pulsing = false

    private var trendKey: String {
        guard let change else { return "risk.trend.steady" }
        if change >= 0.05 { return "risk.trend.rising" }
        if change <= -0.05 { return "risk.trend.falling" }
        return "risk.trend.steady"
    }

    private var trendSymbol: String {
        guard let change else { return "arrow.right" }
        if change >= 0.05 { return "arrow.up.right" }
        if change <= -0.05 { return "arrow.down.right" }
        return "arrow.right"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Space.row) {
                header
                riskWord
                RiskMeter(risk: risk, height: 7)
                // Capped at large text sizes: unbounded, the advice pushed the
                // trend and the timestamp off-screen entirely. The full wording
                // is one tap away in the detail sheet, which the chevron and
                // the accessibility hint both advertise.
                Text(loc.t(risk.guidanceKey))
                    .typo(.callout)
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : nil)
                    .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize ? false : true)
                footer
            }
            .padding(Space.card + 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                    .fill(Palette.card)
                    .overlay(
                        // A flat wash made the hero card the dullest thing on
                        // the screen. The gradient is shallow on purpose: it
                        // gives the card a light source without shifting the
                        // band's colour enough to be mistaken for a second one.
                        RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                            .fill(LinearGradient(
                                colors: [risk.soft, risk.soft.opacity(0.45)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                    .strokeBorder(risk.tint.opacity(0.35), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
        }
        .pressable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(loc.t("risk.card.hint"))
        .accessibilityAddTraits(.isButton)
    }

    private var header: some View {
        HStack(spacing: Space.tight) {
            // A slow live pulse, not a blinking alarm.
            ZStack {
                Circle()
                    .fill(risk.tint.opacity(0.35))
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulsing ? 1.5 : 0.9)
                    .opacity(pulsing ? 0 : 0.9)
                Circle()
                    .fill(risk.tint)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 16, height: 16)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Motion.pulse) { pulsing = true }
            }
            .accessibilityHidden(true)

            Text(loc.t("risk.card.title"))
                .typo(.micro)
                .fontWeight(.semibold)
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var riskWord: some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            HStack(alignment: .firstTextBaseline, spacing: Space.tight + 2) {
                Text(loc.t(risk.labelKey))
                    .typo(.hero)
                    .foregroundStyle(risk.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Image(systemName: risk.symbolName)
                    .font(.title3)
                    .foregroundStyle(risk.ink)
                    .accessibilityHidden(true)
            }

            Text(areaName)
                .typo(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var footer: some View {
        let trend = HStack(spacing: 4) {
            Image(systemName: trendSymbol).font(.system(size: 11, weight: .bold))
            Text(loc.t(trendKey)).typo(.caption).fontWeight(.semibold)
        }
        .foregroundStyle(risk.ink)
        .fixedSize(horizontal: false, vertical: true)

        let updated = Group {
            if let lastUpdated {
                Text(loc.t("risk.card.updated", loc.relative(lastUpdated)))
                    .typo(.micro)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Space.hair) {
                    trend
                    updated
                }
            } else {
                HStack(spacing: Space.tight) {
                    trend
                    if lastUpdated != nil {
                        Text("·").foregroundStyle(.tertiary)
                    }
                    updated
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilitySummary: String {
        var parts = [
            loc.t("risk.card.title"),
            loc.t(risk.labelKey),
            areaName,
        ]
        if let incidence {
            parts.append(loc.t("risk.a11y.rate", loc.decimal(incidence)))
        }
        parts.append(loc.t(trendKey))
        parts.append(loc.t(risk.guidanceKey))
        if let lastUpdated {
            parts.append(loc.t("risk.card.updated", loc.relative(lastUpdated)))
        }
        return parts.joined(separator: ", ")
    }
}

/// Tapping the risk card explains how the band was derived — the thresholds,
/// the window, and what the reading means for the user.
struct RiskDetailSheet: View {
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.dismiss) private var dismiss

    let risk: RiskLevel
    let areaName: String
    let incidence: Double
    let last14Cases: Int
    let lastUpdated: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.stack) {
                    VStack(alignment: .leading, spacing: Space.row) {
                        RiskBadge(risk: risk)
                        Text(loc.t(risk.guidanceKey))
                            .typo(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Space.card)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(risk.soft, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                    CardSection(loc.t("risk.detail.how")) {
                        VStack(alignment: .leading, spacing: Space.row) {
                            LabeledFigure(label: loc.t("risk.detail.window"),
                                          value: loc.num(last14Cases))
                            Divider().overlay(Palette.hairline)
                            LabeledFigure(label: loc.t("common.per100k"),
                                          value: loc.decimal(incidence))
                            Divider().overlay(Palette.hairline)
                            LabeledFigure(label: loc.t("about.lastUpdated"),
                                          value: lastUpdated.map { loc.fullDate($0) } ?? "—")
                        }
                        Text(loc.t("map.list.footer"))
                            .typo(.micro)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    CardSection(loc.t("risk.detail.bands")) {
                        VStack(spacing: Space.row) {
                            ForEach(RiskLevel.allCases) { level in
                                HStack(spacing: Space.row) {
                                    RiskBadge(risk: level, compact: true)
                                    Text(loc.t("risk.detail.band.\(level.rawValue)"))
                                        .typo(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 0)
                                    if level == risk {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(risk.ink)
                                    }
                                }
                            }
                        }
                    }

                    SourceBadge(kind: .official, detail: "DGHS")
                }
                .padding(.horizontal, Space.screen)
                .padding(.vertical, Space.card)
            }
            .background(Palette.plane)
            .navigationTitle(areaName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.t("common.done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// A label and its figure on one row.
struct LabeledFigure: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).typo(.callout).foregroundStyle(.secondary)
            Spacer(minLength: Space.tight)
            Text(value).typo(.callout).fontWeight(.semibold).tabularFigures()
        }
        .accessibilityElement(children: .combine)
    }
}
