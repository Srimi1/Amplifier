package dev.legion.amplifier

import kotlin.math.pow

object Gain {
    const val DEFAULT_MB = 600
    const val MAX_MB = 1500
    const val STEP_MB = 50

    fun clamp(millibels: Int): Int = millibels.coerceIn(0, MAX_MB)

    fun amplitude(millibels: Int): Double = 10.0.pow(clamp(millibels) / 2000.0)
}
