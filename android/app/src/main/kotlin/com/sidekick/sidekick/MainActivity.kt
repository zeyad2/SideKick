package com.sidekick.sidekick

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.provider.Settings
import android.view.KeyEvent
import android.view.WindowManager
import android.view.accessibility.AccessibilityManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var captureChannel: MethodChannel? = null
    private var receiverRegistered = false

    private val captureReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent) {
            val payload = mutableMapOf<String, Any?>()
            intent.getStringExtra(CaptureForegroundService.EXTRA_EVENT_ID)?.let { payload["eventId"] = it }
            intent.getStringExtra(CaptureForegroundService.EXTRA_AUDIO_PATH)?.let { payload["audioPath"] = it }
            if (intent.hasExtra(CaptureForegroundService.EXTRA_CAPTURED_AT)) {
                payload["capturedAtMs"] = intent.getLongExtra(CaptureForegroundService.EXTRA_CAPTURED_AT, 0)
            }
            intent.getStringExtra(CaptureForegroundService.EXTRA_OWNER_ID)?.let {
                payload["ownerId"] = it
            }
            when (intent.action) {
                CaptureForegroundService.ACTION_STARTED -> captureChannel?.invokeMethod("recordingStarted", payload)
                CaptureForegroundService.ACTION_LEVEL -> captureChannel?.invokeMethod(
                    "recordingLevel",
                    mapOf("amplitude" to intent.getIntExtra(CaptureForegroundService.EXTRA_AMPLITUDE, 0)),
                )
                CaptureForegroundService.ACTION_SAVED -> captureChannel?.invokeMethod("captureSaved", payload)
                CaptureForegroundService.ACTION_ERROR -> captureChannel?.invokeMethod(
                    "captureError",
                    mapOf("code" to intent.getStringExtra(CaptureForegroundService.EXTRA_ERROR)),
                )
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ReminderRuntimeBridge.configure(this, flutterEngine)
        captureChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "configureTrigger" -> {
                        val key = call.argument<String>("key") ?: "volume_up"
                        val keyCode = if (key == "volume_down") KeyEvent.KEYCODE_VOLUME_DOWN else KeyEvent.KEYCODE_VOLUME_UP
                        val count = call.argument<Int>("pressCount") ?: SidekickAccessibilityService.DEFAULT_PRESS_COUNT
                        val window = call.argument<Number>("windowMs")?.toLong() ?: SidekickAccessibilityService.DEFAULT_WINDOW_MS
                        val committed = getSharedPreferences(SidekickAccessibilityService.TRIGGER_PREFS, MODE_PRIVATE)
                            .edit()
                            .putInt(SidekickAccessibilityService.KEY_CODE, keyCode)
                            .putInt(SidekickAccessibilityService.PRESS_COUNT, count.coerceIn(1, 5))
                            .putLong(SidekickAccessibilityService.WINDOW_MS, window.coerceIn(300L, 2500L))
                            .commit()
                        result.success(committed)
                    }
                    "setCaptureOwner" -> {
                        NativeCaptureStore(this@MainActivity).setConfiguredOwner(
                            call.argument<String>("ownerId"),
                        )
                        result.success(null)
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }
                    "isAccessibilityEnabled" -> result.success(isCaptureAccessibilityEnabled())
                    "startCapture" -> {
                        ContextCompat.startForegroundService(
                            this@MainActivity,
                            Intent(this@MainActivity, CaptureForegroundService::class.java)
                                .setAction(CaptureForegroundService.ACTION_START),
                        )
                        result.success(null)
                    }
                    "stopCapture" -> {
                        startService(
                            Intent(this@MainActivity, CaptureForegroundService::class.java)
                                .setAction(CaptureForegroundService.ACTION_STOP),
                        )
                        result.success(null)
                    }
                    "cancelCapture" -> {
                        startService(
                            Intent(this@MainActivity, CaptureForegroundService::class.java)
                                .setAction(CaptureForegroundService.ACTION_CANCEL),
                        )
                        result.success(null)
                    }
                    "getCaptureState" -> {
                        val store = NativeCaptureStore(this@MainActivity)
                        if (!CaptureRuntimeGuard.hasLiveCapture) store.recoverInterrupted()
                        result.success(
                            mapOf(
                                "isRecording" to CaptureForegroundService.isRecording,
                                "active" to store.active()?.toMap(),
                            ),
                        )
                    }
                    "getPendingCaptureEvents" -> {
                        val store = NativeCaptureStore(this@MainActivity)
                        if (!CaptureRuntimeGuard.hasLiveCapture) store.recoverInterrupted()
                        result.success(
                            store.pending(call.argument<String>("ownerId")).map { it.toMap() },
                        )
                    }
                    "ackCaptureEvent" -> {
                        call.argument<String>("eventId")?.let {
                            NativeCaptureStore(this@MainActivity).acknowledge(it)
                        }
                        result.success(null)
                    }
                    "retryFailedCaptures" -> {
                        val ownerId = call.argument<String>("ownerId")
                        result.success(
                            if (ownerId == null) emptyList<Map<String, Any?>>()
                            else NativeCaptureStore(this@MainActivity)
                                .retryFailed(ownerId)
                                .map { it.toMap() },
                        )
                    }
                    else -> result.notImplemented()
                }
            }
        }
        registerCaptureReceiver()
    }

    @Deprecated("Deprecated in Android; retained for the document picker contract.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (ReminderRuntimeBridge.onReminderSoundPickerResult(this, requestCode, resultCode, data)) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ReminderRuntimeBridge.detachReminderSoundPicker()
        captureChannel?.setMethodCallHandler(null)
        captureChannel = null
        if (receiverRegistered) {
            unregisterReceiver(captureReceiver)
            receiverRegistered = false
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun registerCaptureReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(CaptureForegroundService.ACTION_STARTED)
            addAction(CaptureForegroundService.ACTION_LEVEL)
            addAction(CaptureForegroundService.ACTION_SAVED)
            addAction(CaptureForegroundService.ACTION_ERROR)
        }
        ContextCompat.registerReceiver(this, captureReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        receiverRegistered = true
    }

    private fun isCaptureAccessibilityEnabled(): Boolean {
        val manager = getSystemService(ACCESSIBILITY_SERVICE) as AccessibilityManager
        return manager.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK).any {
            it.resolveInfo.serviceInfo.packageName == packageName &&
                it.resolveInfo.serviceInfo.name == SidekickAccessibilityService::class.java.name
        }
    }

    companion object {
        const val CHANNEL_NAME = "com.sidekick/capture"
        const val EXTRA_SHOW_CAPTURE = "show_capture"
    }
}
