import SwiftUI

/// One day of the record, in full.
///
/// Everything written down that day, oldest moment first, so it reads as the
/// day happened rather than as a stack with the newest on top. This is the
/// screen a reader holds up to a doctor, so nothing is abbreviated.
struct LogDayDetailView: View {
    @Environment(LocalizationManager.self) private var loc
    let day: HealthLogDay
    let title: String

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
    }
}
