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

    @State private var step: CheckerStep = .fever

    private var steps: [CheckerStep] { CheckerStep.sequence(hasFever: selected.contains("fever")) }
    private var stepIndex: Int { steps.firstIndex(of: step) ?? 0 }
    private var isLastStep: Bool { stepIndex == steps.count - 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.stack) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(loc.t(step.titleKey)).typo(.title)
                            Text(loc.t(step.subtitleKey))
                                .typo(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        stepContent
                    }
                    .padding(.horizontal, Space.screen)
                    .padding(.top, Space.row)
                    .padding(.bottom, Space.section)
                    .readableColumn()
                }
                footer
            }
            .background(Palette.plane)
            .navigationTitle(loc.t("check.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { LanguageToggle() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingLog = true } label: {
                        Image(systemName: "list.clipboard")
                    }
                    .accessibilityLabel(loc.t("log.title"))
                }
            }
            .sheet(isPresented: $showingLog) { CaseLogView() }
            // Reset once the reader comes back from the result, not when the
            // result opens: clearing while it is still on screen would blank
            // the answers it is explaining. Returning means that check is
            // finished, and a half-filled form from a previous illness is a
            // worse starting point than an empty one — stale ticks would be
            // carried silently into the next result.
            .onChange(of: showingResult) { _, isShowing in
                guard !isShowing else { return }
                resetCheck()
            }
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

    /// Position in the flow, shown as segments rather than a percentage: the
    /// number of questions left is the thing someone actually wants to know.
    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, item in
                Capsule()
                    .fill(index <= stepIndex ? Palette.accent : Palette.grid)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, Space.screen)
        .padding(.vertical, Space.tight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loc.t("step.progress", loc.num(stepIndex + 1), loc.num(steps.count)))
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .fever: feverStep
        case .symptoms: symptomStep(group: .core, excluding: ["fever"])
        case .warningSigns: warningStep
        case .timeline: timelineStep
        case .riskFactors: riskStep
        }
    }

    // MARK: - Steps

    private var feverStep: some View {
        VStack(spacing: Space.row) {
            choiceTile(title: loc.t("step.fever.yes"),
                       symbol: "thermometer.high",
                       isOn: selected.contains("fever")) {
                selected.insert("fever")
                advance()
            }
            choiceTile(title: loc.t("step.fever.no"),
                       symbol: "thermometer.low",
                       isOn: !selected.contains("fever") && step != .fever) {
                selected.remove("fever")
                hasFeverDate = false
                advance()
            }
        }
    }

    private func symptomStep(group: Symptom.Group, excluding: Set<String>) -> some View {
        VStack(spacing: Space.tight) {
            ForEach(TriageEngine.symptoms(in: group).filter { !excluding.contains($0.id) }) { symptom in
                selectableTile(symptom: symptom, emphasis: false)
            }
        }
    }

    /// Warning and severe signs share a screen, drawn louder than the core
    /// symptoms, because these are the answers that change the advice.
    private var warningStep: some View {
        VStack(spacing: Space.tight) {
            ForEach([Symptom.Group.warning, .severe], id: \.self) { group in
                ForEach(TriageEngine.symptoms(in: group)) { symptom in
                    selectableTile(symptom: symptom, emphasis: true)
                }
            }
            Button(loc.t("step.warning.none")) {
                for group in [Symptom.Group.warning, .severe] {
                    for symptom in TriageEngine.symptoms(in: group) { selected.remove(symptom.id) }
                }
                advance()
            }
            .typo(.subheadline)
            .frame(maxWidth: .infinity, minHeight: Hit.minimum)
            .foregroundStyle(Palette.accent)
        }
    }

    private var timelineStep: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Toggle(loc.t("check.fever.knowDate"), isOn: $hasFeverDate.animation())
                .typo(.callout)
            if hasFeverDate {
                DatePicker(loc.t("check.fever.started"), selection: $feverStarted,
                           in: Date().addingTimeInterval(-30 * 86_400)...Date(),
                           displayedComponents: .date)
                    .typo(.callout)
                FeverTimelineView(feverDay: daysSinceFever + 1)
                    .padding(.top, Space.tight)
            } else {
                Text(loc.t("step.timeline.unknown"))
                    .typo(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Space.card)
        .cardSurface()
    }

    private var riskStep: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            Toggle(loc.t("check.risk.pregnant"), isOn: $context.isPregnant)
            Toggle(loc.t("check.risk.age"), isOn: $context.isUnderFiveOrOverSixty)
            Toggle(loc.t("check.risk.chronic"), isOn: $context.hasChronicCondition)
            Toggle(loc.t("check.risk.previous"), isOn: $context.hadDengueBefore)
            Text(loc.t("check.risk.footer"))
                .typo(.micro)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.hair)
        }
        .typo(.callout)
        .padding(Space.card)
        .cardSurface()
    }

    // MARK: - Pieces

    private func choiceTile(title: String, symbol: String,
                            isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.row) {
                Image(systemName: symbol).font(.title3)
                Text(title).typo(.headline)
                Spacer(minLength: 0)
                if isOn { Image(systemName: "checkmark.circle.fill") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 64)
            .padding(.horizontal, Space.card)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(isOn ? Palette.accent : Palette.card,
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private func selectableTile(symptom: Symptom, emphasis: Bool) -> some View {
        let isOn = selected.contains(symptom.id)
        let tint = emphasis ? Palette.riskTint(.high) : Palette.accent
        return Button {
            if isOn { selected.remove(symptom.id) } else { selected.insert(symptom.id) }
            Haptic.selection()
        } label: {
            HStack(alignment: .top, spacing: Space.row) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? tint : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t(symptom.titleKey)).typo(.callout).fontWeight(.medium)
                    Text(loc.t(symptom.detailKey))
                        .typo(.micro).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: Hit.minimum)
            .padding(Space.row)
            .background(isOn ? tint.opacity(0.10) : Palette.card,
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(isOn ? tint.opacity(0.45) : Palette.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private var footer: some View {
        HStack(spacing: Space.row) {
            if stepIndex > 0 {
                SecondaryActionButton(title: loc.t("step.back"),
                                      systemImage: "chevron.left") { retreat() }
            }
            PrimaryActionButton(title: isLastStep ? loc.t("step.seeResult") : loc.t("step.next")) {
                if isLastStep { showingResult = true } else { advance() }
            }
            // The engine tolerates an empty set, but a result from no answers
            // tells the reader nothing, so the last step waits for one.
            .disabled(isLastStep && selected.isEmpty)
        }
        .padding(.horizontal, Space.screen)
        .padding(.vertical, Space.row)
        .background(.bar)
    }

    /// Back to an empty check at step one.
    ///
    /// The case log keeps the finished check, so nothing is lost by clearing
    /// here — the record lives in CaseLogStore, not in this form's state.
    private func resetCheck() {
        selected.removeAll()
        context = TriageEngine.Context()
        hasFeverDate = false
        feverStarted = Date()
        step = .fever
    }

    private func advance() {
        guard let next = steps.first(where: { $0 > step }) else { return }
        withAnimation(Motion.interactive) { step = next }
    }

    private func retreat() {
        guard let previous = steps.last(where: { $0 < step }) else { return }
        withAnimation(Motion.interactive) { step = previous }
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
                VStack(alignment: .leading, spacing: Space.row) {
                    Text(loc.t(phaseKey, loc.num(feverDay)))
                        .typo(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // The same phase, drawn. The sentence says which phase this
                    // is; the track shows how much of the illness is still to
                    // come, which is what makes the critical window legible.
                    FeverTimelineView(feverDay: feverDay)
                }
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
