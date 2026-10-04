package dev.legion.amplifier

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.View
import android.view.WindowInsets
import android.widget.Button
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView

class MainActivity : Activity() {
    private lateinit var prefs: Prefs
    private lateinit var enabledSwitch: Switch
    private lateinit var globalSwitch: Switch
    private lateinit var gainSlider: SeekBar
    private lateinit var pauseButton: Button
    private val handler = Handler(Looper.getMainLooper())
    private var rendering = false
    private val statusObserver: (BoostState) -> Unit = { renderStatus(it) }
    private val applyGain = Runnable { BoostService.applySettingsToRunningService() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = Prefs(this)
        setContentView(R.layout.activity_main)
        applyInsets()
        enabledSwitch = findViewById(R.id.enabled_switch)
        globalSwitch = findViewById(R.id.global_switch)
        gainSlider = findViewById(R.id.gain_slider)
        pauseButton = findViewById(R.id.pause_button)
        gainSlider.max = Gain.MAX_MB / Gain.STEP_MB
        gainSlider.progress = prefs.gainMb / Gain.STEP_MB
        renderGain(prefs.gainMb)
        findViewById<View>(R.id.gain_markers).addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            val marker = findViewById<View>(R.id.double_marker)
            val track = gainSlider.width - gainSlider.paddingLeft - gainSlider.paddingRight
            val fraction = Gain.DEFAULT_MB.toFloat() / Gain.MAX_MB
            val center = if (gainSlider.layoutDirection == View.LAYOUT_DIRECTION_RTL) {
                gainSlider.width - gainSlider.paddingRight - track * fraction
            } else {
                gainSlider.paddingLeft + track * fraction
            }
            marker.translationX = center - marker.width / 2f - marker.left
        }

        enabledSwitch.setOnCheckedChangeListener { _, checked ->
            if (rendering) return@setOnCheckedChangeListener
            prefs.enabled = checked
            prefs.paused = false
            if (checked) {
                if (requestStart()) requestSetupPermissions()
            } else {
                handler.removeCallbacks(applyGain)
                stopService(Intent(this, BoostService::class.java))
                renderStatus(BoostRuntime.state)
            }
        }
        globalSwitch.setOnCheckedChangeListener { _, checked ->
            if (rendering) return@setOnCheckedChangeListener
            prefs.useGlobal = checked
            if (prefs.enabled) BoostService.applySettingsToRunningService()
            renderStatus(BoostRuntime.state)
        }
        gainSlider.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (!fromUser) return
                prefs.gainMb = progress * Gain.STEP_MB
                renderGain(prefs.gainMb)
                handler.removeCallbacks(applyGain)
                handler.postDelayed(applyGain, 150)
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) = Unit
            override fun onStopTrackingTouch(seekBar: SeekBar?) {
                handler.removeCallbacks(applyGain)
                BoostService.applySettingsToRunningService()
            }
        })
        pauseButton.setOnClickListener {
            try {
                BoostService.togglePause(this)
            } catch (_: RuntimeException) {
                BoostRuntime.publish(BoostState(startFailed = true))
            }
        }
        findViewById<Button>(R.id.battery_button).setOnClickListener { openBatterySettings() }
        findViewById<Button>(R.id.notification_button).setOnClickListener {
            startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
        }
    }

    override fun onStart() {
        super.onStart()
        BoostRuntime.observe(statusObserver)
    }

    override fun onResume() {
        super.onResume()
        renderPermissions()
        // Recover from a killed process while the activity is visible and starts are allowed.
        if (prefs.enabled && !BoostRuntime.state.running) requestStart()
    }

    override fun onStop() {
        handler.removeCallbacks(applyGain)
        BoostService.applySettingsToRunningService()
        BoostRuntime.remove(statusObserver)
        super.onStop()
    }

    private fun requestStart(): Boolean = try {
        BoostService.start(this)
        true
    } catch (_: RuntimeException) {
        prefs.enabled = false
        BoostRuntime.publish(BoostState(startFailed = true))
        false
    }

    private fun renderGain(gainMb: Int) {
        val text = getString(R.string.gain_value, gainMb / 100.0)
        findViewById<TextView>(R.id.gain_value).text = text
        findViewById<TextView>(R.id.gain_factor).text = getString(R.string.gain_factor, Gain.amplitude(gainMb))
        gainSlider.contentDescription = getString(R.string.gain_accessibility, text)
    }

    private fun renderStatus(state: BoostState) {
        rendering = true
        enabledSwitch.isChecked = prefs.enabled
        globalSwitch.isChecked = prefs.useGlobal
        rendering = false
        pauseButton.isEnabled = state.running && prefs.enabled
        pauseButton.setText(if (state.paused) R.string.resume_boost else R.string.pause_boost)
        val message = when {
            state.startFailed -> R.string.status_start_failed
            !prefs.enabled -> R.string.status_off
            !state.running -> R.string.status_starting
            state.paused -> R.string.status_paused
            state.engine.global == GlobalState.ACTIVE -> R.string.status_global_active
            state.engine.boostedSessions > 0 -> R.string.status_sessions_active
            else -> R.string.status_waiting
        }
        findViewById<TextView>(R.id.service_status).setText(message)
        val global = if (!state.running) R.string.global_idle else when (state.engine.global) {
            GlobalState.ACTIVE -> R.string.global_active
            GlobalState.OFF -> R.string.global_off
            GlobalState.PAUSED -> R.string.global_paused
            GlobalState.NO_CONTROL -> R.string.global_conflict
            GlobalState.UNAVAILABLE -> R.string.global_unavailable
        }
        findViewById<TextView>(R.id.global_status).text = getString(R.string.global_status, getString(global))
        findViewById<TextView>(R.id.session_status).text = getString(
            R.string.session_status, state.engine.boostedSessions, state.engine.knownSessions,
        )
        val issues = buildList {
            if (state.engine.failedSessions > 0) add(resources.getQuantityString(
                R.plurals.failed_sessions, state.engine.failedSessions, state.engine.failedSessions,
            ))
            if (state.engine.controlConflicts > 0) add(getString(R.string.effect_conflict))
            if (state.engine.sessionLimitReached) add(getString(R.string.session_limit))
        }
        findViewById<TextView>(R.id.effect_issues).apply {
            text = issues.joinToString("\n")
            visibility = if (issues.isEmpty()) View.GONE else View.VISIBLE
        }
    }

    private fun requestSetupPermissions() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
            !prefs.askedNotifications) {
            prefs.askedNotifications = true
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION)
        } else {
            offerBatteryExemption()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION) {
            renderPermissions()
            if (prefs.enabled) offerBatteryExemption()
        }
    }

    private fun offerBatteryExemption() {
        if (prefs.askedBattery || batteryExempt()) return
        prefs.askedBattery = true
        AlertDialog.Builder(this)
            .setTitle(R.string.battery_dialog_title)
            .setMessage(R.string.battery_dialog_message)
            .setPositiveButton(R.string.battery_allow) { _, _ -> openBatterySettings() }
            .setNegativeButton(R.string.not_now, null)
            .show()
    }

    private fun batteryExempt(): Boolean = getSystemService(PowerManager::class.java)
        .isIgnoringBatteryOptimizations(packageName)

    private fun renderPermissions() {
        findViewById<TextView>(R.id.battery_status).setText(
            if (batteryExempt()) R.string.battery_unrestricted else R.string.battery_optimized,
        )
        val notifications = getSystemService(NotificationManager::class.java).areNotificationsEnabled()
        findViewById<TextView>(R.id.notification_status).setText(
            if (notifications) R.string.notifications_allowed else R.string.notifications_blocked,
        )
    }

    @SuppressLint("BatteryLife") // Continuous, user-enabled audio processing is the app's core function.
    private fun openBatterySettings() {
        try {
            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
        } catch (_: ActivityNotFoundException) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: ActivityNotFoundException) {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
            }
        }
    }

    @Suppress("DEPRECATION") // Needed for Android 11–14; Android 16 already enforces edge-to-edge.
    private fun applyInsets() {
        val root = findViewById<View>(R.id.root)
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false)
            root.setOnApplyWindowInsetsListener { view, insets ->
                val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
                view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
                insets
            }
            root.requestApplyInsets()
        } else {
            root.fitsSystemWindows = true
        }
    }

    companion object {
        private const val NOTIFICATION_PERMISSION = 1
    }
}
