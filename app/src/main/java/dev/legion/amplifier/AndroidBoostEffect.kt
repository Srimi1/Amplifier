package dev.legion.amplifier

import android.media.audiofx.AudioEffect
import android.media.audiofx.LoudnessEnhancer

internal class AndroidBoostEffect(session: Int, onControlChanged: () -> Unit) : BoostEffect {
    private val enhancer = LoudnessEnhancer(session)

    init {
        try {
            enhancer.setControlStatusListener { _, _ -> onControlChanged() }
        } catch (error: RuntimeException) {
            enhancer.release()
            throw error
        }
    }

    override val hasControl: Boolean
        get() = try { enhancer.hasControl() } catch (_: RuntimeException) { false }

    override val enabled: Boolean
        get() = try { enhancer.enabled } catch (_: RuntimeException) { false }

    override fun setGain(millibels: Int) = enhancer.setTargetGain(millibels)

    override fun setEnabled(value: Boolean) {
        check(enhancer.setEnabled(value) == AudioEffect.SUCCESS) { "Audio effect enable failed" }
    }

    override fun release() {
        try {
            enhancer.setControlStatusListener(null)
        } finally {
            enhancer.release()
        }
    }
}
