package bd.uzzal.denguewatch

import bd.uzzal.denguewatch.domain.*
import org.junit.Assert.*
import org.junit.Test

/**
 * The same assertions that pin the iOS engine, so a person who runs the check
 * on an Android phone and an iPhone is told the same thing.
 */
class RiskLevelTest {

    @Test fun `bands match the iOS thresholds at every boundary`() {
        val cases = listOf(
            0.0 to RiskLevel.LOW, 4.999 to RiskLevel.LOW,
            5.0 to RiskLevel.MODERATE, 19.999 to RiskLevel.MODERATE,
            20.0 to RiskLevel.HIGH, 59.999 to RiskLevel.HIGH,
            60.0 to RiskLevel.SEVERE, 1_000_000.0 to RiskLevel.SEVERE,
        )
        for ((value, expected) in cases) {
            assertEquals("incidence $value", expected, RiskLevel.fromIncidencePer100k(value))
        }
    }

    @Test fun `negative incidence reads low, not severe`() {
        assertEquals(RiskLevel.LOW, RiskLevel.fromIncidencePer100k(-1.0))
    }

    @Test fun `NaN reads low rather than falling through to severe`() {
        // Absent data must never present as the loudest reading.
        assertEquals(RiskLevel.LOW, RiskLevel.fromIncidencePer100k(Double.NaN))
    }

    @Test fun `infinite incidence is severe`() {
        assertEquals(RiskLevel.SEVERE, RiskLevel.fromIncidencePer100k(Double.POSITIVE_INFINITY))
    }
}

class SeriesTest {
    @Test fun `sum of empty is zero`() = assertEquals(0, Series.sum(emptyList()))
    @Test fun `sum adds up`() = assertEquals(6, Series.sum(listOf(1, 2, 3)))

    @Test fun `window of one is identity`() {
        assertEquals(listOf(1.0, 2.0, 3.0), Series.movingAverage(listOf(1, 2, 3), 1))
    }

    @Test fun `a flat series averages flat`() {
        assertTrue(Series.movingAverage(listOf(10, 10, 10, 10), 3).all { Math.abs(it - 10) < 1e-9 })
    }

    @Test fun `empty series does not throw`() {
        assertTrue(Series.movingAverage(emptyList(), 7).isEmpty())
    }

    @Test fun `window longer than the series is handled`() {
        assertEquals(1, Series.movingAverage(listOf(5), 7).size)
    }

    @Test fun `output length always matches input`() {
        assertEquals(7, Series.movingAverage(listOf(1, 2, 3, 4, 5, 6, 7), 3).size)
    }
}

class TriageEngineTest {
    private val none = TriageEngine.Context()
    private val comorbid = TriageEngine.Context(isPregnant = true)
    private fun eval(vararg ids: String, ctx: TriageEngine.Context = none) =
        TriageEngine.evaluate(ids.toSet(), ctx)

    @Test fun `no symptoms is self care`() = assertEquals(TriageOutcome.SELF_CARE, eval())

    @Test fun `fever alone advises a test`() =
        assertEquals(TriageOutcome.TEST_ADVISED, eval("fever"))

    @Test fun `one core symptom without fever is self care`() =
        assertEquals(TriageOutcome.SELF_CARE, eval("headache"))

    @Test fun `two core symptoms without fever advise a test`() =
        assertEquals(TriageOutcome.TEST_ADVISED, eval("headache", "aches"))

    @Test fun `a warning sign means see a doctor today`() =
        assertEquals(TriageOutcome.SEE_DOCTOR_TODAY, eval("vomiting"))

    @Test fun `a severe sign is an emergency`() =
        assertEquals(TriageOutcome.EMERGENCY, eval("faint"))

    @Test fun `severe outranks warning`() =
        assertEquals(TriageOutcome.EMERGENCY, eval("faint", "vomiting"))

    @Test fun `severe outranks everything`() =
        assertEquals(TriageOutcome.EMERGENCY, eval("heavyBleed", "fever", "headache", "aches"))

    @Test fun `warning outranks core`() =
        assertEquals(TriageOutcome.SEE_DOCTOR_TODAY, eval("fever", "headache", "aches", "noUrine"))

    @Test fun `comorbidity escalates fever plus two core`() =
        assertEquals(TriageOutcome.SEE_DOCTOR_TODAY, eval("fever", "headache", "aches", ctx = comorbid))

    @Test fun `the same symptoms without comorbidity stay at test advised`() =
        assertEquals(TriageOutcome.TEST_ADVISED, eval("fever", "headache", "aches"))

    @Test fun `comorbidity alone is not a symptom`() =
        assertEquals(TriageOutcome.SELF_CARE, eval(ctx = comorbid))

    @Test fun `unknown ids are ignored rather than throwing`() {
        assertEquals(TriageOutcome.SELF_CARE, eval("nonsense", "xyzzy"))
        assertEquals(TriageOutcome.TEST_ADVISED, eval("nonsense", "fever"))
    }

    /**
     * The property that matters most: reporting one more symptom must never
     * produce a calmer answer. Checked across every ordered pair, in both
     * contexts.
     */
    @Test fun `adding a symptom never lowers severity`() {
        val ids = TriageEngine.symptoms.map { it.id }
        for (ctx in listOf(none, comorbid)) {
            for (a in ids) for (b in ids) {
                if (a == b) continue
                val one = TriageEngine.evaluate(setOf(a), ctx)
                val two = TriageEngine.evaluate(setOf(a, b), ctx)
                assertTrue("[$a] $one -> [$a,$b] $two", two.ordinal >= one.ordinal)
            }
        }
    }

    @Test fun `phase mapping matches iOS`() {
        assertNull(TriageEngine.phaseKey(null))
        assertEquals("check.phase.febrile", TriageEngine.phaseKey(0))
        assertEquals("check.phase.febrile", TriageEngine.phaseKey(2))
        assertEquals("check.phase.critical", TriageEngine.phaseKey(3))
        assertEquals("check.phase.critical", TriageEngine.phaseKey(6))
        assertEquals("check.phase.recovery", TriageEngine.phaseKey(7))
        assertEquals("check.phase.recovery", TriageEngine.phaseKey(-3))
    }

    @Test fun `outcome slugs match the shared string keys`() {
        assertEquals("selfCare", TriageOutcome.SELF_CARE.slug)
        assertEquals("testAdvised", TriageOutcome.TEST_ADVISED.slug)
        assertEquals("seeDoctor", TriageOutcome.SEE_DOCTOR_TODAY.slug)
        assertEquals("emergency", TriageOutcome.EMERGENCY.slug)
    }
}
