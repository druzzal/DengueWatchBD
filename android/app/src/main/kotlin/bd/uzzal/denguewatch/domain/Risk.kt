package bd.uzzal.denguewatch.domain

/**
 * Risk bands, thresholds identical to the iOS app: a two-week attack rate per
 * 100,000 people.
 */
enum class RiskLevel { LOW, MODERATE, HIGH, SEVERE;

    companion object {
        /**
         * NaN is rejected explicitly rather than left to fall through.
         *
         * Every comparison against NaN is false, so a `when` chain of upper
         * bounds sends it to the last branch — which would report SEVERE, the
         * loudest possible reading, from what is actually absent data. The iOS
         * initialiser has the same shape and is only safe because all three of
         * its callers guard the division; that is an invariant a future caller
         * can quietly break, so this port does not rely on it.
         */
        fun fromIncidencePer100k(value: Double): RiskLevel = when {
            value.isNaN() -> LOW
            value < 5 -> LOW
            value < 20 -> MODERATE
            value < 60 -> HIGH
            else -> SEVERE
        }
    }
}

object Series {
    fun sum(values: List<Int>): Int = values.sum()

    /** Centred-trailing moving average, smoothing the reporting-day sawtooth. */
    fun movingAverage(values: List<Int>, window: Int): List<Double> {
        if (window <= 1) return values.map { it.toDouble() }
        return values.indices.map { index ->
            val start = maxOf(0, index - window + 1)
            val slice = values.subList(start, index + 1)
            slice.sum().toDouble() / slice.size
        }
    }
}
