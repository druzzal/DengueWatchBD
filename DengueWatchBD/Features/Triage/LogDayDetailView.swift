import SwiftUI

/// One day of the record, in full.
///
/// Everything written down that day, oldest moment first, so it reads as the
/// day happened rather than as a stack with the newest on top. This is the
/// screen a reader holds up to a doctor, so nothing is abbreviated.
struct LogDayDetailView: View {
    @Environment(LocalizationManager.self) private var loc
    @Environment(Preferences.self) private var preferences
    let day: HealthLogDay
    let title: String
    /// "Day N" in the whole log, and the name the reader gave the day, so the
    /// day's own PDF says what the list says.
    var number: Int?
    var name: String?

    @State private var isExporting = false

    /// Oldest first here, deliberately: a day is read forwards.
    private var items: [HealthLogDay.Item] {
        day.itemsNewestFirst.reversed()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.stack) {
                ForEach(items) { item in
                    Card {
                        VStack(alignment: .leading, spacing: Space.row) {
                            LogEntryDetailView.content(for: item)
                        }
                    }
                }
                InlineNote(symbol: "lock", detail: loc.t("log.privacyFooter"))
            }
            .padding(.horizontal, Space.screen)
            .padding(.vertical, Space.row)
            .readableColumn()
        }
        .background(Palette.plane)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: export) {
                    if isExporting {
                        ProgressView()
                    } else {
                        Label(loc.t("log.exportDay"), systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isExporting)
                .accessibilityLabel(loc.t("log.exportDay"))
            }
        }
    }

    /// This day alone, as its own PDF.
    private func export() {
        guard !isExporting else { return }
        isExporting = true
        Haptic.selection()
        Task { @MainActor in
            await HealthLogPDF.share(days: [day], loc: loc, unit: preferences.temperatureUnit,
                                     names: name.map { [day.date: $0] } ?? [:],
                                     numbers: number.map { [day.date: $0] } ?? [:])
            isExporting = false
        }
    }
}
