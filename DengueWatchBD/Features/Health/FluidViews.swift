import SwiftUI

/// Today's fluids: what the reader has drunk and how often they have passed
/// urine, against the one target WHO gives patients themselves.
///
/// It records and totals. The only line it adds of its own is the six-hour
/// urine gap, which is the symptom check's own warning sign, said where the
/// gap shows up rather than left for the reader to notice.
struct FluidCard: View {
    @Environment(FluidStore.self) private var fluids
    @Environment(LocalizationManager.self) private var loc

    @State private var showingEntry = false
    @State private var showingEntries = false

    var body: some View {
        let today = fluids.day(Date())
        let todays = fluids.entries(on: Date())

        CardSection(loc.t("fluid.section"), subtitle: loc.t("fluid.subtitle")) {
            VStack(alignment: .leading, spacing: Space.row) {
                HStack(spacing: Space.row) {
                    FluidTile(label: loc.t("fluid.drunk"),
                              value: loc.num(today.drunkMillilitres),
                              unit: loc.t("fluid.unit.ml"),
                              detail: "\(loc.t("fluid.drinks")): \(loc.num(today.drinks))")
                        .accessibilityIdentifier("fluidIntakeTile")
                    FluidTile(label: loc.t("fluid.urine"),
                              value: loc.num(today.urinations),
                              unit: loc.t("fluid.unit.times"),
                              detail: loc.t("fluid.urine.aim",
                                            loc.num(FluidLog.urinationAim.lowerBound),
                                            loc.num(FluidLog.urinationAim.upperBound)))
                        .accessibilityIdentifier("fluidUrineTile")
                }

                if FluidLog.urineGapIsLong(entries: fluids.entries) {
                    InlineNote(symbol: "exclamationmark.triangle.fill",
                               detail: loc.t("fluid.urine.gap",
                                             loc.num(Int(FluidLog.urineGapHours))),
                               tint: Palette.riskInk(.high))
                }

                HStack(spacing: Space.row) {
                    SecondaryActionButton(title: loc.t("fluid.addDrink"),
                                          systemImage: "cup.and.saucer.fill") {
                        showingEntry = true
                    }
                    // One tap, timed now: this is logged several times a day,
                    // often by someone looking after a patient. A different
                    // time can still be chosen through the sheet.
                    SecondaryActionButton(title: loc.t("fluid.addUrine"),
                                          systemImage: "drop.fill") {
                        fluids.add(FluidEntry(kind: .urine))
                        Haptic.selection()
                    }
                }

                if !todays.isEmpty {
                    DisclosureGroup(isExpanded: $showingEntries) {
                        FluidEntryList(entries: todays, allowsDeletion: true)
                            .padding(.top, Space.tight)
                    } label: {
                        Text(loc.t("fluid.todayEntries", loc.num(todays.count)))
                            .typo(.callout)
                    }
                    .tint(Palette.accent)
                }

                InlineNote(symbol: "info.circle", detail: loc.t("fluid.whatToDrink"))
            }
        }
        .sheet(isPresented: $showingEntry) { FluidEntryView() }
    }
}

/// One of the two totals: a figure, its unit, and a line of context.
private struct FluidTile: View {
    let label: String
    let value: String
    let unit: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .typo(.micro)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .typo(.statValue)
                    .monospacedDigit()
                Text(unit)
                    .typo(.micro)
                    .foregroundStyle(Color.secondary)
            }
            Text(detail)
                .typo(.micro)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.row)
        .background(Palette.plane,
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A day's fluid entries, oldest first.
struct FluidEntryList: View {
    @Environment(FluidStore.self) private var fluids
    @Environment(LocalizationManager.self) private var loc
    let entries: [FluidEntry]
    var allowsDeletion = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: Space.row) {
                    Image(systemName: entry.kind == .drink ? "cup.and.saucer.fill" : "drop.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(label(for: entry))
                        .typo(.callout)
                    Spacer(minLength: Space.tight)
                    Text(loc.time(entry.date))
                        .typo(.micro)
                        .foregroundStyle(Color.secondary)
                        .monospacedDigit()
                    if allowsDeletion {
                        Button {
                            withAnimation { fluids.delete(id: entry.id) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Palette.mutedInk)
                                .frame(minWidth: Hit.minimum, minHeight: Hit.minimum)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(loc.t("common.delete"))
                    }
                }
                .frame(minHeight: Hit.minimum)
                .accessibilityElement(children: .contain)
                if index < entries.count - 1 { Divider() }
            }
        }
    }

    private func label(for entry: FluidEntry) -> String {
        switch entry.kind {
        case .drink: "\(loc.num(entry.millilitres ?? 0)) \(loc.t("fluid.unit.ml"))"
        case .urine: loc.t("fluid.urine")
        }
    }
}

/// One day's fluids in the log: the totals, then each entry.
struct FluidDaySummary: View {
    @Environment(LocalizationManager.self) private var loc
    let entries: [FluidEntry]

    var body: some View {
        let day = FluidLog.day(entries.first?.date ?? Date(), entries: entries)
        VStack(alignment: .leading, spacing: Space.row) {
            Label(loc.t("fluid.log.title"), systemImage: "cup.and.saucer.fill")
                .typo(.subheadline)
                .fontWeight(.semibold)
            HStack(spacing: Space.row) {
                FluidTile(label: loc.t("fluid.drunk"),
                          value: loc.num(day.drunkMillilitres),
                          unit: loc.t("fluid.unit.ml"),
                          detail: "\(loc.t("fluid.drinks")): \(loc.num(day.drinks))")
                FluidTile(label: loc.t("fluid.urine"),
                          value: loc.num(day.urinations),
                          unit: loc.t("fluid.unit.times"),
                          detail: loc.t("fluid.urine.aim",
                                        loc.num(FluidLog.urinationAim.lowerBound),
                                        loc.num(FluidLog.urinationAim.upperBound)))
            }
            FluidEntryList(entries: entries)
        }
    }
}

/// Adding one drink, or a time urine was passed that was not logged then.
struct FluidEntryView: View {
    @Environment(FluidStore.self) private var fluids
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.dismiss) private var dismiss

    @State private var kind: FluidEntry.Kind = .drink
    @State private var millilitres = 200
    @State private var takenAt = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $kind) {
                        Text(loc.t("fluid.kind.drink")).tag(FluidEntry.Kind.drink)
                        Text(loc.t("fluid.urine")).tag(FluidEntry.Kind.urine)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                if kind == .drink {
                    Section {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.tight),
                                                 count: 3),
                                  spacing: Space.tight) {
                            ForEach(FluidLog.presetMillilitres, id: \.self) { amount in
                                preset(amount)
                            }
                        }
                        .padding(.vertical, Space.hair)
                        Stepper(value: $millilitres, in: FluidLog.plausibleMillilitres, step: 50) {
                            Text("\(loc.num(millilitres)) \(loc.t("fluid.unit.ml"))")
                                .monospacedDigit()
                        }
                    } header: {
                        Text(loc.t("fluid.amount"))
                    } footer: {
                        Text(loc.t("fluid.amount.footer"))
                    }
                }

                Section {
                    DatePicker(loc.t("fluid.when"), selection: $takenAt,
                               in: Date().addingTimeInterval(-7 * 86_400)...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                        // Follows the app's language, as the other pickers do.
                        .environment(\.locale, loc.pickerLocale)
                }
            }
            .navigationTitle(loc.t("fluid.add.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.t("common.save")) { save() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func preset(_ amount: Int) -> some View {
        let isOn = millilitres == amount
        return Button {
            millilitres = amount
            Haptic.selection()
        } label: {
            Text("\(loc.num(amount)) \(loc.t("fluid.unit.ml"))")
                .typo(.callout)
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: Hit.minimum)
                .foregroundStyle(isOn ? Color.white : Palette.accent)
                .background(isOn ? Palette.accent : Palette.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private func save() {
        fluids.add(FluidEntry(date: takenAt, kind: kind,
                              millilitres: kind == .drink ? millilitres : nil))
        dismiss()
    }
}
