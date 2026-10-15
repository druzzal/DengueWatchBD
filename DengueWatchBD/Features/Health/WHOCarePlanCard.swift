import SwiftUI

/// Where WHO's guidance puts the reader's own record, what WHO advises
/// for it, and — always — what produced it.
///
/// The reasons are not decoration. A plan that says "go to hospital" without
/// saying why reads as an oracle, and an oracle is exactly what a health app
/// must not be. Every line here names a box the reader ticked or a number they
/// wrote down.
struct WHOCarePlanCard: View {
    @Environment(LocalizationManager.self) private var loc

    let plan: WHOCarePlan
    /// When the check behind this plan was run.
    let checkedAt: Date
    /// False once the check is old enough that it describes a past day.
    let isCurrent: Bool
    /// Lab measures well outside their range, named for the doctor rather
    /// than folded into the group.
    let notableLabs: String?
    /// The haematocrit has risen on each of the last two reports. Named for
    /// the doctor, like `notableLabs`, and never folded into the group.
    var haematocritRising = false
    var onRecheck: () -> Void

    private var risk: RiskLevel { plan.group.risk }

    var body: some View {
        CardSection(loc.t("who.plan.title"),
                    subtitle: loc.t("who.plan.checkedAt", loc.dayAndTime(checkedAt))) {
            VStack(alignment: .leading, spacing: Space.row) {
                if !isCurrent {
                    // Shown rather than hidden — it is the reader's own record
                    // — but never presented as advice for today.
                    InlineNote(symbol: "clock.arrow.circlepath",
                               detail: loc.t("who.plan.stale"),
                               tint: Palette.riskInk(.moderate))
                }
                header
                advice
                if !plan.reasons.isEmpty && plan.reasons != [.noneOfThese] {
                    reasons
                }
                if haematocritRising {
                    InlineNote(symbol: "chart.line.uptrend.xyaxis",
                               detail: loc.t("care.plan.haematocritRising"),
                               tint: Palette.riskInk(.high))
                }
                if let notableLabs {
                    InlineNote(symbol: "drop.triangle",
                               detail: loc.t("care.plan.readings", notableLabs),
                               tint: Palette.riskInk(.high))
                }
                if notableLabs != nil || haematocritRising {
                    // Only where a lab value is on the card: this is the one
                    // place a reader could reasonably assume their blood count
                    // moved the group. It did not.
                    InlineNote(symbol: "info.circle", detail: loc.t("care.plan.note"))
                }
                if !plan.measuredReasons.isEmpty {
                    // A home cuff is not a clinician's hands, and the plan
                    // should say so where it leans on one.
                    InlineNote(symbol: "exclamationmark.triangle.fill",
                               detail: loc.t("who.plan.measuredNote"),
                               tint: Palette.riskInk(.high))
                }
                SecondaryActionButton(title: loc.t("care.plan.recheck"),
                                      systemImage: "stethoscope", action: onRecheck)
                InlineNote(symbol: "info.circle", detail: loc.t("who.plan.source"))
            }
        }
    }

    /// The level, drawn and named. The A / B / C letters went with WHO's 2009
    /// groups: the 2025 guideline has no letters, and printing one would send
    /// a clinician looking for a classification that no longer exists.
    private var header: some View {
        HStack(alignment: .top, spacing: Space.row) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.riskSoft(risk))
                Image(systemName: plan.group.symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.riskInk(risk))
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(loc.t(plan.group.titleKey))
                    .typo(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.riskInk(risk))
                    .fixedSize(horizontal: false, vertical: true)
                Text(loc.t(plan.group.detailKey))
                    .typo(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var advice: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            ForEach(plan.group.adviceKeys, id: \.self) { key in
                HStack(alignment: .top, spacing: Space.tight) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.accent)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    Text(loc.t(key))
                        .typo(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var reasons: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(loc.t("who.plan.becauseTitle"))
                .typo(.micro)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(plan.reasons) { reason in
                HStack(alignment: .top, spacing: Space.tight) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    Text(loc.t(reason.labelKey))
                        .typo(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Space.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.plane,
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
