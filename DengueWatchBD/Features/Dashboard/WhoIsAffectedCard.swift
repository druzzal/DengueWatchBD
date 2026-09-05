import SwiftUI

/// Who is catching dengue this season — age bands, split by sex.
///
/// This breakdown is new: the previous data pipeline never carried it. It
/// matters clinically because dengue's risk profile is not flat across ages,
/// and because a reader deciding how worried to be about a child or an older
/// relative is asking exactly this question.
///
/// Drawn as a paired bar per band rather than a population pyramid. A pyramid
/// reads well at a glance but needs a signed axis, and at phone width the
/// negative half is routinely misread as a decline.
struct WhoIsAffectedCard: View {
    @Environment(LocalizationManager.self) private var loc

    let bands: [AgeBand]
    let split: SexSplit?

    private var peak: Int { max(bands.map(\.total).max() ?? 1, 1) }

    var body: some View {
        CardSection(loc.t("who.title"), subtitle: loc.t("who.subtitle")) {
            if let split {
                HStack(spacing: Space.tight) {
                    sexShare(label: loc.t("who.male"),
                             value: split.male,
                             share: split.maleShare,
                             color: Palette.cases)
                    sexShare(label: loc.t("who.female"),
                             value: split.female,
                             share: 1 - split.maleShare,
                             color: Palette.deaths)
                }
                .padding(.bottom, 2)
            }

            ChartLegend(items: [
                .init(label: loc.t("who.male"), color: Palette.cases),
                .init(label: loc.t("who.female"), color: Palette.deaths)
            ])

            VStack(spacing: 5) {
                ForEach(bands) { band in
                    row(band)
                }
            }
        }
    }

    private func row(_ band: AgeBand) -> some View {
        HStack(spacing: Space.tight) {
            Text(band.label)
                .typo(.micro)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            GeometryReader { geometry in
                let unit = geometry.size.width / CGFloat(peak)
                HStack(spacing: 1) {
                    Capsule().fill(Palette.cases)
                        .frame(width: max(1, CGFloat(band.male) * unit))
                    Capsule().fill(Palette.deaths)
                        .frame(width: max(1, CGFloat(band.female) * unit))
                    Spacer(minLength: 0)
                }
                .frame(height: geometry.size.height, alignment: .center)
            }
            .frame(height: 13)

            Text(loc.compact(band.total))
                .typo(.micro)
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(loc.t("who.a11y", band.label,
                                  loc.num(band.male), loc.num(band.female)))
    }

    private func sexShare(label: String, value: Int, share: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).typo(.micro).foregroundStyle(.secondary)
            Text(loc.t("who.share", loc.decimal(share * 100, places: 0)))
                .typo(.statValue).foregroundStyle(color)
            Text(loc.compact(value)).typo(.micro).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
