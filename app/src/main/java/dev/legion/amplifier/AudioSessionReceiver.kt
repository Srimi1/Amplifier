package dev.legion.amplifier

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AudioSessionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        BoostService.deliverSessionEvent(intent)
    }
}
