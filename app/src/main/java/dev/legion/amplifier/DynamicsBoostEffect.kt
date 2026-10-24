package dev.legion.amplifier

import android.annotation.TargetApi
import android.media.audiofx.AudioEffect
import android.media.audiofx.DynamicsProcessing

/**
 * Gain stage built on DynamicsProcessing: input gain followed by a brick-wall limiter.
 * Unlike LoudnessEnhancer it accepts an effect priority, so Amplifier keeps control of the
 * output mix on Android 17 builds where system or vendor effects claim it first.
 */
@TargetApi(28)
internal class DynamicsBoostEffect(session: Int, onControlChanged: () -> Unit) : BoostEffect {
    private val processor = DynamicsProcessing(PRIORITY, session, config())
    private var appliedMb = Int.MIN_VALUE

    init {
        try {
            processor.setControlStatusListener { _, _ -> onControlChanged() }
        } catch (error: RuntimeException) {
            processor.release()
            throw error
        }
    }

    override val hasControl: Boolean
        get() = try { processor.hasControl() } catch (_: RuntimeException) { false }

    override val enabled: Boolean
        get() = try { processor.enabled } catch (_: RuntimeException) { false }

    override fun setGain(millibels: Int) {
        if (millibels == appliedMb) return
        processor.setInputGainAllChannelsTo(millibels / 100f)
        appliedMb = millibels
    }

    override fun setEnabled(value: Boolean) {
        check(processor.setEnabled(value) == AudioEffect.SUCCESS) { "Audio effect enable failed" }
    }

    override fun release() {
        try {
            processor.setControlStatusListener(null)
        } finally {
            processor.release()
        }
    }

    private companion object {
        // Highest priority wins control of a shared session such as the output mix.
        const val PRIORITY = Int.MAX_VALUE
        const val CHANNELS = 2

        fun config(): DynamicsProcessing.Config {
            val limiter = DynamicsProcessing.Limiter(
                true, true, 0,
                1f, // attack, ms
                60f, // release, ms
                10f, // ratio
                -1f, // threshold, dBFS
                0f, // post gain, dB
            )
            return DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION, CHANNELS,
                false, 0, false, 0, false, 0, true,
            )
                .setPreferredFrameDuration(10f)
                .setInputGainAllChannelsTo(0f)
                .setLimiterAllChannelsTo(limiter)
                .build()
        }
    }
}
