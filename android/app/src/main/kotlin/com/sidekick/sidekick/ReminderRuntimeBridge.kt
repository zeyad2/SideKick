package com.sidekick.sidekick

import android.app.PendingIntent
import android.app.AlarmManager
import android.app.Activity
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.location.LocationListener
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.TimeZone

object ReminderRuntimeBridge {
    private const val CHANNEL_NAME = "com.sidekick/reminders"
    private const val PREFS = "sidekick_reminder_runtime"
    private const val KEY_GEOFENCES = "geofences"
    private const val KEY_ACTIONS = "actions"
    private const val KEY_ACTION_SEQ = "action_seq"
    private const val KEY_INT_IDS = "int_ids"
    private const val KEY_INT_SEQ = "int_seq"
    private const val KEY_DWELL = "dwell"
    private const val KEY_TIME_REMINDERS = "time_reminders"
    private val prefsLock = Any()
    private var pendingSoundPickerResult: MethodChannel.Result? = null

    @Volatile
    internal var forceCommitFailureForTesting = false

    fun configure(context: Context, flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "registerGeofence" -> {
                        val id = call.argument<String>("id")
                        val lat = call.argument<Double>("lat")
                        val lng = call.argument<Double>("lng")
                        val radiusM = call.argument<Int>("radiusM") ?: 150
                        val transition = call.argument<String>("transition") ?: "enter"
                        if (id == null || lat == null || lng == null) {
                            result.error("invalid_geofence", "Missing reminder id or coordinates.", null)
                            return@setMethodCallHandler
                        }
                        runCatching {
                            registerGeofence(
                                context = context.applicationContext,
                                id = id,
                                title = call.argument<String>("title") ?: "Sidekick reminder",
                                details = call.argument<String>("details"),
                                lat = lat,
                                lng = lng,
                                radiusM = radiusM,
                                transition = transition,
                                dwellSeconds = call.argument<Int>("dwellSeconds") ?: 60,
                            )
                        }.onSuccess {
                            result.success(null)
                        }.onFailure {
                            result.error("geofence_register_failed", it.message, null)
                        }
                    }
                    "cancelGeofence" -> {
                        call.argument<String>("id")?.let {
                            cancelGeofence(context.applicationContext, it)
                        }
                        result.success(null)
                    }
                    "scheduleTimeReminder" -> {
                        val id = call.argument<String>("id")
                        val triggerAtMs = call.argument<Number>("triggerAtMs")?.toLong()
                        if (id == null || triggerAtMs == null) {
                            result.error("invalid_time_reminder", "Missing reminder id or trigger timestamp.", null)
                            return@setMethodCallHandler
                        }
                        scheduleTimeReminder(
                            context = context.applicationContext,
                            id = id,
                            title = call.argument<String>("title") ?: "Sidekick reminder",
                            details = call.argument<String>("details"),
                            triggerAtMs = triggerAtMs,
                            notificationId = call.argument<Int>("notificationId"),
                        )
                        result.success(null)
                    }
                    "cancelTimeReminder" -> {
                        call.argument<String>("id")?.let {
                            cancelTimeReminder(
                                context.applicationContext,
                                it,
                                call.argument<Int>("notificationId"),
                            )
                        }
                        result.success(null)
                    }
                    "managedNotificationId" -> {
                        val id = call.argument<String>("id")
                        if (id == null) {
                            result.error("invalid_id", "Missing id.", null)
                        } else {
                            result.success(managedNotificationId(context.applicationContext, id))
                        }
                    }
                    "managedRequestCode" -> {
                        val key = call.argument<String>("key")
                        if (key == null) {
                            result.error("invalid_key", "Missing key.", null)
                        } else {
                            result.success(managedRequestCode(context.applicationContext, key))
                        }
                    }
                    "drainNativeActions" -> {
                        result.success(drainNativeActions(context.applicationContext))
                    }
                    "currentLocation" -> currentLocation(context.applicationContext, result)
                    "currentTimeZoneName" -> result.success(TimeZone.getDefault().id)
                    "getReminderSoundState" -> result.success(
                        ReminderSoundStore.state(context.applicationContext),
                    )
                    "downloadReminderSound" -> {
                        val id = call.argument<String>("id")
                        if (id == null) {
                            result.error("invalid_sound", "Missing reminder sound id.", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            val outcome = runCatching {
                                ReminderSoundStore.download(context.applicationContext, id)
                            }
                            Handler(Looper.getMainLooper()).post {
                                outcome.onSuccess { result.success(null) }
                                    .onFailure { result.error("sound_download_failed", it.message, null) }
                            }
                        }.start()
                    }
                    "selectReminderSound" -> resultOf(result, "sound_select_failed") {
                        ReminderSoundStore.select(
                            context.applicationContext,
                            call.argument<String>("id") ?: "system",
                        )
                    }
                    "previewReminderSound" -> resultOf(result, "sound_preview_failed") {
                        ReminderSoundStore.preview(
                            context.applicationContext,
                            call.argument<String>("id") ?: "system",
                        )
                    }
                    "deleteReminderSound" -> resultOf(result, "sound_delete_failed") {
                        ReminderSoundStore.delete(
                            context.applicationContext,
                            call.argument<String>("id")
                                ?: throw IllegalArgumentException("Missing reminder sound id."),
                        )
                    }
                    "pickLocalReminderSound" -> {
                        val activity = context as? Activity
                        if (activity == null) {
                            result.error("sound_picker_unavailable", "No Android activity is available.", null)
                        } else if (pendingSoundPickerResult != null) {
                            result.error("sound_picker_busy", "The sound picker is already open.", null)
                        } else {
                            pendingSoundPickerResult = result
                            activity.startActivityForResult(
                                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "audio/*"
                                },
                                REQUEST_REMINDER_SOUND,
                            )
                        }
                    }
                    "ackNativeAction" -> {
                        val actionId = call.argument<String>("actionId")
                        if (actionId != null) acknowledgeNativeAction(context.applicationContext, actionId)
                        result.success(null)
                    }
                    "enqueueNativeAction" -> {
                        val id = call.argument<String>("id")
                        val action = call.argument<String>("action")
                        if (id == null || action == null) {
                            result.error("invalid_action", "Missing reminder id or action.", null)
                            return@setMethodCallHandler
                        }
                        enqueueNativeAction(
                            context.applicationContext,
                            id,
                            action,
                            call.argument<Number>("rescheduleAtMs")?.toLong(),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    fun onReminderSoundPickerResult(
        context: Context,
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != REQUEST_REMINDER_SOUND) return false
        val pending = pendingSoundPickerResult ?: return true
        pendingSoundPickerResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(null)
            return true
        }
        Thread {
            val outcome = runCatching {
                ReminderSoundStore.importLocal(context.applicationContext, uri)
            }
            Handler(Looper.getMainLooper()).post {
                outcome.onSuccess { pending.success(null) }
                    .onFailure { pending.error("sound_import_failed", it.message, null) }
            }
        }.start()
        return true
    }

    fun detachReminderSoundPicker() {
        pendingSoundPickerResult?.error(
            "sound_picker_closed",
            "The sound picker closed with the app.",
            null,
        )
        pendingSoundPickerResult = null
        ReminderSoundStore.stopPreview()
    }

    private fun resultOf(
        result: MethodChannel.Result,
        code: String,
        operation: () -> Unit,
    ) {
        runCatching(operation)
            .onSuccess { result.success(null) }
            .onFailure { result.error(code, it.message, null) }
    }

    private fun registerGeofence(
        context: Context,
        id: String,
        title: String,
        details: String?,
        lat: Double,
        lng: Double,
        radiusM: Int,
        transition: String,
        dwellSeconds: Int,
    ) {
        if (!hasLocationPermission(context)) {
            throw SecurityException("background_location_permission_denied")
        }
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        @Suppress("DEPRECATION")
        manager.addProximityAlert(
            lat,
            lng,
            radiusM.toFloat(),
            -1L,
            pendingIntent(context, id, title, details, transition, dwellSeconds)
                ?: return,
        )
        saveGeofence(context, id, title, details, lat, lng, radiusM, transition, dwellSeconds)
    }

    private fun hasLocationPermission(context: Context): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val background = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_BACKGROUND_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
        return fine && background
    }

    private fun currentLocation(context: Context, result: MethodChannel.Result) {
        val fine = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        if (!fine && !coarse) {
            result.error("location_permission_denied", "Location permission is required.", null)
            return
        }

        val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val provider = when {
            fine && manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ->
                LocationManager.GPS_PROVIDER
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ->
                LocationManager.NETWORK_PROVIDER
            else -> null
        }
        if (provider == null) {
            result.error("location_disabled", "Turn on location services and try again.", null)
            return
        }

        val handler = Handler(Looper.getMainLooper())
        var completed = false
        fun finish(location: android.location.Location?) {
            if (completed) return
            completed = true
            if (location == null) {
                result.error("location_unavailable", "Could not determine your current location.", null)
            } else {
                result.success(mapOf("lat" to location.latitude, "lng" to location.longitude))
            }
        }

        val fallback = runCatching { manager.getLastKnownLocation(provider) }.getOrNull()
        handler.postDelayed({ finish(fallback) }, 12_000L)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            manager.getCurrentLocation(provider, null, context.mainExecutor) { finish(it ?: fallback) }
            return
        }

        @Suppress("DEPRECATION")
        manager.requestSingleUpdate(
            provider,
            object : LocationListener {
                override fun onLocationChanged(location: android.location.Location) = finish(location)
                @Deprecated("Deprecated in Android")
                override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
                override fun onProviderEnabled(provider: String) = Unit
                override fun onProviderDisabled(provider: String) = Unit
            },
            Looper.getMainLooper(),
        )
    }

    fun cancelGeofence(context: Context, id: String) {
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        @Suppress("DEPRECATION")
        val existing = pendingIntent(
            context,
            id,
            "Sidekick reminder",
            null,
            "enter",
            60,
            PendingIntent.FLAG_NO_CREATE,
        )
        if (existing != null) manager.removeProximityAlert(
            existing,
        )
        removeGeofence(context, id)
    }

    fun restoreGeofences(context: Context) {
        val records = geofenceRecords(context)
        for (i in 0 until records.length()) {
            val record = records.optJSONObject(i) ?: continue
            runCatching {
                registerGeofence(
                    context = context.applicationContext,
                    id = record.getString("id"),
                    title = record.optString("title", "Sidekick reminder"),
                    details = record.optString("details").ifBlank { null },
                    lat = record.getDouble("lat"),
                    lng = record.getDouble("lng"),
                    radiusM = record.optInt("radiusM", 150),
                    transition = record.optString("transition", "enter"),
                    dwellSeconds = record.optInt("dwellSeconds", 60),
                )
            }
        }
    }

    fun scheduleTimeReminder(
        context: Context,
        id: String,
        title: String,
        details: String?,
        triggerAtMs: Long,
        notificationId: Int? = null,
    ) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = timePendingIntent(context, id, title, details, notificationId) ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarm.canScheduleExactAlarms()) {
            alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pending)
        } else {
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pending)
        }
        saveTimeReminder(context, id, title, details, triggerAtMs, notificationId)
    }

    fun cancelTimeReminder(context: Context, id: String, notificationId: Int? = null) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = timePendingIntent(
            context = context,
            id = id,
            title = "Sidekick reminder",
            details = null,
            notificationId = notificationId,
            lookupFlag = PendingIntent.FLAG_NO_CREATE,
        )
        if (pending != null) alarm.cancel(pending)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        manager.cancel(notificationId ?: managedNotificationId(context, id))
        removeTimeReminder(context, id)
    }

    fun restoreTimeReminders(context: Context) {
        val now = System.currentTimeMillis()
        val records = timeReminderRecords(context)
        for (i in 0 until records.length()) {
            val record = records.optJSONObject(i) ?: continue
            val triggerAtMs = record.optLong("triggerAtMs")
            if (triggerAtMs <= now) continue
            scheduleTimeReminder(
                context = context.applicationContext,
                id = record.getString("id"),
                title = record.optString("title", "Sidekick reminder"),
                details = record.optString("details").ifBlank { null },
                triggerAtMs = triggerAtMs,
                notificationId = record.optInt("notificationId").takeIf { it > 0 },
            )
        }
    }

    fun enqueueNativeAction(
        context: Context,
        reminderId: String,
        action: String,
        rescheduleAtMs: Long? = null,
        source: String = "native_notification",
    ): String {
        synchronized(prefsLock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val actions = JSONArray(prefs.getString(KEY_ACTIONS, "[]") ?: "[]")
            val seq = prefs.getLong(KEY_ACTION_SEQ, 0L) + 1L
            val actionId = "$reminderId:$action:$seq"
            actions.put(
                JSONObject()
                    .put("actionId", actionId)
                    .put("id", reminderId)
                    .put("action", action)
                    .put("source", source)
                    .put("recordedAtMs", System.currentTimeMillis()),
            )
            if (rescheduleAtMs != null) {
                actions.getJSONObject(actions.length() - 1)
                    .put("rescheduleAtMs", rescheduleAtMs)
            }
            commitChecked(
                prefs.edit()
                    .putLong(KEY_ACTION_SEQ, seq)
                    .putString(KEY_ACTIONS, actions.toString()),
                "native action journal enqueue",
            )
            return actionId
        }
    }

    fun acknowledgeNativeAction(context: Context, actionId: String) {
        synchronized(prefsLock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val actions = JSONArray(prefs.getString(KEY_ACTIONS, "[]") ?: "[]")
            val kept = JSONArray()
            for (i in 0 until actions.length()) {
                val action = actions.optJSONObject(i) ?: continue
                if (action.optString("actionId") != actionId) kept.put(action)
            }
            commitChecked(
                prefs.edit().putString(KEY_ACTIONS, kept.toString()),
                "native action journal ack",
            )
        }
    }

    fun drainNativeActions(context: Context): List<Map<String, Any?>> {
        synchronized(prefsLock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val actions = JSONArray(prefs.getString(KEY_ACTIONS, "[]") ?: "[]")
            return (0 until actions.length()).mapNotNull { index ->
                val action = actions.optJSONObject(index) ?: return@mapNotNull null
                mapOf(
                    "actionId" to action.optString("actionId"),
                    "id" to action.optString("id"),
                    "action" to action.optString("action"),
                    "source" to action.optString("source"),
                    "recordedAtMs" to action.optLong("recordedAtMs"),
                    "rescheduleAtMs" to action.optLong("rescheduleAtMs")
                        .takeIf { action.has("rescheduleAtMs") },
                )
            }
        }
    }

    private fun saveGeofence(
        context: Context,
        id: String,
        title: String,
        details: String?,
        lat: Double,
        lng: Double,
        radiusM: Int,
        transition: String,
        dwellSeconds: Int,
    ) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val records = geofenceRecords(context)
        val kept = JSONArray()
        for (i in 0 until records.length()) {
            val record = records.optJSONObject(i) ?: continue
            if (record.optString("id") != id) kept.put(record)
        }
        kept.put(
            JSONObject()
                .put("id", id)
                .put("title", title)
                .put("details", details)
                .put("lat", lat)
                .put("lng", lng)
                .put("radiusM", radiusM)
                .put("transition", transition)
                .put("dwellSeconds", dwellSeconds),
        )
        prefs.edit().putString(KEY_GEOFENCES, kept.toString()).apply()
    }

    private fun removeGeofence(context: Context, id: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val records = geofenceRecords(context)
        val kept = JSONArray()
        for (i in 0 until records.length()) {
            val record = records.optJSONObject(i) ?: continue
            if (record.optString("id") != id) kept.put(record)
        }
        prefs.edit().putString(KEY_GEOFENCES, kept.toString()).apply()
    }

    private fun geofenceRecords(context: Context): JSONArray {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return JSONArray(prefs.getString(KEY_GEOFENCES, "[]") ?: "[]")
    }

    private fun saveTimeReminder(
        context: Context,
        id: String,
        title: String,
        details: String?,
        triggerAtMs: Long,
        notificationId: Int?,
    ) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val records = timeReminderRecords(context)
        val kept = JSONArray()
        for (i in 0 until records.length()) {
            val record = records.optJSONObject(i) ?: continue
            if (record.optString("id") != id) kept.put(record)
        }
        kept.put(
            JSONObject()
                .put("id", id)
                .put("title", title)
                .put("details", details)
                .put("triggerAtMs", triggerAtMs)
                .put("notificationId", notificationId ?: managedNotificationId(context, id)),
        )
        prefs.edit().putString(KEY_TIME_REMINDERS, kept.toString()).apply()
    }

    private fun removeTimeReminder(context: Context, id: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val records = timeReminderRecords(context)
        val kept = JSONArray()
        for (i in 0 until records.length()) {
            val record = records.optJSONObject(i) ?: continue
            if (record.optString("id") != id) kept.put(record)
        }
        prefs.edit().putString(KEY_TIME_REMINDERS, kept.toString()).apply()
    }

    private fun timeReminderRecords(context: Context): JSONArray {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return JSONArray(prefs.getString(KEY_TIME_REMINDERS, "[]") ?: "[]")
    }

    private fun pendingIntent(
        context: Context,
        id: String,
        title: String,
        details: String?,
        transition: String,
        dwellSeconds: Int,
        lookupFlag: Int = 0,
    ): PendingIntent? {
        val intent = Intent(context, ReminderGeofenceReceiver::class.java)
            .setAction("com.sidekick.sidekick.reminder.GEOFENCE")
            .setData(Uri.parse("sidekick://geofence/$id/$transition"))
            .putExtra(ReminderGeofenceReceiver.EXTRA_REMINDER_ID, id)
            .putExtra(ReminderGeofenceReceiver.EXTRA_TITLE, title)
            .putExtra(ReminderGeofenceReceiver.EXTRA_DETAILS, details)
            .putExtra(ReminderGeofenceReceiver.EXTRA_TRANSITION, transition)
            .putExtra(ReminderGeofenceReceiver.EXTRA_DWELL_SECONDS, dwellSeconds)
        return PendingIntent.getBroadcast(
            context,
            managedIntId(context, "geofence:$id"),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE or lookupFlag,
        )
    }

    fun managedNotificationId(context: Context, id: String): Int =
        managedIntId(context, "notification:$id")

    fun managedRequestCode(context: Context, key: String): Int =
        managedIntId(context, "request:$key")

    private fun timePendingIntent(
        context: Context,
        id: String,
        title: String,
        details: String?,
        notificationId: Int?,
        lookupFlag: Int = 0,
    ): PendingIntent? {
        val intent = Intent(context, ReminderGeofenceReceiver::class.java)
            .setAction(ReminderGeofenceReceiver.ACTION_TIME_ELAPSED)
            .setData(Uri.parse("sidekick://time/$id"))
            .putExtra(ReminderGeofenceReceiver.EXTRA_REMINDER_ID, id)
            .putExtra(ReminderGeofenceReceiver.EXTRA_TITLE, title)
            .putExtra(ReminderGeofenceReceiver.EXTRA_DETAILS, details)
            .putExtra(ReminderGeofenceReceiver.EXTRA_NOTIFICATION_ID, notificationId ?: managedNotificationId(context, id))
        return PendingIntent.getBroadcast(
            context,
            managedRequestCode(context, "$id:time"),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE or lookupFlag,
        )
    }

    private fun managedIntId(context: Context, key: String): Int {
        synchronized(prefsLock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val ids = JSONObject(prefs.getString(KEY_INT_IDS, "{}") ?: "{}")
            if (ids.has(key)) return ids.getInt(key)
            val used = mutableSetOf<Int>()
            val names = ids.keys()
            while (names.hasNext()) used.add(ids.optInt(names.next()))
            var next = prefs.getInt(KEY_INT_SEQ, 1000) + 1
            while (next <= 0 || used.contains(next)) next++
            ids.put(key, next)
            commitChecked(
                prefs.edit()
                    .putInt(KEY_INT_SEQ, next)
                    .putString(KEY_INT_IDS, ids.toString()),
                "managed integer id allocation",
            )
            return next
        }
    }

    private fun commitChecked(editor: android.content.SharedPreferences.Editor, operation: String) {
        val forcedFailure = forceCommitFailureForTesting
        if (forcedFailure) forceCommitFailureForTesting = false
        if (forcedFailure || !editor.commit()) {
            throw IllegalStateException("Failed to durably commit $operation")
        }
    }

    private const val REQUEST_REMINDER_SOUND = 7401

    fun recordDwellTransition(
        context: Context,
        reminderId: String,
        expectedTransition: String,
        actualTransition: String,
        dwellSeconds: Int,
        nowMs: Long = System.currentTimeMillis(),
    ): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val dwell = JSONObject(prefs.getString(KEY_DWELL, "{}") ?: "{}")
        if (actualTransition != expectedTransition) {
            dwell.remove(reminderId)
            prefs.edit().putString(KEY_DWELL, dwell.toString()).apply()
            return false
        }
        dwell.put(
            reminderId,
            JSONObject()
                .put("transition", expectedTransition)
                .put("startedAtMs", nowMs)
                .put("dwellSeconds", dwellSeconds),
        )
        prefs.edit().putString(KEY_DWELL, dwell.toString()).apply()
        return true
    }

    fun isDwellReady(
        context: Context,
        reminderId: String,
        expectedTransition: String,
        nowMs: Long = System.currentTimeMillis(),
    ): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val dwell = JSONObject(prefs.getString(KEY_DWELL, "{}") ?: "{}")
        val record = dwell.optJSONObject(reminderId) ?: return false
        if (record.optString("transition") != expectedTransition) return false
        val startedAt = record.optLong("startedAtMs")
        val dwellSeconds = record.optInt("dwellSeconds", 60)
        return nowMs - startedAt >= dwellSeconds * 1000L
    }

    fun clearDwell(context: Context, reminderId: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val dwell = JSONObject(prefs.getString(KEY_DWELL, "{}") ?: "{}")
        dwell.remove(reminderId)
        prefs.edit().putString(KEY_DWELL, dwell.toString()).apply()
    }

    fun cancelDwellAlarm(context: Context, reminderId: String) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        val intent = Intent(context, ReminderGeofenceReceiver::class.java)
            .setAction(ReminderGeofenceReceiver.ACTION_DWELL_ELAPSED)
            .setData(Uri.parse("sidekick://dwell/$reminderId"))
        val pending = PendingIntent.getBroadcast(
            context,
            managedRequestCode(context, "$reminderId:dwell"),
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        if (pending != null) {
            alarm.cancel(pending)
        }
    }
}
