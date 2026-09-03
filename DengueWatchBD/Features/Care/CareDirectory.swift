import Foundation

/// National emergency lines. Only numbers that are stable, nationally published
/// and free to dial are listed — an emergency screen is the worst possible
/// place for a number that might be wrong.
struct EmergencyNumber: Identifiable, Hashable {
    let id: String
    let dial: String
    var nameKey: String { "care.sos.\(id).name" }
    var detailKey: String { "care.sos.\(id).detail" }

    static let all: [EmergencyNumber] = [
        EmergencyNumber(id: "999", dial: "999"),
        EmergencyNumber(id: "16263", dial: "16263"),
        EmergencyNumber(id: "333", dial: "333"),
    ]
}

/// A government hospital known to run a dengue ward in outbreak season.
///
/// Deliberately carries no phone number and no hard-coded coordinate. Published
/// hospital numbers change often, and a wrong number during an emergency is
/// worse than no number; likewise a stale coordinate can send someone to the
/// wrong side of a city. The name and city are stable, so directions are
/// resolved live through Maps instead.
struct Hospital: Identifiable, Hashable {
    let id: String
    let name: String
    let banglaName: String
    let city: String
    let banglaCity: String
    let division: Division

    func name(for language: AppLanguage) -> String {
        language == .bangla ? banglaName : name
    }

    func city(for language: AppLanguage) -> String {
        language == .bangla ? banglaCity : city
    }

    /// What gets handed to Maps for search and directions.
    var mapQuery: String { "\(name), \(city), Bangladesh" }
}

enum HospitalDirectory {
    static let all: [Hospital] = [
        // Dhaka
        Hospital(id: "dmch", name: "Dhaka Medical College Hospital",
                 banglaName: "ঢাকা মেডিকেল কলেজ হাসপাতাল",
                 city: "Dhaka", banglaCity: "ঢাকা", division: .dhaka),
        Hospital(id: "mitford", name: "Sir Salimullah Medical College Mitford Hospital",
                 banglaName: "স্যার সলিমুল্লাহ মেডিকেল কলেজ মিটফোর্ড হাসপাতাল",
                 city: "Dhaka", banglaCity: "ঢাকা", division: .dhaka),
        Hospital(id: "suhrawardy", name: "Shaheed Suhrawardy Medical College Hospital",
                 banglaName: "শহীদ সোহরাওয়ার্দী মেডিকেল কলেজ হাসপাতাল",
                 city: "Dhaka", banglaCity: "ঢাকা", division: .dhaka),
        Hospital(id: "mugda", name: "Mugda Medical College Hospital",
                 banglaName: "মুগদা মেডিকেল কলেজ হাসপাতাল",
                 city: "Dhaka", banglaCity: "ঢাকা", division: .dhaka),
        Hospital(id: "kurmitola", name: "Kurmitola General Hospital",
                 banglaName: "কুর্মিটোলা জেনারেল হাসপাতাল",
                 city: "Dhaka", banglaCity: "ঢাকা", division: .dhaka),
        Hospital(id: "bsmmu", name: "Bangabandhu Sheikh Mujib Medical University",
                 banglaName: "বঙ্গবন্ধু শেখ মুজিব মেডিকেল বিশ্ববিদ্যালয়",
                 city: "Dhaka", banglaCity: "ঢাকা", division: .dhaka),
        Hospital(id: "kuwait", name: "Kuwait Bangladesh Friendship Government Hospital",
                 banglaName: "কুয়েত বাংলাদেশ ফ্রেন্ডশিপ সরকারি হাসপাতাল",
                 city: "Uttara, Dhaka", banglaCity: "উত্তরা, ঢাকা", division: .dhaka),
        Hospital(id: "shishu", name: "Dhaka Shishu (Children) Hospital",
                 banglaName: "ঢাকা শিশু হাসপাতাল",
                 city: "Dhaka", banglaCity: "ঢাকা", division: .dhaka),
        Hospital(id: "mohanagar", name: "Mohanagar General Hospital",
                 banglaName: "মহানগর জেনারেল হাসপাতাল",
                 city: "Dhaka", banglaCity: "ঢাকা", division: .dhaka),
        Hospital(id: "tajuddin", name: "Shaheed Tajuddin Ahmad Medical College Hospital",
                 banglaName: "শহীদ তাজউদ্দীন আহমদ মেডিকেল কলেজ হাসপাতাল",
                 city: "Gazipur", banglaCity: "গাজীপুর", division: .dhaka),
        Hospital(id: "narayanganj", name: "Narayanganj General (Victoria) Hospital",
                 banglaName: "নারায়ণগঞ্জ জেনারেল (ভিক্টোরিয়া) হাসপাতাল",
                 city: "Narayanganj", banglaCity: "নারায়ণগঞ্জ", division: .dhaka),
        Hospital(id: "faridpur", name: "Faridpur Medical College Hospital",
                 banglaName: "ফরিদপুর মেডিকেল কলেজ হাসপাতাল",
                 city: "Faridpur", banglaCity: "ফরিদপুর", division: .dhaka),

        // Chattogram
        Hospital(id: "cmch", name: "Chattogram Medical College Hospital",
                 banglaName: "চট্টগ্রাম মেডিকেল কলেজ হাসপাতাল",
                 city: "Chattogram", banglaCity: "চট্টগ্রাম", division: .chattogram),
        Hospital(id: "ctggeneral", name: "Chattogram General Hospital",
                 banglaName: "চট্টগ্রাম জেনারেল হাসপাতাল",
                 city: "Chattogram", banglaCity: "চট্টগ্রাম", division: .chattogram),
        Hospital(id: "coxsbazar", name: "Cox's Bazar Medical College Hospital",
                 banglaName: "কক্সবাজার মেডিকেল কলেজ হাসপাতাল",
                 city: "Cox's Bazar", banglaCity: "কক্সবাজার", division: .chattogram),
        Hospital(id: "cumilla", name: "Cumilla Medical College Hospital",
                 banglaName: "কুমিল্লা মেডিকেল কলেজ হাসপাতাল",
                 city: "Cumilla", banglaCity: "কুমিল্লা", division: .chattogram),
        Hospital(id: "noakhali", name: "Abdul Malek Ukil Medical College Hospital",
                 banglaName: "আব্দুল মালেক উকিল মেডিকেল কলেজ হাসপাতাল",
                 city: "Noakhali", banglaCity: "নোয়াখালী", division: .chattogram),

        // Other divisions
        Hospital(id: "rmch", name: "Rajshahi Medical College Hospital",
                 banglaName: "রাজশাহী মেডিকেল কলেজ হাসপাতাল",
                 city: "Rajshahi", banglaCity: "রাজশাহী", division: .rajshahi),
        Hospital(id: "bogura", name: "Shaheed Ziaur Rahman Medical College Hospital",
                 banglaName: "শহীদ জিয়াউর রহমান মেডিকেল কলেজ হাসপাতাল",
                 city: "Bogura", banglaCity: "বগুড়া", division: .rajshahi),
        Hospital(id: "kmch", name: "Khulna Medical College Hospital",
                 banglaName: "খুলনা মেডিকেল কলেজ হাসপাতাল",
                 city: "Khulna", banglaCity: "খুলনা", division: .khulna),
        Hospital(id: "jashore", name: "Jashore 250 Bed General Hospital",
                 banglaName: "যশোর ২৫০ শয্যা জেনারেল হাসপাতাল",
                 city: "Jashore", banglaCity: "যশোর", division: .khulna),
        Hospital(id: "osmani", name: "Sylhet MAG Osmani Medical College Hospital",
                 banglaName: "সিলেট এম এ জি ওসমানী মেডিকেল কলেজ হাসপাতাল",
                 city: "Sylhet", banglaCity: "সিলেট", division: .sylhet),
        Hospital(id: "sherebangla", name: "Sher-e-Bangla Medical College Hospital",
                 banglaName: "শের-ই-বাংলা মেডিকেল কলেজ হাসপাতাল",
                 city: "Barishal", banglaCity: "বরিশাল", division: .barishal),
        Hospital(id: "rangpur", name: "Rangpur Medical College Hospital",
                 banglaName: "রংপুর মেডিকেল কলেজ হাসপাতাল",
                 city: "Rangpur", banglaCity: "রংপুর", division: .rangpur),
        Hospital(id: "dinajpur", name: "Dinajpur M Abdur Rahim Medical College Hospital",
                 banglaName: "দিনাজপুর এম আব্দুর রহিম মেডিকেল কলেজ হাসপাতাল",
                 city: "Dinajpur", banglaCity: "দিনাজপুর", division: .rangpur),
        Hospital(id: "mmch", name: "Mymensingh Medical College Hospital",
                 banglaName: "ময়মনসিংহ মেডিকেল কলেজ হাসপাতাল",
                 city: "Mymensingh", banglaCity: "ময়মনসিংহ", division: .mymensingh),
    ]

    static func hospitals(in division: Division?) -> [Hospital] {
        guard let division else { return all }
        return all.filter { $0.division == division }
    }
}
