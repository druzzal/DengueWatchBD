import Foundation

/// The two string tables.
///
/// Keys are grouped into chunks partly for readability and partly because a
/// single dictionary literal of this size makes the Swift type-checker crawl.
enum Strings {
    static func table(for language: AppLanguage) -> [String: String] {
        switch language {
        case .english: english
        case .bangla: bangla
        }
    }

    static let english: [String: String] = {
        var table = enCommon
        for chunk in [enDashboard, enMap, enCheck, enPrevent, enCare, enAbout, enRedesign] {
            table.merge(chunk) { _, new in new }
        }
        return table
    }()

    static let bangla: [String: String] = {
        var table = bnCommon
        for chunk in [bnDashboard, bnMap, bnCheck, bnPrevent, bnCare, bnAbout, bnRedesign] {
            table.merge(chunk) { _, new in new }
        }
        return table
    }()

    /// Debug-only parity check: every English key should exist in Bengali.
    static var missingBanglaKeys: [String] {
        english.keys.filter { bangla[$0] == nil }.sorted()
    }
}
