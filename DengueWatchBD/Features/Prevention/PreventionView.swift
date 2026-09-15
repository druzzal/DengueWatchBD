import SwiftUI

struct PreventionView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var expanded: Set<String> = ["breeding"]
    @State private var checklist = PreventionChecklist()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentMonthIndex: Int { Calendar.current.component(.month, from: Date()) - 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if sizeClass == .regular {
                        ScreenTitle(text: loc.t("prevent.title"))
                    }
                    checklistCard
                    seasonalCard
                    mythCard

                    ForEach(PreventionContent.topics) { topic in
                        topicCard(topic)
                    }

                    alertsEntry
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .readableColumn()
            }
            .background(Palette.plane)
            .columnAlignedTitle(loc.t("prevent.title"), isWide: sizeClass == .regular)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { LanguageToggle() }
            }
        }
    }

    /// Today's five tasks, with an honest count and nothing else.
    ///
    /// No streak, no badge, no celebration beyond a quiet line when the last
    /// one is ticked — the brief for this was explicitly that it must not
    /// become a game people tire of.
    private var checklistCard: some View {
        CardSection(loc.t("checklist.title"), subtitle: loc.t("checklist.subtitle")) {
            VStack(alignment: .leading, spacing: Space.row) {
                HStack(spacing: Space.tight) {
                    ProgressView(value: checklist.fraction)
                        .tint(Palette.riskTint(.low))
                    Text(loc.t("checklist.progress",
                               loc.num(checklist.completedCount),
                               loc.num(checklist.total)))
                        .typo(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(loc.t("checklist.progress",
                                          loc.num(checklist.completedCount),
                                          loc.num(checklist.total)))

                VStack(spacing: 0) {
                    ForEach(PreventionTask.allCases) { task in
                        let done = checklist.isDone(task)
                        Button {
                            withAnimation(reduceMotion ? nil : Motion.interactive) {
                                checklist.toggle(task)
                            }
                            Haptic.selection()
                        } label: {
                            HStack(spacing: Space.row) {
                                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(done ? Palette.riskTint(.low) : Color.secondary)
                                Image(systemName: task.symbol)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                    .accessibilityHidden(true)
                                Text(loc.t(task.titleKey))
                                    .typo(.callout)
                                    .strikethrough(done, color: .secondary)
                                    .foregroundStyle(done ? Color.secondary : Color.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: Hit.minimum)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // State goes through the trait, not through colour or a
                        // strikethrough, so VoiceOver reads it as a checkbox.
                        .accessibilityAddTraits(done ? [.isButton, .isSelected] : .isButton)
                        .accessibilityValue(loc.t(done ? "checklist.a11y.done"
                                                       : "checklist.a11y.notDone"))
                    }
                }

                if checklist.isComplete {
                    Text(loc.t("checklist.allDone"))
                        .typo(.caption)
                        .foregroundStyle(Palette.riskTint(.low))
                        .transition(.opacity)
                }
            }
        }
        .onAppear { checklist.refreshIfDayChanged() }
    }

    /// Beliefs that cost people time, paired with what is actually true.
    ///
    /// Myth first and fact second, visually distinct, because a reader
    /// skimming must not come away remembering the myth as the message. The
    /// myth is set in the muted colour and the fact in the primary one.
    private var mythCard: some View {
        CardSection(loc.t("myth.section"), subtitle: loc.t("myth.section.subtitle"),
                    isExpanded: expandedBinding(for: "myths")) {
            VStack(spacing: 0) {
                ForEach(Array(MythFact.all.enumerated()), id: \.element.id) { index, item in
                    // A grid rather than two rows of fixed-width labels. The
                    // labels used to sit in a 54pt frame, which "MYTH" already
                    // overflowed in English — so it hung further left than
                    // "FACT" and the two never lined up. Bengali is worse:
                    // "ভ্রান্ত ধারণা" beside "সত্য" is nowhere near 54pt. A grid
                    // column takes the width of the widest label in whatever
                    // language is on screen, and both rows then share an edge.
                    Grid(alignment: .topLeading, horizontalSpacing: Space.tight,
                         verticalSpacing: Space.tight) {
                        GridRow {
                            Text(loc.t("myth.label").uppercased())
                                .typo(.micro)
                                .fontWeight(.bold)
                                .foregroundStyle(Palette.riskTint(.high))
                            Text(loc.t(item.mythKey))
                                .typo(.callout)
                                .foregroundStyle(.secondary)
                                .strikethrough(true, color: Palette.riskTint(.high).opacity(0.5))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        GridRow {
                            Text(loc.t("myth.fact.label").uppercased())
                                .typo(.micro)
                                .fontWeight(.bold)
                                .foregroundStyle(Palette.riskTint(.low))
                            Text(loc.t(item.factKey))
                                .typo(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, Space.row)
                    .accessibilityElement(children: .combine)

                    if index < MythFact.all.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var seasonalCard: some View {
        CardSection(loc.t("prevent.season.title"), subtitle: loc.t("prevent.season.subtitle")) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(PreventionContent.seasonalPattern.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 5) {
                        // "Now" used to be a hard black outline drawn on top of
                        // the bar, which fought the band colour it sat on. A
                        // caret above the bar marks the month without touching
                        // the colour that carries the meaning.
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(index == currentMonthIndex ? Color.primary : .clear)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.level.tint)
                            .frame(height: 26 + CGFloat(item.level.rawValue) * 9)
                        Text(loc.t(item.labelKey))
                            .font(.system(size: 9,
                                          weight: index == currentMonthIndex ? .bold : .regular))
                            .foregroundStyle(index == currentMonthIndex ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 84, alignment: .bottom)

            RiskScaleLegend()

            if PreventionContent.seasonalPattern.indices.contains(currentMonthIndex) {
                let item = PreventionContent.seasonalPattern[currentMonthIndex]
                HStack(alignment: .top, spacing: 9) {
                    RiskBadge(risk: item.level, compact: true)
                    Text(loc.t(item.noteKey))
                        .typo(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(loc.t("prevent.season.footnote"))
                .typo(.micro).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Open/closed state for a card, over the same set the topic cards use, so
    /// there is one place a section's disclosure lives.
    private func expandedBinding(for id: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(id) },
                set: { isOpen in
                    if isOpen { expanded.insert(id) } else { expanded.remove(id) }
                })
    }

    private func topicCard(_ topic: PreventionTopic) -> some View {
        let isOpen = expanded.contains(topic.id)
        return Card {
            VStack(alignment: .leading, spacing: 13) {
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        if isOpen { expanded.remove(topic.id) } else { expanded.insert(topic.id) }
                    }
                } label: {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: topic.symbol)
                            .font(.title3)
                            .foregroundStyle(Palette.accent)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(loc.t(topic.titleKey))
                                .typo(.headline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Text(loc.t(topic.summaryKey))
                                .typo(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.down")
                            .typo(.caption)
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isOpen ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(loc.t(topic.titleKey))
                .accessibilityValue(loc.t(isOpen ? "common.expanded" : "common.collapsed"))

                if isOpen {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(topic.stepKeys, id: \.self) { key in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(Palette.accent.opacity(0.5))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 7)
                                Text(loc.t(key))
                                    .typo(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.leading, 39)
                }
            }
        }
    }

    /// What the card says underneath its title.
    ///
    /// It used to report only the rise alert, so someone who had turned on the
    /// high-risk entry warning — and nothing else — read "Off" on the one row
    /// that was supposed to tell them their alerts were working.
    private var alertsSummary: String {
        switch (preferences.alertsEnabled, preferences.geofenceAlertsEnabled) {
        case (true, true):
            return loc.t("alerts.state.both")
        case (true, false):
            return loc.t("alerts.on", loc.t(preferences.alertThreshold.labelKey))
        case (false, true):
            return loc.t("alerts.state.entryOnly")
        case (false, false):
            return loc.t("alerts.off")
        }
    }

    private var alertsEntry: some View {
        NavigationLink {
            AlertSettingsView()
        } label: {
            Card {
                HStack(spacing: 13) {
                    Image(systemName: "bell.badge")
                        .font(.title3)
                        .foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc.t("alerts.entry"))
                            .typo(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text(alertsSummary)
                            .typo(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .typo(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
