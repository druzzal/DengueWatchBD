import Foundation

/// A belief that is common in Bangladesh and the fact that corrects it.
///
/// Each entry exists because the myth causes a specific harm — someone stops
/// watching, delays care, or takes something that makes bleeding worse. The
/// facts restate what the app already says elsewhere rather than introducing
/// new clinical claims: the fever-falls warning, the daylight biting, the
/// hospital-only counting. Nothing here is novel advice.
struct MythFact: Identifiable, Hashable {
    let id: String

    var mythKey: String { "myth.\(id).myth" }
    var factKey: String { "myth.\(id).fact" }

    static let all: [MythFact] = [
        // The most dangerous belief in dengue, and the reason the fever
        // timeline exists at all.
        MythFact(id: "feverGone"),
        // Drives people to buy papaya extract instead of seeking review.
        MythFact(id: "papaya"),
        // Leads to nets at night and bare arms at dawn.
        MythFact(id: "nightOnly"),
        // A second infection is more dangerous, not less.
        MythFact(id: "onceOnly"),
        // Sends families chasing a number instead of watching the person.
        MythFact(id: "platelets"),
        // The one that turns a survivable illness into a bleed.
        MythFact(id: "painkillers"),
    ]
}
