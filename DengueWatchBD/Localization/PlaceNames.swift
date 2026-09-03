import Foundation

/// Bengali names for the 64 districts and 8 divisions.
///
/// These live here rather than in the dataset because they are a property of
/// the place, not of any particular day's figures — a live feed keyed by the
/// same district codes needs no Bengali column.
enum PlaceNames {
    static func district(code: String, fallback: String, language: AppLanguage) -> String {
        guard language == .bangla else { return fallback }
        return bangla[code] ?? fallback
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

    /// Keyed by the dataset's district code.
    private static let bangla: [String: String] = [
        // Barishal
        "BARGUNA": "বরগুনা", "BARISHAL": "বরিশাল", "BHOLA": "ভোলা",
        "JHALOKATI": "ঝালকাঠি", "PATUAKHALI": "পটুয়াখালী", "PIROJPUR": "পিরোজপুর",
        // Chattogram
        "BANDARBAN": "বান্দরবান", "BRAHMANBARIA": "ব্রাহ্মণবাড়িয়া", "CHANDPUR": "চাঁদপুর",
        "CHATTOGRAM": "চট্টগ্রাম", "CUMILLA": "কুমিল্লা", "COXS_BAZAR": "কক্সবাজার",
        "FENI": "ফেনী", "KHAGRACHHARI": "খাগড়াছড়ি", "LAKSHMIPUR": "লক্ষ্মীপুর",
        "NOAKHALI": "নোয়াখালী", "RANGAMATI": "রাঙ্গামাটি",
        // Dhaka
        "DHAKA": "ঢাকা", "FARIDPUR": "ফরিদপুর", "GAZIPUR": "গাজীপুর",
        "GOPALGANJ": "গোপালগঞ্জ", "KISHOREGANJ": "কিশোরগঞ্জ", "MADARIPUR": "মাদারীপুর",
        "MANIKGANJ": "মানিকগঞ্জ", "MUNSHIGANJ": "মুন্সিগঞ্জ", "NARAYANGANJ": "নারায়ণগঞ্জ",
        "NARSINGDI": "নরসিংদী", "RAJBARI": "রাজবাড়ী", "SHARIATPUR": "শরীয়তপুর",
        "TANGAIL": "টাঙ্গাইল",
        // Khulna
        "BAGERHAT": "বাগেরহাট", "CHUADANGA": "চুয়াডাঙ্গা", "JASHORE": "যশোর",
        "JHENAIDAH": "ঝিনাইদহ", "KHULNA": "খুলনা", "KUSHTIA": "কুষ্টিয়া",
        "MAGURA": "মাগুরা", "MEHERPUR": "মেহেরপুর", "NARAIL": "নড়াইল",
        "SATKHIRA": "সাতক্ষীরা",
        // Mymensingh
        "JAMALPUR": "জামালপুর", "MYMENSINGH": "ময়মনসিংহ", "NETROKONA": "নেত্রকোণা",
        "SHERPUR": "শেরপুর",
        // Rajshahi
        "BOGURA": "বগুড়া", "CHAPAI_NAWAB": "চাঁপাইনবাবগঞ্জ", "JOYPURHAT": "জয়পুরহাট",
        "NAOGAON": "নওগাঁ", "NATORE": "নাটোর", "PABNA": "পাবনা",
        "RAJSHAHI": "রাজশাহী", "SIRAJGANJ": "সিরাজগঞ্জ",
        // Rangpur
        "DINAJPUR": "দিনাজপুর", "GAIBANDHA": "গাইবান্ধা", "KURIGRAM": "কুড়িগ্রাম",
        "LALMONIRHAT": "লালমনিরহাট", "NILPHAMARI": "নীলফামারী", "PANCHAGARH": "পঞ্চগড়",
        "RANGPUR": "রংপুর", "THAKURGAON": "ঠাকুরগাঁও",
        // Sylhet
        "HABIGANJ": "হবিগঞ্জ", "MOULVIBAZAR": "মৌলভীবাজার", "SUNAMGANJ": "সুনামগঞ্জ",
        "SYLHET": "সিলেট",
    ]

    static var codeCount: Int { bangla.count }
}

extension District {
    func displayName(_ language: AppLanguage) -> String {
        PlaceNames.district(code: code, fallback: name, language: language)
    }
}

extension Division {
    func displayName(_ language: AppLanguage) -> String {
        PlaceNames.division(self, language: language)
    }
}
