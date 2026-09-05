import SwiftUI

struct SymptomCheckerView: View {
    @Environment(DengueStore.self) private var store
    @Environment(CaseLogStore.self) private var log
    @Environment(Preferences.self) private var preferences
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var selected: Set<String> = []
    @State private var context = TriageEngine.Context()
    @State private var feverStarted = Date()
    @State private var hasFeverDate = false
    @State private var showingResult = false
    @State private var showingLog = false

    private var daysSinceFever: Int {
        Calendar.current.dateComponents([.day],
                                        from: Calendar.current.startOfDay(for: feverStarted),
                                        to: Calendar.current.startOfDay(for: Date())).day ?? 0
    }

    private var outcome: TriageOutcome {
        var resolved = context
        resolved.feverDaysAgo = hasFeverDate ? daysSinceFever : nil
        return TriageEngine.evaluate(selected: selected, context: resolved)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(loc.t("check.intro"))
                        .typo(.callout)
                        .foregroundStyle(.secondary)
                }

                ForEach(Symptom.Group.allCases) { group in
                    Section {
                        ForEach(TriageEngine.symptoms(in: group)) { symptom in
                            SymptomRow(symptom: symptom,
                                       isOn: selected.contains(symptom.id)) { isOn in
                                if isOn { selected.insert(symptom.id) } else { selected.remove(symptom.id) }
                            }
                        }
                    } header: {
                        Text(loc.t(group.titleKey))
                    } footer: {
                        Text(loc.t(group.footnoteKey))
                    }
                }

                Section(loc.t("check.fever.section")) {
                    Toggle(loc.t("check.fever.knowDate"), isOn: $hasFeverDate.animation())
                    if hasFeverDate {
                        DatePicker(loc.t("check.fever.started"), selection: $feverStarted,
                                   in: Date().addingTimeInterval(-30 * 86_400)...Date(),
                                   displayedComponents: .date)
                        if let key = TriageEngine.phaseKey(feverDaysAgo: daysSinceFever) {
                            Text(loc.t(key, loc.num(daysSinceFever + 1)))
                                .typo(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle(loc.t("check.risk.pregnant"), isOn: $context.isPregnant)
                    Toggle(loc.t("check.risk.age"), isOn: $context.isUnderFiveOrOverSixty)
                    Toggle(loc.t("check.risk.chronic"), isOn: $context.hasChronicCondition)
                    Toggle(loc.t("check.risk.previous"), isOn: $context.hadDengueBefore)
                } header: {
                    Text(loc.t("check.risk.section"))
                } footer: {
                    Text(loc.t("check.risk.footer"))
                }

                Section {
                    Button {
                        showingResult = true
                    } label: {
                        Text(loc.t("check.seeResult"))
                            .typo(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty)

                    if !selected.isEmpty {
                        Button(loc.t("check.clearAll"), role: .destructive) {
                            selected.removeAll()
                            context = TriageEngine.Context()
                            hasFeverDate = false
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .readableColumn()
            .navigationTitle(loc.t("check.title"))
            .navigationBarTitleDisplayMode(sizeClass == .regular ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { LanguageToggle() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingLog = true
                    } label: {
                        Image(systemName: "list.clipboard")
                    }
                    .accessibilityLabel(loc.t("log.title"))
                }
            }
            .sheet(isPresented: $showingLog) { CaseLogView() }
            .navigationDestination(isPresented: $showingResult) {
                TriageResultView(
                    outcome: outcome,
                    selected: selected,
                    phaseKey: hasFeverDate ? TriageEngine.phaseKey(feverDaysAgo: daysSinceFever) : nil,
                    feverDay: hasFeverDate ? daysSinceFever + 1 : nil,
                    onSave: { note, temperature in
                        log.add(CaseLogEntry(temperature: temperature,
                                             symptomIDs: Array(selected),
                                             outcomeRawValue: outcome.rawValue,
                                             areaCode: preferences.homeAreaCode,
                                             note: note))
                    }
                )
            }
        }
    }
}

/// A symptom row carries its own illustration — the drawing does the work of
/// recognition before the words are read, which matters when someone is ill or
/// reading in their second language.
private struct SymptomRow: View {
    @Environment(LocalizationManager.self) private var loc
    let symptom: Symptom
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            onChange(!isOn)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Palette.accent : Color.secondary)

                SymptomIllustration(symptomID: symptom.id, group: symptom.group, size: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t(symptom.titleKey))
                        .typo(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(loc.t(symptom.detailKey))
                        .typo(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Left to itself, SwiftUI guessed the separator inset per row and got a
        // different answer for rows whose text wrapped — so the list alternated
        // between full-width and text-inset rules. Pin it to the text column.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

struct TriageResultView: View {
    let outcome: TriageOutcome
    let selected: Set<String>
    let phaseKey: String?
    let feverDay: Int?
    let onSave: (String, Double?) -> Void

    @Environment(LocalizationManager.self) private var loc
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var temperature = ""
    @State private var saved = false

    private var accent: Color {
        switch outcome {
        case .selfCare: Palette.downIsGood
        case .testAdvised: Palette.riskTint(.moderate)
        case .seeDoctorToday: Palette.riskTint(.high)
        case .emergency: Palette.riskTint(.severe)
        }
    }

    /// The signs the person actually ticked, worst group first — so the drawing
    /// they see on the result screen is the one that drove the advice.
    private var reportedSigns: [Symptom] {
        TriageEngine.symptoms
            .filter { selected.contains($0.id) }
            .sorted { lhs, rhs in
                let order: [Symptom.Group: Int] = [.severe: 0, .warning: 1, .core: 2]
                return (order[lhs.group] ?? 3) < (order[rhs.group] ?? 3)
            }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                verdictCard
                signsCard
                actionsCard

                if outcome == .emergency || outcome == .seeDoctorToday {
                    emergencyActions
                }

                logCard

                Text(loc.t("result.disclaimer"))
                    .typo(.micro)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .readableColumn()
        }
        .background(Palette.plane)
        .navigationTitle(loc.t("result.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var verdictCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: outcome.symbolName)
                    .font(.title2)
                    .foregroundStyle(accent)
                Text(loc.t(outcome.headlineKey))
                    .typo(.title)
            }
            Text(loc.t(outcome.summaryKey))
                .typo(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let phaseKey, let feverDay {
                Text(loc.t(phaseKey, loc.num(feverDay)))
                    .typo(.caption)
                    .foregroundStyle(.secondary)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(accent.opacity(0.5), lineWidth: 1.5))
    }

    private var signsCard: some View {
        CardSection(loc.t("check.title")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(reportedSigns) { symptom in
                        VStack(spacing: 7) {
                            SymptomIllustration(symptomID: symptom.id, group: symptom.group, size: 66)
                            Text(loc.t(symptom.titleKey))
                                .typo(.micro)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .frame(width: 84)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var actionsCard: some View {
        CardSection(loc.t("result.whatToDo")) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(outcome.actionKeys.enumerated()), id: \.offset) { index, key in
                    HStack(alignment: .top, spacing: 11) {
                        Text(loc.num(index + 1))
                            .typo(.caption).fontWeight(.bold)
                            .foregroundStyle(accent)
                            .frame(width: 20, height: 20)
                            .background(accent.opacity(0.14), in: Circle())
                        Text(loc.t(key))
                            .typo(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var emergencyActions: some View {
        VStack(spacing: 10) {
            if let url = URL(string: "tel://999") {
                Link(destination: url) {
                    Label(loc.t("result.call999"), systemImage: "phone.fill")
                        .typo(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.riskTint(.severe))
            }
            NavigationLink {
                CareView()
            } label: {
                Label(loc.t("result.findHospital"), systemImage: "cross.case.fill")
                    .typo(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
    }

    private var logCard: some View {
        CardSection(loc.t("result.addToLog"), subtitle: loc.t("result.keptOnPhone")) {
            TextField(loc.t("result.temperature"), text: $temperature)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            TextField(loc.t("result.note"), text: $note, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            Button {
                onSave(note, Double(temperature))
                saved = true
            } label: {
                Label(loc.t(saved ? "common.saved" : "result.saveEntry"),
                      systemImage: saved ? "checkmark" : "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(saved)
        }
    }
}
