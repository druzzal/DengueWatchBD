import Foundation

extension Strings {
    static let enDashboard: [String: String] = [
        "dash.title": "DengueWatch",
        "dash.season": "Bangladesh, %@ season",
        "dash.updated": "Updated %@",
        "dash.loading": "Loading surveillance data…",
        "dash.error.title": "Surveillance data unavailable",
        "dash.about.a11y": "About this data",

        "dash.stat.cases": "Cases this season",
        "dash.stat.deaths": "Deaths this season",
        "dash.stat.admitted": "In hospital now",
        "dash.stat.cfr": "Case fatality rate",
        "dash.stat.vsLastWeek": "vs last week",
        "dash.stat.vs7days": "vs 7 days ago",
        "dash.stat.cfrCaption": "deaths ÷ reported cases",
        "dash.delta.a11y": "%@ versus the previous week",

        "dash.curve.title": "Epidemic curve",
        "dash.curve.subtitle": "Cases reported to hospitals each day",
        "dash.legend.daily": "Daily reported",
        "dash.legend.average": "7-day average",
        "dash.curve.peak": "Season peak so far: %@ cases on %@.",
        "dash.curve.tooltip.reported": "%@ reported",
        "dash.curve.tooltip.average": "%@ 7-day avg",
        "dash.curve.tooltip.deaths": "%@ deaths reported",

        "dash.admissions.title": "Patients in hospital",
        "dash.admissions.subtitle": "Dengue inpatients on the ward each day",
        "dash.admissions.footnote": "%@ people were on a dengue ward on %@.",

        "dash.deaths.title": "Deaths reported",
        "dash.deaths.subtitle": "Daily, with a 7-day average",

        "dash.history.title": "Season totals since 2019",
        "dash.history.subtitle": "Reported cases per year, nationwide",
        "dash.history.footnote": "2019–2024 are published DGHS annual totals. 2025 and 2026 are simulated for this demo and are drawn with a hatched bar.",
        "dash.history.a11y": "%@: %@ cases, %@ deaths",
        "dash.history.a11ySimulated": "%@: %@ cases, %@ deaths, simulated",

        "dash.watch.title": "Districts to watch",
        "dash.watch.rising": "Rising fastest",
        "dash.watch.hottest": "Highest rate",
        "dash.watch.risingSub": "Biggest week-on-week rise (20+ cases)",
        "dash.watch.hottestSub": "Highest 14-day cases per 100,000 people",
        "dash.watch.empty": "No district crossed the threshold this week.",

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
        "dash.title": "ডেঙ্গুওয়াচ",
        "dash.season": "বাংলাদেশ, %@ মৌসুম",
        "dash.updated": "হালনাগাদ %@",
        "dash.loading": "তথ্য লোড হচ্ছে…",
        "dash.error.title": "নজরদারির তথ্য পাওয়া যাচ্ছে না",
        "dash.about.a11y": "এই তথ্য সম্পর্কে",

        "dash.stat.cases": "এ মৌসুমে আক্রান্ত",
        "dash.stat.deaths": "এ মৌসুমে মৃত্যু",
        "dash.stat.admitted": "এখন হাসপাতালে",
        "dash.stat.cfr": "মৃত্যুহার",
        "dash.stat.vsLastWeek": "গত সপ্তাহের তুলনায়",
        "dash.stat.vs7days": "৭ দিন আগের তুলনায়",
        "dash.stat.cfrCaption": "মৃত্যু ÷ শনাক্ত রোগী",
        "dash.delta.a11y": "গত সপ্তাহের তুলনায় %@",

        "dash.curve.title": "সংক্রমণ বক্ররেখা",
        "dash.curve.subtitle": "প্রতিদিন হাসপাতালে ভর্তি হওয়া রোগী",
        "dash.legend.daily": "দৈনিক শনাক্ত",
        "dash.legend.average": "৭ দিনের গড়",
        "dash.curve.peak": "এ মৌসুমের সর্বোচ্চ: %@ জন, %@ তারিখে।",
        "dash.curve.tooltip.reported": "%@ জন শনাক্ত",
        "dash.curve.tooltip.average": "%@ — ৭ দিনের গড়",
        "dash.curve.tooltip.deaths": "%@ জনের মৃত্যু",

        "dash.admissions.title": "হাসপাতালে ভর্তি রোগী",
        "dash.admissions.subtitle": "প্রতিদিন ওয়ার্ডে থাকা ডেঙ্গু রোগীর সংখ্যা",
        "dash.admissions.footnote": "%@ তারিখে %@ জন ডেঙ্গু ওয়ার্ডে ছিলেন।",

        "dash.deaths.title": "মৃত্যুর সংখ্যা",
        "dash.deaths.subtitle": "দৈনিক, সঙ্গে ৭ দিনের গড়",

        "dash.history.title": "২০১৯ সাল থেকে মৌসুমভিত্তিক মোট",
        "dash.history.subtitle": "সারা দেশে বছরপ্রতি শনাক্ত রোগী",
        "dash.history.footnote": "২০১৯–২০২৪ সালের সংখ্যা স্বাস্থ্য অধিদপ্তরের প্রকাশিত বার্ষিক হিসাব। ২০২৫ ও ২০২৬ এই ডেমোর জন্য অনুকরণ করা, তাই দাগকাটা বারে দেখানো হয়েছে।",
        "dash.history.a11y": "%@: %@ জন আক্রান্ত, %@ জনের মৃত্যু",
        "dash.history.a11ySimulated": "%@: %@ জন আক্রান্ত, %@ জনের মৃত্যু, অনুকরণ করা",

        "dash.watch.title": "যেসব জেলায় নজর রাখা দরকার",
        "dash.watch.rising": "দ্রুত বাড়ছে",
        "dash.watch.hottest": "সর্বোচ্চ হার",
        "dash.watch.risingSub": "সপ্তাহে সবচেয়ে বেশি বৃদ্ধি (২০+ রোগী)",
        "dash.watch.hottestSub": "১৪ দিনে প্রতি লাখে সর্বোচ্চ রোগী",
        "dash.watch.empty": "এ সপ্তাহে কোনো জেলা সীমা অতিক্রম করেনি।",

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
