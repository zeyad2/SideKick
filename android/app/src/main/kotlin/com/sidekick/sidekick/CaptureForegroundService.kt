package com.sidekick.sidekick

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import java.io.File
import java.util.UUID

class CaptureForegroundService : Service() {
    private var recorder: MediaRecorder? = null
    private var currentEventId: String? = null
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var store: NativeCaptureStore

    private val amplitudeTick = object : Runnable {
        override fun run() {
            val amplitude = runCatching { recorder?.maxAmplitude ?: 0 }.getOrDefault(0)
            broadcast(ACTION_LEVEL) { putExtra(EXTRA_AMPLITUDE, amplitude) }
            if (isRecording) handler.postDelayed(this, LEVEL_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        store = NativeCaptureStore(this)
        if (!CaptureRuntimeGuard.hasLiveCapture) {
            store.recoverInterrupted()?.let(::broadcastSaved)
        }
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopRecording()
            ACTION_CANCEL -> cancelRecording()
            ACTION_START -> startRecording()
            else -> if (!CaptureRuntimeGuard.hasLiveCapture) stopSelf()
        }
        return START_STICKY
    }

    @Synchronized
    private fun startRecording() {
        if (CaptureRuntimeGuard.hasLiveCapture) return
        startForeground(NOTIFICATION_ID, notification("Preparing microphone…"))
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            broadcast(ACTION_ERROR) { putExtra(EXTRA_ERROR, "microphone_permission_denied") }
            stopForegroundAndSelf()
            return
        }

        if (!CaptureRuntimeGuard.hasLiveCapture) store.recoverInterrupted()?.let(::broadcastSaved)
        if (store.active() != null) {
            broadcast(ACTION_ERROR) { putExtra(EXTRA_ERROR, "previous_capture_recovery_required") }
            stopForegroundAndSelf()
            return
        }
        val ownerId = store.configuredOwner()
        if (ownerId == null) {
            broadcast(ACTION_ERROR) { putExtra(EXTRA_ERROR, "signed_out") }
            stopForegroundAndSelf()
            return
        }

        val capturedAt = System.currentTimeMillis()
        val eventId = UUID.randomUUID().toString()
        val directory = File(applicationInfo.dataDir, "app_flutter/pending_audio").apply { mkdirs() }
        val output = File(directory, "$eventId.aac")
        val event = NativeCaptureEvent(eventId, output.absolutePath, capturedAt, ownerId)
        CaptureRuntimeGuard.begin(eventId)
        currentEventId = eventId

        try {
            store.markActive(event)
            recorder = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(this) else {
                @Suppress("DEPRECATION") MediaRecorder()
            }).apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.AAC_ADTS)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioEncodingBitRate(128_000)
                setAudioSamplingRate(44_100)
                setOutputFile(output.absolutePath)
                prepare()
                start()
            }
            store.updateActiveState(STATE_RECORDING)
            isRecording = true
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .notify(NOTIFICATION_ID, notification("Recording — tap Done in Sidekick"))
            broadcast(ACTION_STARTED) {
                putExtra(EXTRA_EVENT_ID, eventId)
                putExtra(EXTRA_AUDIO_PATH, output.absolutePath)
                putExtra(EXTRA_CAPTURED_AT, capturedAt)
                putExtra(EXTRA_OWNER_ID, ownerId)
            }
            handler.post(amplitudeTick)
        } catch (error: Throwable) {
            recorder?.release()
            recorder = null
            isRecording = false
            store.quarantineActive("recorder_start_failed")
            CaptureRuntimeGuard.end(eventId)
            currentEventId = null
            broadcast(ACTION_ERROR) { putExtra(EXTRA_ERROR, error.javaClass.simpleName) }
            stopForegroundAndSelf()
        }
    }

    @Synchronized
    private fun stopRecording() {
        val activeRecorder = recorder ?: run {
            stopForegroundAndSelf()
            return
        }
        val eventId = currentEventId
        try {
            handler.removeCallbacks(amplitudeTick)
            // The state marker is diagnostic. A failed commit must never prevent
            // MediaRecorder.stop(), which is what makes the audio independently durable.
            runCatching { store.updateActiveState(STATE_FINALIZING) }
            val finalized = runCatching { activeRecorder.stop() }.isSuccess
            val active = store.active()
            val durable = finalized && active != null &&
                CaptureAudioValidator.syncAndValidate(File(active.audioPath))
            if (durable) {
                runCatching { store.completeActive() }
                    .onSuccess { it?.let(::broadcastSaved) }
                    .onFailure {
                        broadcast(ACTION_ERROR) {
                            putExtra(EXTRA_ERROR, "capture_journal_finalize_failed")
                        }
                    }
            } else {
                // Preserve the bytes and failure metadata without wedging later captures.
                runCatching { store.quarantineActive("audio_finalization_failed") }
                broadcast(ACTION_ERROR) { putExtra(EXTRA_ERROR, "audio_finalization_failed") }
            }
        } finally {
            runCatching { activeRecorder.release() }
            recorder = null
            isRecording = false
            eventId?.let(CaptureRuntimeGuard::end)
            currentEventId = null
            stopForegroundAndSelf()
        }
    }

    @Synchronized
    private fun cancelRecording() {
        val eventId = currentEventId
        handler.removeCallbacks(amplitudeTick)
        runCatching { recorder?.stop() }
        runCatching { recorder?.release() }
        recorder = null
        isRecording = false
        store.discardActive()
        eventId?.let(CaptureRuntimeGuard::end)
        currentEventId = null
        stopForegroundAndSelf()
    }

    override fun onDestroy() {
        if (recorder != null) stopRecording()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun notification(text: String): android.app.Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            putExtra(MainActivity.EXTRA_SHOW_CAPTURE, true)
        }
        val openApp = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, CaptureForegroundService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Sidekick voice capture")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openApp)
            .addAction(0, "Done", stop)
            .build()
    }

    private fun createNotificationChannel() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Voice capture", NotificationManager.IMPORTANCE_LOW),
        )
    }

    private fun broadcast(action: String, extras: Intent.() -> Unit = {}) {
        sendBroadcast(Intent(action).setPackage(packageName).apply(extras))
    }

    private fun broadcastSaved(event: NativeCaptureEvent) {
        broadcast(ACTION_SAVED) {
            putExtra(EXTRA_EVENT_ID, event.eventId)
            putExtra(EXTRA_AUDIO_PATH, event.audioPath)
            putExtra(EXTRA_CAPTURED_AT, event.capturedAtMs)
            putExtra(EXTRA_OWNER_ID, event.ownerId)
        }
    }

    private fun stopForegroundAndSelf() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    companion object {
        const val ACTION_START = "com.sidekick.sidekick.capture.START"
        const val ACTION_STOP = "com.sidekick.sidekick.capture.STOP"
        const val ACTION_CANCEL = "com.sidekick.sidekick.capture.CANCEL"
        const val ACTION_STARTED = "com.sidekick.sidekick.capture.STARTED"
        const val ACTION_LEVEL = "com.sidekick.sidekick.capture.LEVEL"
        const val ACTION_SAVED = "com.sidekick.sidekick.capture.SAVED"
        const val ACTION_ERROR = "com.sidekick.sidekick.capture.ERROR"
        const val EXTRA_EVENT_ID = "event_id"
        const val EXTRA_AUDIO_PATH = "audio_path"
        const val EXTRA_CAPTURED_AT = "captured_at"
        const val EXTRA_OWNER_ID = "owner_id"
        const val EXTRA_AMPLITUDE = "amplitude"
        const val EXTRA_ERROR = "error"
        private const val CHANNEL_ID = "sidekick_voice_capture"
        private const val NOTIFICATION_ID = 3203
        private const val LEVEL_INTERVAL_MS = 100L

        @Volatile var isRecording = false
            private set

    }
}
