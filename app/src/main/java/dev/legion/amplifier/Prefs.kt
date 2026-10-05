package dev.legion.amplifier

import android.content.Context

class Prefs(context: Context) {
    private val values = context.getSharedPreferences("amplifier", Context.MODE_PRIVATE)

    var enabled: Boolean
        get() = values.getBoolean("enabled", false)
        set(value) { values.edit().putBoolean("enabled", value).apply() }

    var gainMb: Int
        get() = Gain.clamp(values.getInt("gain_mb", Gain.DEFAULT_MB))
        set(value) { values.edit().putInt("gain_mb", Gain.clamp(value)).apply() }

    var paused: Boolean
        get() = values.getBoolean("paused", false)
        set(value) { values.edit().putBoolean("paused", value).apply() }

    var useGlobal: Boolean
        get() = values.getBoolean("use_global", true)
        set(value) { values.edit().putBoolean("use_global", value).apply() }

    var askedNotifications: Boolean
        get() = values.getBoolean("asked_notifications", false)
        set(value) { values.edit().putBoolean("asked_notifications", value).apply() }

    var askedBattery: Boolean
        get() = values.getBoolean("asked_battery", false)
        set(value) { values.edit().putBoolean("asked_battery", value).apply() }
}
