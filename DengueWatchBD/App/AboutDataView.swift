import SwiftUI

struct AboutDataView: View {
    @Environment(SurveillanceStore.self) private var store
    @Environment(LocalizationManager.self) private var loc
    @Environment(SurveillanceSync.self) private var sync
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(loc.t("about.language")) {
                    Picker(loc.t("about.language"), selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.nativeName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let meta = store.meta {
                    Section(loc.t("about.build")) {
                        LabeledContent(loc.t("about.dataset"), value: meta.datasetName)
                        LabeledContent(loc.t("about.lastUpdated"), value: meta.lastUpdated)
                        LabeledContent(loc.t("about.seasonStart"), value: meta.seasonStart)
                        LabeledContent(loc.t("about.districts"), value: loc.num(store.districts.count))
                    }

                    Section {
                        Text(meta.disclaimer).typo(.callout)
                    } header: {
                        Label(loc.t("about.readFirst"), systemImage: "exclamationmark.triangle.fill")
                    }

                    Section(loc.t("about.attribution")) {
                        Text(meta.attribution).typo(.callout)
                    }
                }

                Section(loc.t("about.sync")) {
                    SyncStatusRow()
                    Button(loc.t("sync.checkNow")) {
                        Task {
                            await sync.sync(force: true)
                            await store.reload()
                        }
                    }
                }

                Section(loc.t("about.howNumbers")) {
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(1...5, id: \.self) { index in
                            bullet(loc.t("about.bullet\(index)"))
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(loc.t("about.medical")) {
                    Text(loc.t("about.medicalDetail")).typo(.callout)
                }

                Section(loc.t("about.privacy")) {
                    Text(loc.t("about.privacyDetail")).typo(.callout)
                }

                Section(loc.t("about.goingLive")) {
                    Text(loc.t("about.goingLiveDetail"))
                        .typo(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(loc.t("about.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.t("common.done")) { dismiss() }
                }
            }
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { loc.language },
                set: { newValue in withAnimation(.snappy(duration: 0.25)) { loc.language = newValue } })
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(Palette.accent.opacity(0.5))
                .frame(width: 5, height: 5).padding(.top, 7)
            Text(text).typo(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Shown once, before any number is — and it opens with the language choice, so
/// a Bengali reader is not made to read the disclosures in English first.
struct FirstRunDisclaimerView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Text(loc.t("intro.language"))
                        .typo(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.nativeName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.top, 8)

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 40))
                    .foregroundStyle(Palette.accent)

                Text(loc.t("intro.title")).typo(.title)

                VStack(alignment: .leading, spacing: 15) {
                    point("checkmark.seal", "intro.p1")
                    point("building.2", "intro.p2")
                    point("stethoscope", "intro.p3")
                    point("lock", "intro.p4")
                }

                Button {
                    preferences.hasSeenDisclaimer = true
                    dismiss()
                } label: {
                    Text(loc.t("intro.understand"))
                        .typo(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
            .padding(24)
            // The five tabs and the map overlays are column-capped; this screen
            // was missed because it only ever appears once. On an iPad that left
            // the language picker and the button stretched the full width, with
            // the disclosures running at about twice a comfortable measure — on
            // the very first screen anyone sees.
            .readableColumn()
        }
        .interactiveDismissDisabled()
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { loc.language },
                set: { newValue in withAnimation(.snappy(duration: 0.25)) { loc.language = newValue } })
    }

    private func point(_ symbol: String, _ keyPrefix: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol)
                .typo(.callout)
                .foregroundStyle(Palette.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(loc.t("\(keyPrefix).title"))
                    .typo(.subheadline).fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(loc.t("\(keyPrefix).detail"))
                    .typo(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
