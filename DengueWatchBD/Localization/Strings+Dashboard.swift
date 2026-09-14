import Foundation

extension Strings {
    static let enDashboard: [String: String] = [
        // My health
        "health.title": "My health",
        "health.empty": "Track your symptoms and understand when to seek care.",
        "health.check": "Check symptoms",
        "health.checkAgain": "Check again",
        "health.checkedAt": "Checked %@",

        // Top areas
        "top.title": "Top areas",
        "top.subtitle": "Highest 14-day rate per 100,000 people",
        "top.rate": "%@ per 100,000",
        "top.viewMap": "View map",

        // What changed — deterministic surveillance statements
        "digest.title": "What changed",
        "digest.subtitle": "Since the last DGHS report",
        "digest.national.rise": "Reported cases rose %@%% nationwide this week.",
        "digest.national.fall": "Reported cases fell %@%% nationwide this week.",
        "digest.national.steady": "Reported cases held roughly steady nationwide this week.",
        "digest.hotspots.one": "One area is at high risk or above.",
        "digest.hotspots.many": "%@ areas are at high risk or above.",
        "digest.rises.one": "The steepest rise was in %@.",
        "digest.rises.two": "The steepest rises were in %@ and %@.",
        "digest.noBreakdown": "Area-level figures were not in this report.",
        "digest.action": "See surveillance",

        "who.title": "Who is affected",
        "who.subtitle": "Reported cases this season, by age and sex",
        "who.male": "Male",
        "who.female": "Female",
        "who.share": "%@%%",
        "who.a11y": "Ages %@: %@ male, %@ female",
        "risk.card.hereNow": "%@, where you are now",
        // DGHS reports ten areas for the whole country, so a located reading is
        // an average over a division, not a neighbourhood.
        "risk.card.covers": "A single figure for this whole area — about %@ people",
        "dash.stat.last24": "Last 24 hours",
        "dash.stat.last24Deaths": "%@ deaths",
        "dash.title": "DengueWatch",
        "dash.error.title": "Dengue data unavailable",
        "dash.about.a11y": "About this data",

        "dash.stat.cases": "Cases this season",
        "dash.stat.seasonDeaths": "Deaths this season",
        "dash.stat.vsLastWeek": "vs last week",
        "dash.delta.a11y": "%@ versus the previous week",

        "dash.legend.daily": "Daily reported",
        "dash.legend.average": "7-day average",


        "dash.deaths.title": "Deaths reported",
        "dash.deaths.subtitle": "Daily, with a 7-day average",

        "dash.history.title": "Season totals since 2018",
        "dash.history.subtitle": "Reported cases per year, nationwide",
        "dash.history.footnote": "Every year here is a published DGHS annual total. Deaths are shown only for the current season — the feed carries no yearly death total for earlier years.",
        "dash.history.a11y": "%@: %@ cases, %@ deaths",


        "dash.home.detail": "%@ cases in the last 7 days · %@ per 100k over 14 days",

        "sync.updating": "Updating…",
        "sync.justUpdated": "Data updated",
        "sync.offline": "Offline — showing the last data downloaded",
        "sync.failed": "Could not reach the data server. Showing the last data downloaded.",
        "sync.bundled": "Using the dataset shipped with the app",
        "sync.lastChecked": "Last checked %@",
        "sync.checkNow": "Check for updates now",
    ]

    static let bnDashboard: [String: String] = [
        // আমার স্বাস্থ্য
        "health.title": "আমার স্বাস্থ্য",
        "health.empty": "উপসর্গ লিখে রাখুন, কখন চিকিৎসা নিতে হবে বুঝে নিন।",
        "health.check": "উপসর্গ পরীক্ষা করুন",
        "health.checkAgain": "আবার পরীক্ষা করুন",
        "health.checkedAt": "%@ পরীক্ষা করা হয়েছে",

        // শীর্ষ এলাকা
        "top.title": "শীর্ষ এলাকা",
        "top.subtitle": "প্রতি লাখে ১৪ দিনের সর্বোচ্চ হার",
        "top.rate": "প্রতি লাখে %@",
        "top.viewMap": "মানচিত্র দেখুন",

        // What changed
        "digest.title": "কী বদলাল",
        "digest.subtitle": "স্বাস্থ্য অধিদপ্তরের গত প্রতিবেদনের পর",
        "digest.national.rise": "এ সপ্তাহে সারা দেশে শনাক্ত রোগী %@%% বেড়েছে।",
        "digest.national.fall": "এ সপ্তাহে সারা দেশে শনাক্ত রোগী %@%% কমেছে।",
        "digest.national.steady": "এ সপ্তাহে সারা দেশে শনাক্ত রোগীর সংখ্যা প্রায় অপরিবর্তিত।",
        "digest.hotspots.one": "একটি এলাকা উচ্চ বা তার বেশি ঝুঁকিতে আছে।",
        "digest.hotspots.many": "%@টি এলাকা উচ্চ বা তার বেশি ঝুঁকিতে আছে।",
        "digest.rises.one": "সবচেয়ে বেশি বেড়েছে %@-এ।",
        "digest.rises.two": "সবচেয়ে বেশি বেড়েছে %@ ও %@-এ।",
        "digest.noBreakdown": "এই প্রতিবেদনে এলাকাভিত্তিক তথ্য ছিল না।",
        "digest.action": "নজরদারি দেখুন",

        "who.title": "কারা আক্রান্ত হচ্ছেন",
        "who.subtitle": "এ মৌসুমে বয়স ও লিঙ্গ অনুযায়ী শনাক্ত রোগী",
        "who.male": "পুরুষ",
        "who.female": "নারী",
        "who.share": "%@%%",
        "who.a11y": "%@ বছর: %@ জন পুরুষ, %@ জন নারী",
        "risk.card.hereNow": "%@, আপনি এখন যেখানে আছেন",
        "risk.card.covers": "পুরো এলাকার জন্য একটিই হিসাব — প্রায় %@ মানুষ",
        "dash.stat.last24": "গত ২৪ ঘণ্টা",
        "dash.stat.last24Deaths": "%@ জন মৃত্যু",
        "dash.title": "ডেঙ্গুওয়াচ",
        "dash.error.title": "নজরদারির তথ্য পাওয়া যাচ্ছে না",
        "dash.about.a11y": "এই তথ্য সম্পর্কে",

        "dash.stat.cases": "এ মৌসুমে আক্রান্ত",
        "dash.stat.seasonDeaths": "এ মৌসুমে মৃত্যু",
        "dash.stat.vsLastWeek": "গত সপ্তাহের তুলনায়",
        "dash.delta.a11y": "গত সপ্তাহের তুলনায় %@",

        "dash.legend.daily": "দৈনিক শনাক্ত",
        "dash.legend.average": "৭ দিনের গড়",


        "dash.deaths.title": "মৃত্যুর সংখ্যা",
        "dash.deaths.subtitle": "দৈনিক, সঙ্গে ৭ দিনের গড়",

        "dash.history.title": "২০১৮ সাল থেকে মৌসুমভিত্তিক মোট",
        "dash.history.subtitle": "সারা দেশে বছরপ্রতি শনাক্ত রোগী",
        "dash.history.footnote": "এখানকার প্রতিটি বছরের সংখ্যাই স্বাস্থ্য অধিদপ্তরের প্রকাশিত বার্ষিক হিসাব। মৃত্যুর সংখ্যা কেবল চলতি মৌসুমের জন্য দেখানো হয়েছে — আগের বছরগুলোর বার্ষিক মৃত্যুর হিসাব এই ফিডে নেই।",
        "dash.history.a11y": "%@: %@ জন আক্রান্ত, %@ জনের মৃত্যু",


        "dash.home.detail": "গত ৭ দিনে %@ জন · ১৪ দিনে প্রতি লাখে %@",

        "sync.updating": "হালনাগাদ হচ্ছে…",
        "sync.justUpdated": "তথ্য হালনাগাদ হয়েছে",
        "sync.offline": "অফলাইন — সর্বশেষ নামানো তথ্য দেখানো হচ্ছে",
        "sync.failed": "সার্ভারে পৌঁছানো যায়নি। সর্বশেষ নামানো তথ্য দেখানো হচ্ছে।",
        "sync.bundled": "অ্যাপের সঙ্গে দেওয়া তথ্য ব্যবহার করা হচ্ছে",
        "sync.lastChecked": "সর্বশেষ যাচাই %@",
        "sync.checkNow": "এখনই হালনাগাদ খুঁজুন",
    ]
}
