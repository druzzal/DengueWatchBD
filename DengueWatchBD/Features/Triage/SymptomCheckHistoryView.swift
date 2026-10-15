import SwiftUI

/// Every symptom check the reader has finished, newest first, each one
/// deletable on its own.
///
/// The health log lists measurements, not checks, so this is the only place a
/// single check can be removed. That matters because the latest check drives
/// the care plan and the fever timeline: a mis-tap or a trial run would
/// otherwise go on giving advice until another check replaced it.
struct SymptomCheckHistoryView: View {
    @Environment(CaseLogStore.self) private var log
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.dismiss) private var dismiss

    /// The check a reader has asked to delete, held until they confirm.
    /// A check cannot be rebuilt, so a swipe alone is not enough.
    @State private var pendingDeletion: CaseLogEntry?

    var body: some View {
        NavigationStack {
            Group {
                if log.entries.isEmpty {
                    ContentUnavailableView {
                        Label(loc.t("check.history.title"), systemImage: "stethoscope")
                    } description: {
                        Text(loc.t("health.empty"))
                    }
                } else {
                    List {
                        Section {
                            ForEach(log.entries) { entry in
                                CheckHistoryRow(entry: entry,
                                                isLatest: entry.id == log.entries.first?.id)
                                    .swipeActions {
                                        Button(loc.t("common.delete"), role: .destructive) {
                                            pendingDeletion = entry
                                        }
                                    }
                                    .contextMenu {
                                        Button(loc.t("common.delete"), systemImage: "trash",
                                               role: .destructive) {
                                            pendingDeletion = entry
                                        }
                                    }
                            }
                        } footer: {
                            Text(loc.t("check.history.footer"))
                        }
                    }
                }
            }
            .readableColumn()
            .navigationTitle(loc.t("check.history.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.t("common.done")) { dismiss() }
                }
            }
            .confirmCheckDeletion($pendingDeletion, from: log, loc: loc)
        }
    }
}

/// One finished check: what it advised, and when.
private struct CheckHistoryRow: View {
    @Environment(LocalizationManager.self) private var loc
    let entry: CaseLogEntry
    let isLatest: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Space.row) {
            Image(systemName: entry.outcome.symbolName)
                .font(.title3)
                .foregroundStyle(Palette.riskTint(entry.outcome.risk))
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(loc.t(entry.outcome.headlineKey))
                    .typo(.callout)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
                Text(loc.dayAndTime(entry.date))
                    .typo(.micro)
                    .foregroundStyle(.secondary)
                if isLatest {
                    // Said on the row, so deleting it is not a surprise to the
                    // care plan the reader reads next.
                    Text(loc.t("check.history.latest"))
                        .typo(.micro)
                        .foregroundStyle(Palette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// The one confirmation for deleting a symptom check, shared by the card
    /// in My health and the list of past checks so both ask the same question.
    func confirmCheckDeletion(_ pending: Binding<CaseLogEntry?>,
                              from log: CaseLogStore,
                              loc: LocalizationManager) -> some View {
        confirmationDialog(loc.t("check.delete.confirm"),
                           isPresented: Binding(get: { pending.wrappedValue != nil },
                                                set: { if !$0 { pending.wrappedValue = nil } }),
                           titleVisibility: .visible) {
            Button(loc.t("common.delete"), role: .destructive) {
                if let entry = pending.wrappedValue {
                    withAnimation { log.delete(id: entry.id) }
                    Haptic.selection()
                }
                pending.wrappedValue = nil
            }
            Button(loc.t("common.cancel"), role: .cancel) { pending.wrappedValue = nil }
        } message: {
            Text(loc.t("check.delete.detail"))
        }
    }
}
