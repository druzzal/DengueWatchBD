import SwiftUI

/// Explains what location is for *before* iOS shows its own prompt, and always
/// offers a way to carry on without it.
///
/// A permission dialog with no context is the most common reason people deny
/// location to a health app, and DengueWatch stays useful either way — the
/// area picker covers everything except "risk exactly where I'm standing".
struct LocationPermissionCard: View {
    @Environment(LocalizationManager.self) private var loc
    @Environment(LocationManager.self) private var location

    var onChooseManually: (() -> Void)?

    private var isDenied: Bool {
        location.authorization == .denied || location.authorization == .restricted
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.row) {
                HStack(spacing: Space.row) {
                    Image(systemName: isDenied ? "location.slash.fill" : "location.fill")
                        .font(.title3)
                        .foregroundStyle(Palette.accent)
                        .frame(width: 40, height: 40)
                        .background(Palette.accent.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.t(isDenied ? "location.denied.title" : "location.why.title"))
                            .typo(.headline)
                        Text(loc.t(isDenied ? "location.denied.message" : "location.why.message"))
                            .typo(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if isDenied {
                    if let onChooseManually {
                        SecondaryActionButton(title: loc.t("location.why.manual"),
                                              systemImage: "list.bullet") {
                            onChooseManually()
                        }
                    }
                } else {
                    VStack(spacing: Space.tight) {
                        PrimaryActionButton(title: loc.t("location.why.allow"),
                                            systemImage: "location.fill") {
                            location.requestWhenInUse()
                            location.startUpdatingCoarse()
                        }
                        if let onChooseManually {
                            Button(loc.t("location.why.manual"), action: onChooseManually)
                                .typo(.caption)
                                .foregroundStyle(Palette.accent)
                                .frame(minHeight: Hit.minimum - 10)
                        }
                    }
                }
            }
        }
    }
}
