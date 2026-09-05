import Foundation

/// Bengali names for the reporting areas and the eight divisions.
///
/// These live here rather than in the feed because they are a property of the
/// place, not of any particular day's figures — the feed is keyed by area code
/// and needs no Bengali column.
enum PlaceNames {
    static func area(code: String, fallback: String, language: AppLanguage) -> String {
        guard language == .bangla else { return fallback }
        return areasBangla[code] ?? fallback
    }

    static func division(_ division: Division, language: AppLanguage) -> String {
        guard language == .bangla else { return division.rawValue }
        return divisionsBangla[division] ?? division.rawValue
    }

    private static let divisionsBangla: [Division: String] = [
        .barishal: "বরিশাল",
        .chattogram: "চট্টগ্রাম",
        .dhaka: "ঢাকা",
        .khulna: "খুলনা",
        .mymensingh: "ময়মনসিংহ",
        .rajshahi: "রাজশাহী",
        .rangpur: "রংপুর",
        .sylhet: "সিলেট",
    ]

    /// Keyed by `Geography.Definition.code`.
    private static let areasBangla: [String: String] = [
        "BARISHAL": "বরিশাল",
        "CHATTOGRAM": "চট্টগ্রাম",
        "DHAKA_OUT_CC": "ঢাকা (সিটির বাইরে)",
        "DNCC": "ঢাকা উত্তর সিটি",
        "DSCC": "ঢাকা দক্ষিণ সিটি",
        "KHULNA": "খুলনা",
        "MYMENSINGH": "ময়মনসিংহ",
        "RAJSHAHI": "রাজশাহী",
        "RANGPUR": "রংপুর",
        "SYLHET": "সিলেট",
    ]

    static var codeCount: Int { areasBangla.count }
}

extension Area {
    func displayName(_ language: AppLanguage) -> String {
        PlaceNames.area(code: code, fallback: name, language: language)
    }
}

extension Division {
    func displayName(_ language: AppLanguage) -> String {
        PlaceNames.division(self, language: language)
    }
}
