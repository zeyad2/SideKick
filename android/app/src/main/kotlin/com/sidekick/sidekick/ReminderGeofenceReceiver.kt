package com.sidekick.sidekick

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject

class ReminderGeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_REMINDER_ACTION) {
            val reminderId = intent.getStringExtra(EXTRA_REMINDER_ID) ?: return
            val action = intent.getStringExtra(EXTRA_ACTION) ?: return
            val persisted = runCatching {
                ReminderRuntimeBridge.enqueueNativeAction(context, reminderId, action)
            }.isSuccess
            if (!persisted) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(ReminderRuntimeBridge.managedNotificationId(context, reminderId))
            if (action == "wrong_place") {
                val editIntent = Intent(context, MainActivity::class.java)
                    .setAction(Intent.ACTION_VIEW)
                    .setData(Uri.parse("sidekick://reminders/$reminderId/edit"))
                    .putExtra(EXTRA_EDIT_REMINDER_ID, reminderId)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                context.startActivity(editIntent)
            }
            return
        }
        val reminderId = intent.getStringExtra(EXTRA_REMINDER_ID) ?: return
        if (intent.action != ACTION_TIME_ELAPSED) {
            val expectedTransition = intent.getStringExtra(EXTRA_TRANSITION) ?: "enter"
            if (intent.action == ACTION_DWELL_ELAPSED) {
            if (!ReminderRuntimeBridge.isDwellReady(context, reminderId, expectedTransition)) return
            ReminderRuntimeBridge.clearDwell(context, reminderId)
            } else {
                val entering = intent.getBooleanExtra(LocationManager.KEY_PROXIMITY_ENTERING, true)
                val actualTransition = if (entering) "enter" else "exit"
                val dwellSeconds = intent.getIntExtra(EXTRA_DWELL_SECONDS, 60)
                val dwellStarted = ReminderRuntimeBridge.recordDwellTransition(
                    context = context,
                    reminderId = reminderId,
                    expectedTransition = expectedTransition,
                    actualTransition = actualTransition,
                    dwellSeconds = dwellSeconds,
                )
                if (!dwellStarted) {
                    ReminderRuntimeBridge.cancelDwellAlarm(context, reminderId)
                    return
                }
                if (dwellSeconds > 0) {
                    scheduleDwellNotification(context, intent, dwellSeconds)
                    return
                }
            }
        }

        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Sidekick reminder"
        val details = intent.getStringExtra(EXTRA_DETAILS)
        createChannel(context)
        if (!canPostNotifications(context)) return

        val payload = JSONObject()
            .put("id", reminderId)
            .put("action", "open")
            .toString()
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.putExtra("reminder_payload", payload)
            ?: Intent(context, MainActivity::class.java).putExtra("reminder_payload", payload)
        val openApp = PendingIntent.getActivity(
            context,
            ReminderRuntimeBridge.managedRequestCode(context, "$reminderId:open"),
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(
            ReminderRuntimeBridge.managedNotificationId(context, reminderId),
            NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(details ?: "Location reminder")
                .setContentIntent(openApp)
                .addAction(action(context, reminderId, "done", "Done"))
                .addAction(action(context, reminderId, "later", "Later"))
                .addAction(action(context, reminderId, "dismiss", "Dismiss"))
                .addAction(action(context, reminderId, "wrong_place", "Wrong place"))
                .setAutoCancel(true)
                .build(),
        )
    }

    private fun scheduleDwellNotification(context: Context, original: Intent, dwellSeconds: Int) {
        val dwellIntent = Intent(context, ReminderGeofenceReceiver::class.java)
            .setAction(ACTION_DWELL_ELAPSED)
            .setData(Uri.parse("sidekick://dwell/${original.getStringExtra(EXTRA_REMINDER_ID)}"))
            .putExtras(original)
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = PendingIntent.getBroadcast(
            context,
            ReminderRuntimeBridge.managedRequestCode(context, "${original.getStringExtra(EXTRA_REMINDER_ID)}:dwell"),
            dwellIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarm.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + dwellSeconds * 1000L,
            pending,
        )
    }

    private fun action(
        context: Context,
        reminderId: String,
        action: String,
        title: String,
    ): NotificationCompat.Action {
        val intent = Intent(context, ReminderGeofenceReceiver::class.java)
            .setAction(ACTION_REMINDER_ACTION)
            .setData(Uri.parse("sidekick://notification/$reminderId/$action"))
            .putExtra(EXTRA_REMINDER_ID, reminderId)
            .putExtra(EXTRA_ACTION, action)
        val pending = PendingIntent.getBroadcast(
            context,
            ReminderRuntimeBridge.managedRequestCode(context, "$reminderId:$action"),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Action.Builder(R.mipmap.ic_launcher, title, pending).build()
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Place reminders", NotificationManager.IMPORTANCE_DEFAULT),
        )
    }

    private fun canPostNotifications(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED

    companion object {
        const val EXTRA_REMINDER_ID = "reminder_id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_DETAILS = "details"
        const val EXTRA_TRANSITION = "transition"
        const val EXTRA_DWELL_SECONDS = "dwell_seconds"
        const val EXTRA_ACTION = "action"
        const val EXTRA_NOTIFICATION_ID = "notification_id"
        const val EXTRA_EDIT_REMINDER_ID = "edit_reminder_id"
        const val ACTION_REMINDER_ACTION = "com.sidekick.sidekick.reminder.ACTION"
        const val ACTION_DWELL_ELAPSED = "com.sidekick.sidekick.reminder.DWELL_ELAPSED"
        const val ACTION_TIME_ELAPSED = "com.sidekick.sidekick.reminder.TIME_ELAPSED"
        private const val CHANNEL_ID = "sidekick_place_reminders"
    }
}
