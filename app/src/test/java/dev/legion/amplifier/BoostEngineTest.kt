package dev.legion.amplifier

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BoostEngineTest {
    private class FakeEffect : BoostEffect {
        var controlled = true
        private var active = false
        var appliedGain = 0
        var released = false
        var failGain = false
        var failEnable = false
        override val hasControl get() = controlled
        override val enabled get() = active
        override fun setGain(millibels: Int) {
            check(!failGain)
            appliedGain = millibels
        }
        override fun setEnabled(value: Boolean) {
            check(!failEnable || !value)
            active = value
        }
        override fun release() { released = true }
    }

    private class Fixture(private val unavailable: Set<Int> = emptySet()) {
        val effects = mutableMapOf<Int, FakeEffect>()
        val engine = BoostEngine { session ->
            check(session !in unavailable)
            FakeEffect().also { effects[session] = it }
        }
    }

    @Test fun globalAndSessionAttachmentsUseOnlyOneGainStage() {
        val f = Fixture()
        f.engine.configure(600, useGlobal = true, paused = false)
        val status = f.engine.openSession(42)
        assertEquals(GlobalState.ACTIVE, status.global)
        assertEquals(1, status.knownSessions)
        assertEquals(0, status.boostedSessions)
        assertTrue(f.effects.getValue(0).enabled)
        assertFalse(f.effects.getValue(42).enabled)
        assertEquals(600, f.effects.getValue(42).appliedGain)
    }

    @Test fun rejectedGlobalMixFallsBackToAnnouncedSessions() {
        val f = Fixture(setOf(0))
        f.engine.configure(600, useGlobal = true, paused = false)
        val status = f.engine.openSession(42)
        assertEquals(GlobalState.UNAVAILABLE, status.global)
        assertEquals(1, status.boostedSessions)
        assertTrue(f.effects.getValue(42).enabled)
    }

    @Test fun losingAndRegainingGlobalControlSwitchesTheRoute() {
        val f = Fixture()
        f.engine.configure(600, useGlobal = true, paused = false)
        f.engine.openSession(42)
        f.effects.getValue(0).controlled = false
        var status = f.engine.refresh()
        assertEquals(GlobalState.NO_CONTROL, status.global)
        assertEquals(1, status.boostedSessions)
        f.effects.getValue(0).controlled = true
        status = f.engine.refresh()
        assertEquals(GlobalState.ACTIVE, status.global)
        assertFalse(f.effects.getValue(42).enabled)
    }

    @Test fun pauseDisablesEveryEffectAndResumeRestoresGain() {
        val f = Fixture(setOf(0))
        f.engine.configure(600, useGlobal = true, paused = false)
        f.engine.openSession(42)
        val paused = f.engine.configure(1200, useGlobal = true, paused = true)
        assertEquals(0, paused.boostedSessions)
        assertFalse(f.effects.getValue(42).enabled)
        val resumed = f.engine.configure(1200, useGlobal = true, paused = false)
        assertEquals(1, resumed.boostedSessions)
        assertEquals(1200, f.effects.getValue(42).appliedGain)
    }

    @Test fun disablingGlobalReleasesItAndEnablesSessionFallback() {
        val f = Fixture()
        f.engine.configure(600, useGlobal = true, paused = false)
        f.engine.openSession(42)
        val status = f.engine.configure(600, useGlobal = false, paused = false)
        assertEquals(GlobalState.OFF, status.global)
        assertTrue(f.effects.getValue(0).released)
        assertFalse(f.effects.getValue(0).enabled)
        assertTrue(f.effects.getValue(42).enabled)
    }

    @Test fun duplicateEventsAreIdempotentAndCloseReleasesTheEffect() {
        val f = Fixture()
        f.engine.configure(600, useGlobal = false, paused = false)
        f.engine.openSession(42)
        val effect = f.effects.getValue(42)
        assertEquals(1, f.engine.openSession(42).knownSessions)
        assertTrue(effect === f.effects.getValue(42))
        assertEquals(0, f.engine.closeSession(42).knownSessions)
        assertTrue(effect.released)
        assertFalse(effect.enabled)
        assertEquals(0, f.engine.closeSession(42).knownSessions)
    }

    @Test fun publicBroadcastsCannotManageGlobalMixOrExhaustUnlimitedEffects() {
        val f = Fixture()
        f.engine.configure(600, useGlobal = false, paused = false)
        assertEquals(0, f.engine.openSession(0).knownSessions)
        assertEquals(0, f.engine.openSession(-1).knownSessions)
        repeat(BoostEngine.MAX_SESSIONS) { f.engine.openSession(it + 1) }
        val status = f.engine.openSession(999)
        assertTrue(status.sessionLimitReached)
        assertEquals(BoostEngine.MAX_SESSIONS, f.effects.size)
        assertFalse(f.engine.closeSession(1).sessionLimitReached)
    }

    @Test fun failedGlobalEnableAlsoFallsBack() {
        val f = Fixture()
        f.engine.configure(600, useGlobal = true, paused = true)
        // Open the global effect through the factory, then make future enables fail.
        f.engine.configure(600, useGlobal = true, paused = false)
        f.effects.getValue(0).setEnabled(false)
        f.effects.getValue(0).failEnable = true
        val status = f.engine.openSession(42)
        assertEquals(GlobalState.UNAVAILABLE, status.global)
        assertEquals(1, status.boostedSessions)
    }

    @Test fun failedGainUpdateDisablesTheOldGainInsteadOfReportingSuccess() {
        val f = Fixture()
        f.engine.configure(1500, useGlobal = false, paused = false)
        f.engine.openSession(42)
        f.effects.getValue(42).failGain = true
        val status = f.engine.configure(600, useGlobal = false, paused = false)
        assertEquals(0, status.boostedSessions)
        assertEquals(1, status.failedSessions)
        assertFalse(f.effects.getValue(42).enabled)
    }

    @Test fun unavailableSessionDoesNotPreventOtherSessionsFromWorking() {
        val f = Fixture(setOf(42))
        f.engine.configure(600, useGlobal = false, paused = false)
        f.engine.openSession(42)
        val status = f.engine.openSession(43)
        assertEquals(2, status.knownSessions)
        assertEquals(1, status.failedSessions)
        assertEquals(1, status.boostedSessions)
    }

    @Test fun shutdownReleasesGlobalAndAllSessionResources() {
        val f = Fixture()
        f.engine.configure(600, useGlobal = true, paused = false)
        f.engine.openSession(42)
        f.engine.openSession(43)
        f.engine.release()
        assertTrue(f.effects.values.all { it.released && !it.enabled })
        assertEquals(0, f.engine.closeSession(42).knownSessions)
    }

    @Test fun gainIsClampedAndSixDecibelsIsApproximatelyDoubleAmplitude() {
        val f = Fixture()
        f.engine.configure(Int.MAX_VALUE, useGlobal = true, paused = false)
        assertEquals(1500, f.effects.getValue(0).appliedGain)
        f.engine.configure(-100, useGlobal = true, paused = false)
        assertEquals(0, f.effects.getValue(0).appliedGain)
        assertEquals(2.0, Gain.amplitude(600), 0.005)
        assertEquals(1.0, Gain.amplitude(0), 0.0)
    }
}
