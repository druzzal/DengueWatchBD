import Foundation

/// The WHO care plan, the fever timeline and the fluid log.
///
/// The clinical content is WHO's, not the app's: who goes to hospital and what
/// is advised at home come from *Guidelines for clinical management of
/// arboviral diseases: dengue, chikungunya, Zika and yellow fever* (2025),
/// sections 2.6 and 4. Wording is plain language rather than the guideline's
/// own register, but no advice is added to it and none is softened — the NSAID
/// warning in particular is stated as flatly as WHO states it, and doses are
/// left to the pharmacist and the pack.
extension Strings {
    static let enWHO: [String: String] = [
        "who.plan.title": "WHO care plan",
        "who.plan.checkedAt": "From your symptom check on %@",
        "who.plan.stale": "This is from an older check. Dengue changes day by day — run the check again so this reflects how you are now.",
        // Shown beside the lab line, which is the one place a reader might
        // otherwise assume their blood count moved the group. It did not.
        "care.plan.note": "This plan follows your symptom check and the readings you took, not your lab results. Your doctor reads the lab report.",
        "who.plan.becauseTitle": "Why this advice",
        "who.plan.measuredNote": "Readings you take at home are not a substitute for being examined. If you feel worse than the numbers suggest, go anyway.",
        "who.plan.source": "Based on WHO's 2025 guidelines for the clinical management of arboviral diseases. “Care at home” is WHO's non-severe group; “Hospital today” and “Emergency care now” are its severe group, which needs hospital care. This app matches what you recorded against that guidance. It does not decide whether you have dengue.",

        // Group A
        "who.group.home.title": "Care at home",
        "who.group.home.detail": "On your answers, WHO's guidance is that this is not severe for now and can be managed at home, with someone checking each day.",
        "who.group.home.advice1": "Drink often, in small amounts. Measure each drink with a cup and log it in Fluids today, so the day's total can be checked.",
        "who.group.home.advice2": "Aim to pass urine at least 4 to 6 times a day. Mostly water; oral rehydration salts, soup, coconut water, rice water or yoghurt drinks help too. Avoid fizzy drinks, packaged juice and sweetened tea.",
        "who.group.home.advice3": "For fever and pain, paracetamol only — carefully if you have liver disease. No aspirin, ibuprofen, diclofenac or other NSAIDs. If you take aspirin every day for your heart, ask your doctor before stopping.",
        "who.group.home.advice4": "No steroids for dengue unless a doctor treating you prescribes them.",

        // Group B
        "who.group.referral.title": "Hospital today",
        "who.group.referral.detail": "On your answers, WHO's guidance is that you should be assessed in hospital today rather than cared for at home.",
        "who.group.referral.advice1": "Go to a hospital today. Take this record and any lab reports with you.",
        "who.group.referral.advice2": "Keep drinking fluids on the way, unless you are vomiting.",
        "who.group.referral.advice3": "Paracetamol only. No aspirin, ibuprofen or other NSAIDs, and no steroids unless the hospital prescribes them.",
        "who.group.referral.advice4": "Ask for a full blood count. A falling platelet count alongside a rising haematocrit is what the doctor is watching for.",

        // Group C
        "who.group.emergency.title": "Emergency care now",
        "who.group.emergency.detail": "On your answers, WHO's guidance is that these signs need emergency treatment without delay.",
        "who.group.emergency.advice1": "Go to the nearest emergency department now, or call 999 for an ambulance.",
        "who.group.emergency.advice2": "Do not wait for the fever to return or for a test result.",
        "who.group.emergency.advice3": "Take someone with you if you can, and bring this record.",

        // Why
        "who.reason.severeSign": "You reported a sign of severe dengue.",
        "who.reason.warningSign": "You reported a warning sign.",
        "who.reason.criticalPhase": "You are in the critical phase — days 4 to 7, when plasma leak begins.",
        "who.reason.narrowPulsePressure": "Your last blood pressure had a narrow gap between the two numbers, 20 mmHg or less.",
        "who.reason.lowBloodPressure": "Your last blood pressure was under 90 on the upper number.",
        "who.reason.fastPulse": "Your last pulse was over 120.",
        "who.reason.lowOxygen": "Your last oxygen reading was under 94%.",
        "who.reason.noneOfThese": "No warning signs, and no reading outside the range WHO names.",

        // Fever timeline
        "fever.timeline.title": "Fever timeline",
        "fever.timeline.subtitle": "Dengue turns dangerous as the fever settles",
        "fever.timeline.day": "Day %@",
        "fever.timeline.note": "The critical phase is days 4 to 7, around the time the fever drops. Feeling better then does not mean the danger has passed.",

        "who.group.home.advice5": "Rest, and have someone check on you every day, above all on days 4 to 7. Go to hospital straight away for any warning sign: belly pain, repeated vomiting, being unable to drink, bleeding, unusual sleepiness or restlessness, or passing much less urine.",
        "who.reason.pregnancy": "You are pregnant. WHO lists pregnancy on its own as a reason for hospital care in dengue.",
        "who.reason.higherRiskGroup": "You are under 5 or over 60, or have a long-term condition. WHO leaves admission to the clinician for these groups, so be seen today.",
        "who.reason.previousDengue": "You have had dengue before. A second infection can be more severe, so watch closely — on its own this does not change the advice.",
        "care.plan.haematocritRising": "Your haematocrit has gone up on each of your last two lab reports. WHO lists a rising haematocrit among the reasons doctors admit someone with dengue — show these reports to a doctor today.",
        "fluid.section": "Fluids today",
        "fluid.subtitle": "WHO advises measuring what you drink while you are ill",
        "fluid.drunk": "Fluid intake",
        "fluid.drinks": "Drinks",
        "fluid.urine": "Passed urine",
        "fluid.unit.ml": "ml",
        "fluid.unit.times": "times",
        "fluid.urine.aim": "Aim: at least %@–%@ a day",
        "fluid.urine.gap": "No urine logged for over %@ waking hours. If you really have not passed urine, that is a warning sign — contact a doctor today.",
        "fluid.addDrink": "Add a drink",
        "fluid.addUrine": "Passed urine",
        "fluid.todayEntries": "Today's entries (%@)",
        "fluid.whatToDrink": "Mostly water. Oral rehydration salts, soup, coconut water, rice water and yoghurt drinks count too. Avoid fizzy drinks, packaged juice and sweetened tea.",
        "fluid.add.title": "Add to fluid log",
        "fluid.kind.drink": "Drink",
        "fluid.amount": "How much",
        "fluid.amount.footer": "Measure your usual cup or glass once — with a marked bottle, for example — then use that amount each time.",
        "fluid.when": "When",
        "fluid.log.title": "Fluids",
    ]

    static let bnWHO: [String: String] = [
        "who.plan.title": "বিশ্ব স্বাস্থ্য সংস্থার পরামর্শ",
        "who.plan.checkedAt": "%@ তারিখের উপসর্গ পরীক্ষা থেকে",
        "who.plan.stale": "এটি আগের একটি পরীক্ষার ফল। ডেঙ্গু দিনে দিনে বদলায় — এখন কেমন আছেন তা জানতে আবার পরীক্ষা করুন।",
        "care.plan.note": "এই পরামর্শ আপনার উপসর্গ পরীক্ষা ও নেওয়া পরিমাপ অনুযায়ী, ল্যাব রিপোর্ট অনুযায়ী নয়। ল্যাব রিপোর্ট আপনার ডাক্তার দেখবেন।",
        "who.plan.becauseTitle": "কেন এই পরামর্শ",
        "who.plan.measuredNote": "বাড়িতে নেওয়া পরিমাপ ডাক্তারের পরীক্ষার বিকল্প নয়। সংখ্যায় যা-ই দেখাক, শরীর বেশি খারাপ লাগলে ডাক্তারের কাছে যান।",
        "who.plan.source": "বিশ্ব স্বাস্থ্য সংস্থার ২০২৫ সালের আরবোভাইরাস রোগের চিকিৎসা নির্দেশিকা অনুযায়ী। ‘বাড়িতে যত্ন’ নির্দেশিকার মারাত্মক নয় এমন রোগের দল; ‘আজই হাসপাতালে’ ও ‘এখনই জরুরি চিকিৎসা’ মারাত্মক রোগের দল, যার জন্য হাসপাতালে চিকিৎসা দরকার। অ্যাপটি আপনার লেখা তথ্য ওই নির্দেশিকার সঙ্গে মিলিয়ে দেখায়। ডেঙ্গু হয়েছে কি না, তা এটি ঠিক করে না।",

        "who.group.home.title": "বাড়িতে যত্ন",
        "who.group.home.detail": "আপনার উত্তর অনুযায়ী বিশ্ব স্বাস্থ্য সংস্থার নির্দেশিকা বলে, এখন পর্যন্ত এটি মারাত্মক নয় এবং বাড়িতেই যত্ন নেওয়া যায় — তবে প্রতিদিন কাউকে খোঁজ নিতে হবে।",
        "who.group.home.advice1": "অল্প অল্প করে বারবার পান করুন। প্রতিবার কাপ দিয়ে মেপে ‘আজকের তরল’-এ লিখে রাখুন, যাতে দিনের মোট পরিমাণ দেখা যায়।",
        "who.group.home.advice2": "দিনে অন্তত ৪ থেকে ৬ বার প্রস্রাব হওয়া উচিত। বেশিরভাগ পানি; খাবার স্যালাইন, স্যুপ, ডাবের পানি, চালের মাড়, মাঠা বা ঘোলও চলবে। কোমল পানীয়, প্যাকেটজাত জুস ও চিনি দেওয়া চা এড়িয়ে চলুন।",
        "who.group.home.advice3": "জ্বর ও ব্যথায় শুধু প্যারাসিটামল — লিভারের রোগ থাকলে সাবধানে। অ্যাসপিরিন, আইবুপ্রোফেন, ডাইক্লোফেনাক বা অন্য এনএসএআইডি নয়। হৃদরোগের জন্য প্রতিদিন অ্যাসপিরিন খেলে, বন্ধ করার আগে ডাক্তারকে জিজ্ঞেস করুন।",
        "who.group.home.advice4": "চিকিৎসা করছেন এমন ডাক্তার লিখে না দিলে ডেঙ্গুর জন্য স্টেরয়েড খাবেন না।",

        "who.group.referral.title": "আজই হাসপাতালে",
        "who.group.referral.detail": "আপনার উত্তর অনুযায়ী বিশ্ব স্বাস্থ্য সংস্থার নির্দেশিকা বলে, বাড়িতে না রেখে আজই হাসপাতালে পরীক্ষা করানো দরকার।",
        "who.group.referral.advice1": "আজই হাসপাতালে যান। এই রেকর্ড ও ল্যাব রিপোর্ট সঙ্গে নিন।",
        "who.group.referral.advice2": "বমি না হলে যাওয়ার পথেও তরল খেতে থাকুন।",
        "who.group.referral.advice3": "শুধু প্যারাসিটামল। অ্যাসপিরিন, আইবুপ্রোফেন বা অন্য এনএসএআইডি নয়; হাসপাতাল না দিলে স্টেরয়েডও নয়।",
        "who.group.referral.advice4": "CBC পরীক্ষা করাতে বলুন। Platelet কমছে অথচ Haematocrit বাড়ছে কি না — ডাক্তার সেটিই দেখবেন।",

        "who.group.emergency.title": "এখনই জরুরি চিকিৎসা",
        "who.group.emergency.detail": "আপনার উত্তর অনুযায়ী বিশ্ব স্বাস্থ্য সংস্থার নির্দেশিকা বলে, এই লক্ষণে দেরি না করে জরুরি চিকিৎসা দরকার।",
        "who.group.emergency.advice1": "এখনই কাছের হাসপাতালের জরুরি বিভাগে যান, বা অ্যাম্বুলেন্সের জন্য ৯৯৯ নম্বরে ফোন করুন।",
        "who.group.emergency.advice2": "জ্বর আবার আসার বা পরীক্ষার ফল আসার অপেক্ষা করবেন না।",
        "who.group.emergency.advice3": "পারলে কাউকে সঙ্গে নিন, আর এই রেকর্ড সঙ্গে নিন।",

        "who.reason.severeSign": "আপনি মারাত্মক ডেঙ্গুর একটি লক্ষণ জানিয়েছেন।",
        "who.reason.warningSign": "আপনি একটি বিপদচিহ্ন জানিয়েছেন।",
        "who.reason.criticalPhase": "আপনি সংকটকালে আছেন — ৪ থেকে ৭ দিন, যখন রক্তরস বেরিয়ে যেতে শুরু করে।",
        "who.reason.narrowPulsePressure": "আপনার শেষ রক্তচাপে উপরের ও নিচের সংখ্যার ব্যবধান কম ছিল — ২০ বা তার কম।",
        "who.reason.lowBloodPressure": "আপনার শেষ রক্তচাপের উপরের সংখ্যা ৯০-এর নিচে ছিল।",
        "who.reason.fastPulse": "আপনার শেষ নাড়ির গতি ১২০-এর বেশি ছিল।",
        "who.reason.lowOxygen": "আপনার শেষ অক্সিজেনের মাত্রা ৯৪%-এর নিচে ছিল।",
        "who.reason.noneOfThese": "কোনো বিপদচিহ্ন নেই, আর কোনো পরিমাপও বিশ্ব স্বাস্থ্য সংস্থার বলা সীমার বাইরে নয়।",

        "fever.timeline.title": "জ্বরের সময়রেখা",
        "fever.timeline.subtitle": "জ্বর নামার সময়েই ডেঙ্গু বেশি বিপজ্জনক হয়",
        "fever.timeline.day": "দিন %@",
        "fever.timeline.note": "সংকটকাল জ্বরের ৪ থেকে ৭ দিন — সাধারণত যখন জ্বর নামতে শুরু করে। তখন ভালো লাগা মানেই বিপদ কেটে যাওয়া নয়।",

        "who.group.home.advice5": "বিশ্রাম নিন, আর প্রতিদিন কেউ একজন খোঁজ নিক — বিশেষ করে জ্বরের ৪ থেকে ৭ দিনে। যেকোনো বিপদচিহ্ন দেখা দিলে সঙ্গে সঙ্গে হাসপাতালে যান: পেটে ব্যথা, বারবার বমি, কিছু পান করতে না পারা, রক্তক্ষরণ, অস্বাভাবিক ঘুম ঘুম ভাব বা অস্থিরতা, বা প্রস্রাব অনেক কমে যাওয়া।",
        "who.reason.pregnancy": "আপনি গর্ভবতী। ডেঙ্গুতে শুধু গর্ভাবস্থাকেই হাসপাতালে চিকিৎসার একটি কারণ হিসেবে ধরে বিশ্ব স্বাস্থ্য সংস্থা।",
        "who.reason.higherRiskGroup": "আপনার বয়স ৫ বছরের কম বা ৬০ বছরের বেশি, বা আপনার দীর্ঘমেয়াদি কোনো রোগ আছে। এ ক্ষেত্রে ভর্তির সিদ্ধান্ত বিশ্ব স্বাস্থ্য সংস্থা চিকিৎসকের ওপর ছেড়ে দেয়, তাই আজই দেখান।",
        "who.reason.previousDengue": "আপনার আগে ডেঙ্গু হয়েছিল। দ্বিতীয়বারের সংক্রমণ বেশি মারাত্মক হতে পারে, তাই কাছ থেকে নজর রাখুন — শুধু এ কারণে পরামর্শ বদলায় না।",
        "care.plan.haematocritRising": "আপনার শেষ দুটি ল্যাব রিপোর্টে পরপর Haematocrit বেড়েছে। ডেঙ্গু রোগীকে ভর্তি করার কারণগুলোর মধ্যে বাড়তে থাকা Haematocrit-কে ধরে বিশ্ব স্বাস্থ্য সংস্থা — আজই রিপোর্টগুলো ডাক্তারকে দেখান।",
        "fluid.section": "আজকের তরল",
        "fluid.subtitle": "অসুস্থ থাকার সময় কতটা পান করছেন তা মেপে রাখার পরামর্শ দেয় বিশ্ব স্বাস্থ্য সংস্থা",
        "fluid.drunk": "মোট পান",
        "fluid.drinks": "কতবার পান",
        "fluid.urine": "প্রস্রাব",
        "fluid.unit.ml": "মিলি",
        "fluid.unit.times": "বার",
        "fluid.urine.aim": "লক্ষ্য: দিনে অন্তত %@–%@ বার",
        "fluid.urine.gap": "জেগে থাকার সময়ে %@ ঘণ্টার বেশি কোনো প্রস্রাব লেখা হয়নি। সত্যিই প্রস্রাব না হয়ে থাকলে এটি একটি বিপদচিহ্ন — আজই ডাক্তারের সঙ্গে যোগাযোগ করুন।",
        "fluid.addDrink": "পানীয় যোগ করুন",
        "fluid.addUrine": "প্রস্রাব হয়েছে",
        "fluid.todayEntries": "আজকের হিসাব (%@)",
        "fluid.whatToDrink": "বেশিরভাগ পানি। খাবার স্যালাইন, স্যুপ, ডাবের পানি, চালের মাড়, মাঠা বা ঘোলও হিসাবে ধরা হবে। কোমল পানীয়, প্যাকেটজাত জুস ও চিনি দেওয়া চা এড়িয়ে চলুন।",
        "fluid.add.title": "তরলের হিসাবে যোগ করুন",
        "fluid.kind.drink": "পানীয়",
        "fluid.amount": "পরিমাণ",
        "fluid.amount.footer": "নিজের কাপ বা গ্লাসটি একবার মেপে নিন — যেমন দাগ কাটা বোতল দিয়ে — তারপর প্রতিবার সেই পরিমাণ ধরুন।",
        "fluid.when": "কখন",
        "fluid.log.title": "তরল",
    ]
}
