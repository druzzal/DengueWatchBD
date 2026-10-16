import SwiftUI

/// Keeps a form's unsaved fields in the scene's own storage.
///
/// iOS can end an app in the background to free memory, and a reader who
/// switched away mid-entry — to find the lab report, to answer a message —
/// came back to an empty form. Scene storage is what iOS restores after it
/// ends the app itself, and what it discards when the reader swipes the app
/// away, which is the right line: a reading half-typed when the system
/// stepped in comes back; one abandoned on purpose does not.
///
/// The draft is cleared whenever the form goes away normally — saved,
/// cancelled or swiped down — so opening it again always starts empty, as it
/// did before. The Android build keeps the same fields the same way.
struct FormDraft<Draft: Codable & Equatable>: ViewModifier {
    @SceneStorage private var stored: Data?
    @Binding var draft: Draft

    init(key: String, draft: Binding<Draft>) {
        _stored = SceneStorage(key)
        _draft = draft
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                if let stored, let restored = try? JSONDecoder().decode(Draft.self, from: stored) {
                    draft = restored
                }
            }
            .onChange(of: draft) { _, latest in
                stored = try? JSONEncoder().encode(latest)
            }
            .onDisappear { stored = nil }
    }
}

extension View {
    /// See `FormDraft`.
    func keepsDraft<Draft: Codable & Equatable>(_ key: String, _ draft: Binding<Draft>) -> some View {
        modifier(FormDraft(key: key, draft: draft))
    }
}
