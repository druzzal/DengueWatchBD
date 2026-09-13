import Foundation

/// The WHO care plan and the fever timeline.
///
/// The clinical content is WHO's, not the app's: the A / B / C management
/// groups and their advice come from *Dengue: guidelines for diagnosis,
/// treatment, prevention and control* (2009), chapter 2. Wording is plain
/// language rather than the guideline's own register, but no advice is added
/// to it and none is softened — the NSAID warning in particular is stated as
/// flatly as WHO states it.
extension Strings {
    static let enWHO: [String: String] = [
        "who.plan.title": "WHO care plan",
        "who.plan.subtitle": "Your symptom check and readings, matched to WHO's guidance",
        "who.plan.becauseTitle": "Why this group",
        "who.plan.measuredNote": "Readings you take at home are not a substitute for being examined. If you feel worse than the numbers suggest, go anyway.",
        "who.plan.source": "Groups A, B and C are WHO's, from its dengue guidelines. This app matches what you recorded against that guidance. It does not decide whether you have dengue.",

        // Group A
        "who.group.home.title": "Group A — care at home",
        "who.group.home.detail": "On your answers, WHO's guidance is that this can usually be managed at home, with someone checking each day.",
        "who.group.home.advice1": "Drink enough to pass urine at least every six hours — water, oral rehydration salts, rice water, coconut water or soup.",
        "who.group.home.advice2": "Paracetamol only, for fever and pain. No aspirin, ibuprofen or other anti-inflammatory painkillers: they raise the risk of bleeding.",
        "who.group.home.advice3": "Rest, and have someone look in on you every day — above all between day 3 and day 7.",
        "who.group.home.advice4": "Go to hospital straight away if a warning sign appears: belly pain, repeated vomiting, bleeding, restlessness, or passing much less urine.",

        // Group B
        "who.group.referral.title": "Group B — be seen at a hospital",
        "who.group.referral.detail": "On your answers, WHO's guidance is that this should be assessed in hospital rather than at home.",
        "who.group.referral.advice1": "Go to a hospital today. Take this record and any lab reports with you.",
        "who.group.referral.advice2": "Keep drinking fluids on the way, unless you are vomiting.",
        "who.group.referral.advice3": "Paracetamol only. No aspirin or ibuprofen.",
        "who.group.referral.advice4": "Ask for a full blood count. A falling platelet count alongside a rising haematocrit is what the doctor is watching for.",

        // Group C
        "who.group.emergency.title": "Group C — emergency care now",
        "who.group.emergency.detail": "On your answers, WHO's guidance is that these signs need emergency treatment without delay.",
        "who.group.emergency.advice1": "Go to the nearest emergency department now, or call 999 for an ambulance.",
        "who.group.emergency.advice2": "Do not wait for the fever to return or for a test result.",
        "who.group.emergency.advice3": "Take someone with you if you can, and bring this record.",

        // Why
        "who.reason.severeSign": "You reported a sign of severe dengue.",
        "who.reason.warningSign": "You reported a warning sign.",
        "who.reason.coMorbidity": "You have a condition WHO counts as higher risk.",
        "who.reason.criticalPhase": "You are in the critical phase — days 4 to 6, when plasma leak begins.",
        "who.reason.narrowPulsePressure": "Your last blood pressure had a narrow gap between the two numbers, 20 mmHg or less.",
        "who.reason.lowBloodPressure": "Your last blood pressure was under 90 on the upper number.",
        "who.reason.fastPulse": "Your last pulse was over 120.",
        "who.reason.lowOxygen": "Your last oxygen reading was under 94%.",
        "who.reason.noneOfThese": "No warning signs, and no reading outside the range WHO names.",

        // Fever timeline
        "fever.timeline.title": "Fever timeline",
        "fever.timeline.subtitle": "Dengue turns dangerous as the fever settles",
        "fever.timeline.day": "Day %@",
        "fever.timeline.note": "The critical phase is days 4 to 6, around the time the fever drops. Feeling better then does not mean the danger has passed.",
    ]

    static let bnWHO: [String: String] = [
        "who.plan.title": "বিশ্ব স্বাস্থ্য সংস্থার পরামর্শ",
        "who.plan.subtitle": "আপনার উপসর্গ পরীক্ষা ও পরিমাপ বিশ্ব স্বাস্থ্য সংস্থার নির্দেশিকার সঙ্গে মিলিয়ে",
        "who.plan.becauseTitle": "কেন এই ধাপ",
        "who.plan.measuredNote": "বাড়িতে নেওয়া পরিমাপ ডাক্তারের পরীক্ষার বিকল্প নয়। সংখ্যায় যা-ই দেখাক, শরীর বেশি খারাপ লাগলে ডাক্তারের কাছে যান।",
        "who.plan.source": "A, B ও C ধাপ বিশ্ব স্বাস্থ্য সংস্থার ডেঙ্গু নির্দেশিকার। অ্যাপটি আপনার লেখা তথ্য ওই নির্দেশিকার সঙ্গে মিলিয়ে দেখায়। ডেঙ্গু হয়েছে কি না, তা এটি ঠিক করে না।",

        "who.group.home.title": "ধাপ A — বাড়িতে যত্ন",
        "who.group.home.detail": "আপনার উত্তর অনুযায়ী বিশ্ব স্বাস্থ্য সংস্থার নির্দেশিকা বলে, সাধারণত বাড়িতেই যত্ন নেওয়া যায় — তবে প্রতিদিন কাউকে খোঁজ নিতে হবে।",
        "who.group.home.advice1": "এত তরল খান যেন অন্তত ছয় ঘণ্টায় একবার প্রস্রাব হয় — পানি, খাবার স্যালাইন, চালের মাড়, ডাবের পানি বা স্যুপ।",
        "who.group.home.advice2": "জ্বর ও ব্যথায় শুধু প্যারাসিটামল। অ্যাসপিরিন, আইবুপ্রোফেন বা এ ধরনের ব্যথানাশক নয় — এতে রক্তক্ষরণের ঝুঁকি বাড়ে।",
        "who.group.home.advice3": "বিশ্রাম নিন, আর প্রতিদিন কেউ একজন খোঁজ নিক — বিশেষ করে জ্বরের ৩ থেকে ৭ দিনের মধ্যে।",
        "who.group.home.advice4": "বিপদচিহ্ন দেখা দিলে সঙ্গে সঙ্গে হাসপাতালে যান: পেটে ব্যথা, বারবার বমি, রক্তক্ষরণ, ছটফট করা, বা প্রস্রাব অনেক কমে যাওয়া।",

        "who.group.referral.title": "ধাপ B — হাসপাতালে দেখান",
        "who.group.referral.detail": "আপনার উত্তর অনুযায়ী বিশ্ব স্বাস্থ্য সংস্থার নির্দেশিকা বলে, বাড়িতে না রেখে হাসপাতালে পরীক্ষা করানো দরকার।",
        "who.group.referral.advice1": "আজই হাসপাতালে যান। এই হিসাব ও ল্যাব রিপোর্ট সঙ্গে নিন।",
        "who.group.referral.advice2": "বমি না হলে যাওয়ার পথেও তরল খেতে থাকুন।",
        "who.group.referral.advice3": "শুধু প্যারাসিটামল। অ্যাসপিরিন বা আইবুপ্রোফেন নয়।",
        "who.group.referral.advice4": "রক্তের সিবিসি পরীক্ষা করাতে বলুন। প্লেটলেট কমছে অথচ হেমাটোক্রিট বাড়ছে কি না — ডাক্তার সেটিই দেখবেন।",

        "who.group.emergency.title": "ধাপ C — এখনই জরুরি চিকিৎসা",
        "who.group.emergency.detail": "আপনার উত্তর অনুযায়ী বিশ্ব স্বাস্থ্য সংস্থার নির্দেশিকা বলে, এই লক্ষণে দেরি না করে জরুরি চিকিৎসা দরকার।",
        "who.group.emergency.advice1": "এখনই কাছের হাসপাতালের জরুরি বিভাগে যান, বা অ্যাম্বুলেন্সের জন্য ৯৯৯ নম্বরে ফোন করুন।",
        "who.group.emergency.advice2": "জ্বর আবার আসার বা পরীক্ষার ফল আসার অপেক্ষা করবেন না।",
        "who.group.emergency.advice3": "পারলে কাউকে সঙ্গে নিন, আর এই হিসাব সঙ্গে রাখুন।",

        "who.reason.severeSign": "আপনি মারাত্মক ডেঙ্গুর একটি লক্ষণ জানিয়েছেন।",
        "who.reason.warningSign": "আপনি একটি বিপদচিহ্ন জানিয়েছেন।",
        "who.reason.coMorbidity": "আপনার এমন একটি অবস্থা আছে, যাকে বিশ্ব স্বাস্থ্য সংস্থা বাড়তি ঝুঁকি ধরে।",
        "who.reason.criticalPhase": "আপনি সংকটকালে আছেন — ৪ থেকে ৬ দিন, যখন রক্তরস বেরিয়ে যেতে শুরু করে।",
        "who.reason.narrowPulsePressure": "আপনার শেষ রক্তচাপে উপরের ও নিচের সংখ্যার ব্যবধান কম ছিল — ২০ বা তার কম।",
        "who.reason.lowBloodPressure": "আপনার শেষ রক্তচাপের উপরের সংখ্যা ৯০-এর নিচে ছিল।",
        "who.reason.fastPulse": "আপনার শেষ নাড়ির গতি ১২০-এর বেশি ছিল।",
        "who.reason.lowOxygen": "আপনার শেষ অক্সিজেনের মাত্রা ৯৪%-এর নিচে ছিল।",
        "who.reason.noneOfThese": "কোনো বিপদচিহ্ন নেই, আর কোনো পরিমাপও বিশ্ব স্বাস্থ্য সংস্থার বলা সীমার বাইরে নয়।",

        "fever.timeline.title": "জ্বরের সময়রেখা",
        "fever.timeline.subtitle": "জ্বর নামার সময়েই ডেঙ্গু বেশি বিপজ্জনক হয়",
        "fever.timeline.day": "দিন %@",
        "fever.timeline.note": "সংকটকাল জ্বরের ৪ থেকে ৬ দিন — সাধারণত যখন জ্বর নামতে শুরু করে। তখন ভালো লাগা মানেই বিপদ কেটে যাওয়া নয়।",
    ]
}
