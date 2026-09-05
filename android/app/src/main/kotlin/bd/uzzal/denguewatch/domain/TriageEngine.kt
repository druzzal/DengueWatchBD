package bd.uzzal.denguewatch.domain

/**
 * The symptom check. A direct port of the iOS engine: same symptom ids, same
 * grouping, same escalation order, so both apps give one person the same
 * advice.
 *
 * Ordering is the safety property. Severe outranks warning, warning outranks
 * core, and adding a symptom can never lower the outcome.
 */
enum class SymptomGroup { CORE, WARNING, SEVERE }

data class Symptom(val id: String, val group: SymptomGroup)

enum class TriageOutcome {
    SELF_CARE, TEST_ADVISED, SEE_DOCTOR_TODAY, EMERGENCY;

    /** Matches the iOS string-table slugs so both apps share the copy keys. */
    val slug: String
        get() = when (this) {
            SELF_CARE -> "selfCare"
            TEST_ADVISED -> "testAdvised"
            SEE_DOCTOR_TODAY -> "seeDoctor"
            EMERGENCY -> "emergency"
        }
}

object TriageEngine {

    /** Higher-risk groups per WHO guidance; they lift a borderline result. */
    data class Context(
        val feverDaysAgo: Int? = null,
        val isPregnant: Boolean = false,
        val isUnderFiveOrOverSixty: Boolean = false,
        val hasChronicCondition: Boolean = false,
        val hadDengueBefore: Boolean = false,
    ) {
        val hasCoMorbidity: Boolean
            get() = isPregnant || isUnderFiveOrOverSixty || hasChronicCondition || hadDengueBefore
    }

    val symptoms: List<Symptom> = listOf(
        Symptom("fever", SymptomGroup.CORE),
        Symptom("headache", SymptomGroup.CORE),
        Symptom("aches", SymptomGroup.CORE),
        Symptom("rash", SymptomGroup.CORE),
        Symptom("nausea", SymptomGroup.CORE),
        Symptom("abdominal", SymptomGroup.WARNING),
        Symptom("vomiting", SymptomGroup.WARNING),
        Symptom("bleeding", SymptomGroup.WARNING),
        Symptom("fatigue", SymptomGroup.WARNING),
        Symptom("fluid", SymptomGroup.WARNING),
        Symptom("noUrine", SymptomGroup.WARNING),
        Symptom("faint", SymptomGroup.SEVERE),
        Symptom("confusion", SymptomGroup.SEVERE),
        Symptom("heavyBleed", SymptomGroup.SEVERE),
    )

    fun symptoms(group: SymptomGroup): List<Symptom> = symptoms.filter { it.group == group }

    fun symptom(id: String): Symptom? = symptoms.firstOrNull { it.id == id }

    fun evaluate(selected: Set<String>, context: Context): TriageOutcome {
        val chosen = symptoms.filter { selected.contains(it.id) }
        if (chosen.any { it.group == SymptomGroup.SEVERE }) return TriageOutcome.EMERGENCY

        val warnings = chosen.count { it.group == SymptomGroup.WARNING }
        if (warnings >= 1) return TriageOutcome.SEE_DOCTOR_TODAY

        val core = chosen.count { it.group == SymptomGroup.CORE }
        val hasFever = selected.contains("fever")

        if (hasFever && core >= 2) {
            return if (context.hasCoMorbidity) TriageOutcome.SEE_DOCTOR_TODAY
            else TriageOutcome.TEST_ADVISED
        }
        if (hasFever) return TriageOutcome.TEST_ADVISED
        if (core >= 2) return TriageOutcome.TEST_ADVISED
        return TriageOutcome.SELF_CARE
    }

    /**
     * Which phase of illness. The critical phase is when plasma leak starts,
     * and it is not when people feel worst.
     */
    fun phaseKey(feverDaysAgo: Int?): String? {
        val day = feverDaysAgo ?: return null
        return when (day) {
            in 0..2 -> "check.phase.febrile"
            in 3..6 -> "check.phase.critical"
            else -> "check.phase.recovery"
        }
    }
}
