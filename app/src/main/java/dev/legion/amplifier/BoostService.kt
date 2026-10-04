package dev.legion.amplifier

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.audiofx.AudioEffect
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import java.lang.ref.WeakReference

class BoostService : Service() {
    private lateinit var prefs: Prefs
    private lateinit var engine: BoostEngine
    private val handler = Handler(Looper.getMainLooper())
    private var foreground = false
    private var receiverRegistered = false
    private var destroyed = false

    private val sessionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = handleSessionEvent(intent)
    }

    override fun onCreate() {
        super.onCreate()
        prefs = Prefs(this)
        engine = BoostEngine { session ->
            AndroidBoostEffect(session) {
                handler.post {
                    if (!destroyed && foreground && prefs.enabled) updateStatus(engine.refresh())
                }
            }
        }
        val channel = NotificationChannel(
            CHANNEL_ID, getString(R.string.channel_name), NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.channel_description)
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        activeService = WeakReference(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP || !prefs.enabled) {
            prefs.enabled = false
            prefs.paused = false
            engine.release()
            foreground = false
            stopForeground(STOP_FOREGROUND_REMOVE)
            BoostRuntime.publish(BoostState())
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_TOGGLE) prefs.paused = !prefs.paused

        // Meet the foreground-start deadline before opening any native audio engines.
        try {
            val notification = notification(BoostRuntime.state.engine)
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            foreground = true
        } catch (error: RuntimeException) {
            prefs.enabled = false
            engine.release()
            foreground = false
            BoostRuntime.publish(BoostState(startFailed = true))
            Log.w(TAG, "Foreground service start failed", error)
            stopSelf()
            return START_NOT_STICKY
        }

        if (!receiverRegistered) {
            val filter = IntentFilter().apply {
                addAction(AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION)
                addAction(AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION)
            }
            // Players live in other apps, so this receiver must be exported.
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(sessionReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerLegacyReceiver(filter)
            }
            receiverRegistered = true
        }
        applySettings()
        return START_STICKY
    }

    private fun applySettings() {
        if (!destroyed && foreground && prefs.enabled) {
            updateStatus(engine.configure(prefs.gainMb, prefs.useGlobal, prefs.paused))
        }
    }

    @SuppressLint("UnspecifiedRegisterReceiverFlag") // Pre-33 API: broadcasts intentionally come from other apps.
    private fun registerLegacyReceiver(filter: IntentFilter) {
        registerReceiver(sessionReceiver, filter)
    }

    private fun handleSessionEvent(intent: Intent) {
        if (!foreground || !prefs.enabled) return
        try {
            val session = intent.getIntExtra(AudioEffect.EXTRA_AUDIO_SESSION, -1)
            if (session <= 0) return
            when (intent.action) {
                AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION -> {
                    val content = intent.getIntExtra(AudioEffect.EXTRA_CONTENT_TYPE, AudioEffect.CONTENT_TYPE_MUSIC)
                    if (content !in AudioEffect.CONTENT_TYPE_MUSIC..AudioEffect.CONTENT_TYPE_GAME) return
                    updateStatus(engine.openSession(session))
                }
                AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION -> updateStatus(engine.closeSession(session))
            }
        } catch (error: RuntimeException) {
            // Reject malformed public broadcasts without taking down the service.
            Log.w(TAG, "Ignored invalid audio-session event", error)
        }
    }

    private fun updateStatus(status: EngineStatus) {
        BoostRuntime.publish(BoostState(running = true, paused = prefs.paused, engine = status))
        if (foreground) {
            getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification(status))
        }
    }

    private fun notification(status: EngineStatus): Notification {
        val openApp = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PENDING_FLAGS,
        )
        val toggle = PendingIntent.getForegroundService(
            this, 1, Intent(this, BoostService::class.java).setAction(ACTION_TOGGLE), PENDING_FLAGS,
        )
        val stop = PendingIntent.getService(
            this, 2, Intent(this, BoostService::class.java).setAction(ACTION_STOP), PENDING_FLAGS,
        )
        val route = when (status.global) {
            GlobalState.ACTIVE -> getString(R.string.notification_global)
            else -> resources.getQuantityString(R.plurals.notification_sessions, status.boostedSessions, status.boostedSessions)
        }
        val text = if (prefs.paused) getString(R.string.notification_paused, prefs.gainMb / 100.0)
            else getString(R.string.notification_active, prefs.gainMb / 100.0, route)
        val builder = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_amplifier)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(openApp)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(
                Icon.createWithResource(this, if (prefs.paused) R.drawable.ic_play else R.drawable.ic_pause),
                getString(if (prefs.paused) R.string.resume_boost else R.string.pause_boost), toggle,
            ).build())
            .addAction(Notification.Action.Builder(
                Icon.createWithResource(this, R.drawable.ic_stop), getString(R.string.stop_boost), stop,
            ).build())
        if (Build.VERSION.SDK_INT >= 31) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    override fun onDestroy() {
        destroyed = true
        handler.removeCallbacksAndMessages(null)
        if (receiverRegistered) unregisterReceiver(sessionReceiver)
        engine.release()
        foreground = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        if (activeService.get() === this) activeService.clear()
        BoostRuntime.publish(BoostState(startFailed = BoostRuntime.state.startFailed))
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val TAG = "Amplifier"
        private const val CHANNEL_ID = "audio_boost"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_START = "dev.legion.amplifier.START"
        private const val ACTION_TOGGLE = "dev.legion.amplifier.TOGGLE"
        private const val ACTION_STOP = "dev.legion.amplifier.STOP"
        private const val PENDING_FLAGS = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        private var activeService = WeakReference<BoostService>(null)

        fun start(context: Context) {
            context.startForegroundService(Intent(context, BoostService::class.java).setAction(ACTION_START))
        }

        fun togglePause(context: Context) {
            context.startForegroundService(Intent(context, BoostService::class.java).setAction(ACTION_TOGGLE))
        }

        internal fun deliverSessionEvent(intent: Intent) {
            activeService.get()?.handleSessionEvent(intent)
        }

        internal fun applySettingsToRunningService() {
            activeService.get()?.applySettings()
        }
    }
}
