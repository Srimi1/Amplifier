package dev.legion.amplifier

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        if (!Prefs(context).enabled) return
        try {
            BoostService.start(context)
        } catch (error: RuntimeException) {
            // Keep the requested enabled flag. Opening the app retries from the foreground.
            BoostRuntime.publish(BoostState(startFailed = true))
            Log.w("Amplifier", "Android prevented background restart", error)
        }
    }
}
