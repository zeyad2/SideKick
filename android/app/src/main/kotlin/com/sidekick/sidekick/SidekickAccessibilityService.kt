package com.sidekick.sidekick

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.SystemClock
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import androidx.core.content.ContextCompat

class SidekickAccessibilityService : AccessibilityService() {
    private val presses = ArrayDeque<Long>()

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit
    override fun onInterrupt() = Unit

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN || event.repeatCount != 0) return false
        val prefs = getSharedPreferences(TRIGGER_PREFS, MODE_PRIVATE)
        val configuredKey = prefs.getInt(KEY_CODE, KeyEvent.KEYCODE_VOLUME_UP)
        if (event.keyCode != configuredKey) return false

        val now = SystemClock.elapsedRealtime()
        val windowMs = prefs.getLong(WINDOW_MS, DEFAULT_WINDOW_MS)
        val pressCount = prefs.getInt(PRESS_COUNT, DEFAULT_PRESS_COUNT).coerceIn(1, 5)
        presses.addLast(now)
        while (presses.isNotEmpty() && now - presses.first() > windowMs) presses.removeFirst()
        if (presses.size < pressCount) return false

        presses.clear()
        val action = if (CaptureRuntimeGuard.hasLiveCapture) {
            CaptureForegroundService.ACTION_STOP
        } else {
            CaptureForegroundService.ACTION_START
        }
        ContextCompat.startForegroundService(
            this,
            Intent(this, CaptureForegroundService::class.java).setAction(action),
        )
        if (action == CaptureForegroundService.ACTION_START) {
            packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra(MainActivity.EXTRA_SHOW_CAPTURE, true)
                }?.let(::startActivity)
        }
        return true
    }

    companion object {
        const val TRIGGER_PREFS = "sidekick_capture_trigger"
        const val KEY_CODE = "key_code"
        const val PRESS_COUNT = "press_count"
        const val WINDOW_MS = "window_ms"
        const val DEFAULT_PRESS_COUNT = 3
        const val DEFAULT_WINDOW_MS = 900L
    }
}
