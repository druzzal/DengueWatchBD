import SwiftUI

/// Explains what location is for *before* iOS shows its own prompt.
///
/// The system dialog is a one-shot: if someone declines it because they did not
/// understand the ask, the app cannot ask again. So the reason comes first, in
/// plain language, with an obvious way to decline that does not burn the
/// system prompt.
struct LocationPermissionSheet: View {
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.dismiss) private var dismiss

    /// Called when the user agrees; the caller then makes the system request.
    let onAllow: () -> Void

    var body: some View {
        VStack(spacing: Space.stack) {
            Spacer(minLength: Space.card)

            Image(systemName: "location.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)

            VStack(spacing: Space.tight) {
                Text(loc.t("locperm.title"))
                    .typo(.title)
                    .multilineTextAlignment(.center)
                Text(loc.t("locperm.body"))
                    .typo(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Space.row) {
                reason("map", "locperm.reason1")
                reason("cross.case", "locperm.reason2")
                reason("lock.shield", "locperm.reason3")
            }
            .padding(.top, Space.hair)

            Spacer(minLength: Space.card)

            VStack(spacing: Space.tight) {
                PrimaryActionButton(title: loc.t("locperm.allow"),
                                    systemImage: "location.fill") {
                    dismiss()
                    onAllow()
                }
                Button(loc.t("locperm.notNow")) { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: Hit.minimum)
            }
        }
        .padding(.horizontal, Space.screen)
        .padding(.bottom, Space.card)
        .presentationDetents([.height(520), .large])
        .presentationDragIndicator(.visible)
    }

    private func reason(_ symbol: String, _ key: String) -> some View {
        HStack(alignment: .top, spacing: Space.row) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(Palette.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(loc.t(key))
                .typo(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
