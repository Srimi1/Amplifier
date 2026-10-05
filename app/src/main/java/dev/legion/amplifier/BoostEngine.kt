package dev.legion.amplifier

/** Platform-independent routing and effect lifetime management. Used on the main thread. */
internal interface BoostEffect {
    val hasControl: Boolean
    val enabled: Boolean
    fun setGain(millibels: Int)
    fun setEnabled(value: Boolean)
    fun release()
}

internal enum class GlobalState { OFF, ACTIVE, UNAVAILABLE, NO_CONTROL, PAUSED }

internal data class EngineStatus(
    val global: GlobalState = GlobalState.OFF,
    val boostedSessions: Int = 0,
    val knownSessions: Int = 0,
    val failedSessions: Int = 0,
    val controlConflicts: Int = 0,
    val sessionLimitReached: Boolean = false,
)

internal class BoostEngine(private val createEffect: (Int) -> BoostEffect) {
    private val effects = linkedMapOf<Int, BoostEffect>()
    private val sessions = linkedSetOf<Int>()
    private var gainMb = Gain.DEFAULT_MB
    private var useGlobal = true
    private var paused = false
    private var limited = false
    private val failed = mutableSetOf<Int>()

    fun configure(gainMb: Int, useGlobal: Boolean, paused: Boolean): EngineStatus {
        this.gainMb = Gain.clamp(gainMb)
        this.useGlobal = useGlobal
        this.paused = paused
        if (!useGlobal) removeEffect(0)
        if (useGlobal && !paused && 0 !in effects) attach(0)
        return refresh()
    }

    fun openSession(session: Int): EngineStatus {
        // Session broadcasts are public input. Session 0 is managed only by configure().
        if (session <= 0) return status()
        if (session !in sessions && sessions.size >= MAX_SESSIONS) {
            limited = true
            return status()
        }
        sessions.add(session)
        if (session !in effects) attach(session)
        return refresh()
    }

    fun closeSession(session: Int): EngineStatus {
        if (session <= 0) return status()
        sessions.remove(session)
        removeEffect(session)
        if (sessions.size < MAX_SESSIONS) limited = false
        return status()
    }

    fun refresh(): EngineStatus {
        // Turn off per-session processing before enabling the mix. The same audio
        // must not receive +6 dB twice when both attachment strategies succeed.
        if (paused || (useGlobal && effects[0]?.hasControl == true)) {
            effects.filterKeys { it != 0 }.forEach { (session, effect) ->
                apply(session, effect, false)
            }
        }
        effects[0]?.let { apply(0, it, useGlobal && !paused) }
        val globalActive = globalActive()
        effects.filterKeys { it != 0 }.forEach { (session, effect) ->
            apply(session, effect, !paused && !globalActive)
        }
        return status()
    }

    fun release() {
        effects.keys.toList().forEach(::removeEffect)
        sessions.clear()
        failed.clear()
        limited = false
    }

    private fun attach(session: Int) {
        try {
            effects[session] = createEffect(session)
            failed.remove(session)
        } catch (_: RuntimeException) {
            failed.add(session)
        }
    }

    private fun apply(session: Int, effect: BoostEffect, enabled: Boolean) {
        if (!effect.hasControl) return
        try {
            effect.setGain(gainMb)
            if (effect.enabled != enabled) effect.setEnabled(enabled)
            if (effect.enabled != enabled) {
                failed.add(session)
            } else {
                failed.remove(session)
            }
        } catch (_: RuntimeException) {
            failed.add(session)
            // A failed gain update must not leave an old, possibly larger boost running.
            try { effect.setEnabled(false) } catch (_: RuntimeException) { /* Engine gone. */ }
        }
    }

    private fun removeEffect(session: Int) {
        effects.remove(session)?.let { effect ->
            try {
                if (effect.hasControl) effect.setEnabled(false)
            } catch (_: RuntimeException) { /* Already disconnected. */ }
            try { effect.release() } catch (_: RuntimeException) { /* Already released. */ }
        }
        failed.remove(session)
    }

    private fun globalActive(): Boolean = !paused && useGlobal &&
        effects[0]?.let { it.hasControl && it.enabled && 0 !in failed } == true

    private fun status(): EngineStatus = EngineStatus(
        global = when {
            !useGlobal -> GlobalState.OFF
            paused -> GlobalState.PAUSED
            globalActive() -> GlobalState.ACTIVE
            effects[0]?.hasControl == false -> GlobalState.NO_CONTROL
            else -> GlobalState.UNAVAILABLE
        },
        boostedSessions = if (paused || globalActive()) 0 else sessions.count {
            it !in failed && effects[it]?.let { effect -> effect.hasControl && effect.enabled } == true
        },
        knownSessions = sessions.size,
        failedSessions = sessions.count { it in failed },
        controlConflicts = effects.values.count { !it.hasControl },
        sessionLimitReached = limited,
    )

    companion object {
        const val MAX_SESSIONS = 32
    }
}
