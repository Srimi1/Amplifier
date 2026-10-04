package dev.legion.amplifier

internal data class BoostState(
    val running: Boolean = false,
    val paused: Boolean = false,
    val engine: EngineStatus = EngineStatus(),
    val startFailed: Boolean = false,
)

/** In-process status; never persisted, so stale session counts cannot survive a restart. */
internal object BoostRuntime {
    var state = BoostState()
        private set
    private val listeners = linkedSetOf<(BoostState) -> Unit>()

    fun publish(value: BoostState) {
        if (state == value) return
        state = value
        listeners.toList().forEach { it(value) }
    }

    fun observe(listener: (BoostState) -> Unit) {
        listeners.add(listener)
        listener(state)
    }

    fun remove(listener: (BoostState) -> Unit) {
        listeners.remove(listener)
    }
}
