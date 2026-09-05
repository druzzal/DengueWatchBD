import SwiftUI

struct PreventionView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var expanded: Set<String> = ["breeding"]

    private var currentMonthIndex: Int { Calendar.current.component(.month, from: Date()) - 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if sizeClass == .regular {
                        ScreenTitle(text: loc.t("prevent.title"))
                    }
                    seasonalCard

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
