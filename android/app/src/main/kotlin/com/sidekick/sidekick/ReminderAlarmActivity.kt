package com.sidekick.sidekick

import android.app.Activity
import android.app.DatePickerDialog
import android.app.NotificationManager
import android.app.TimePickerDialog
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.DatePicker
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Space
import android.widget.TextView
import android.widget.TimePicker
import android.widget.Toast
import java.text.DateFormat
import java.util.Calendar
import java.util.Date

/**
 * Native by design: this screen can appear over the lock screen without waiting
 * for Flutter to boot, and still works if the app process had been killed.
 */
class ReminderAlarmActivity : Activity() {
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    private val reminderId: String by lazy {
        intent.getStringExtra(ReminderGeofenceReceiver.EXTRA_REMINDER_ID).orEmpty()
    }
    private val titleText: String by lazy {
        intent.getStringExtra(ReminderGeofenceReceiver.EXTRA_TITLE) ?: "Sidekick reminder"
    }
    private val detailsText: String? by lazy {
        intent.getStringExtra(ReminderGeofenceReceiver.EXTRA_DETAILS)
    }
    private val sansTypeface: Typeface by lazy {
        typefaceFromFlutterAssets("DMSans-Regular.ttf", Typeface.SANS_SERIF)
    }
    private val sansMediumTypeface: Typeface by lazy {
        typefaceFromFlutterAssets("DMSans-Medium.ttf", Typeface.DEFAULT_BOLD)
    }
    private val serifTypeface: Typeface by lazy {
        typefaceFromFlutterAssets("DMSerifDisplay-Italic.ttf", Typeface.SERIF)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureAlarmWindow()
        setContentView(alarmView())
        startAlarmSound()
    }

    override fun onDestroy() {
        stopAlarmSound()
        super.onDestroy()
    }

    @Deprecated("Alarm dismissal requires an explicit action.")
    override fun onBackPressed() = Unit

    private fun configureAlarmWindow() {
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
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.statusBarColor = BACKGROUND
        window.navigationBarColor = BACKGROUND
    }

    private fun alarmView(): View {
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            setBackgroundColor(BACKGROUND)
            clipToPadding = false
        }
        val page = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(20), dp(36), dp(20), dp(24))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        page.addView(personaOrb())
        page.addView(space(18))
        page.addView(label("IT'S TIME", 12f, PRIMARY).apply { letterSpacing = 0.16f })
        page.addView(space(12))
        page.addView(label(titleText, 38f, ON_SURFACE, serif = true).apply {
            gravity = Gravity.CENTER
            maxLines = 3
        })

        if (!detailsText.isNullOrBlank()) {
            page.addView(space(20))
            page.addView(detailsCard(detailsText!!))
        }

        page.addView(space(20))
        page.addView(label(
            DateFormat.getTimeInstance(DateFormat.SHORT).format(Date()),
            15f,
            ON_SURFACE_VARIANT,
            medium = true,
        ))
        page.addView(space(32))
        page.addView(label("Need a little runway?", 19f, ON_SURFACE, medium = true).apply {
            gravity = Gravity.START
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
        })
        page.addView(space(6))
        page.addView(label("Snooze it without losing the thread.", 14f, ON_SURFACE_VARIANT).apply {
            gravity = Gravity.START
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
        })
        page.addView(space(16))
        page.addView(snoozeGrid())
        page.addView(space(12))
        page.addView(actionButton(
            label = "Choose another date & time",
            fill = SURFACE_CONTAINER_HIGH,
            foreground = ON_SURFACE,
            stroke = OUTLINE_VARIANT,
            onClick = ::chooseNewDateAndTime,
        ))

        page.addView(Space(this).apply { minimumHeight = dp(28) }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            0,
            1f,
        ))
        page.addView(actionButton(
            label = "Done",
            fill = PRIMARY,
            foreground = ON_PRIMARY,
            onClick = { finishWithAction("done") },
        ))
        page.addView(space(10))
        page.addView(actionButton(
            label = "Dismiss reminder",
            fill = Color.TRANSPARENT,
            foreground = ON_SURFACE_VARIANT,
            onClick = { finishWithAction("dismiss") },
        ))

        scroll.addView(page)
        return scroll
    }

    private fun personaOrb() = FrameLayout(this).apply {
        background = roundedDrawable(PRIMARY_CONTAINER, radius = 999)
        contentDescription = "Sidekick"
        layoutParams = LinearLayout.LayoutParams(dp(52), dp(52))
        addView(label("S", 22f, ON_PRIMARY_CONTAINER, serif = true).apply {
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        })
    }

    private fun detailsCard(details: String) = label(details, 16f, ON_SURFACE_VARIANT).apply {
        gravity = Gravity.CENTER
        setPadding(dp(18), dp(15), dp(18), dp(15))
        background = roundedDrawable(SURFACE_CONTAINER, OUTLINE_VARIANT, 12)
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
    }

    private fun snoozeGrid() = GridLayout(this).apply {
        columnCount = 2
        rowCount = 2
        alignmentMode = GridLayout.ALIGN_BOUNDS
        useDefaultMargins = false
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        QUICK_SNOOZE_MINUTES.forEachIndexed { index, minutes ->
            addView(actionButton(
                label = "$minutes minutes",
                fill = SURFACE_CONTAINER,
                foreground = PRIMARY_FIXED,
                stroke = OUTLINE_VARIANT,
                height = 58,
                onClick = { rescheduleAfter(minutes) },
            ), GridLayout.LayoutParams(
                GridLayout.spec(index / 2),
                GridLayout.spec(index % 2, 1f),
            ).apply {
                width = 0
                height = dp(66)
                val halfGap = dp(5)
                setMargins(
                    if (index % 2 == 0) 0 else halfGap,
                    0,
                    if (index % 2 == 0) halfGap else 0,
                    dp(8),
                )
            })
        }
    }

    private fun rescheduleAfter(minutes: Int) {
        scheduleAndFinish(quickRescheduleAt(System.currentTimeMillis(), minutes))
    }

    private fun chooseNewDateAndTime() {
        stopAlarmSound()
        val initial = Calendar.getInstance().apply { add(Calendar.MINUTE, 30) }
        DatePickerDialog(
            this,
            { _: DatePicker, year: Int, month: Int, day: Int ->
                showTimePicker(year, month, day, initial)
            },
            initial.get(Calendar.YEAR),
            initial.get(Calendar.MONTH),
            initial.get(Calendar.DAY_OF_MONTH),
        ).also { dialog ->
            dialog.setTitle("Choose a date")
            dialog.setOnCancelListener { startAlarmSound() }
            dialog.setOnShowListener {
                dialog.getButton(DatePickerDialog.BUTTON_POSITIVE).text = "Next: choose time"
            }
            dialog.datePicker.minDate = System.currentTimeMillis() - 1_000L
            dialog.show()
        }
    }

    private fun showTimePicker(year: Int, month: Int, day: Int, initial: Calendar) {
        TimePickerDialog(
            this,
            { _: TimePicker, hour: Int, minute: Int ->
                val triggerAtMs = customRescheduleAt(year, month, day, hour, minute)
                if (triggerAtMs <= System.currentTimeMillis()) {
                    Toast.makeText(this, "Choose a time in the future", Toast.LENGTH_LONG).show()
                    startAlarmSound()
                } else {
                    scheduleAndFinish(triggerAtMs)
                }
            },
            initial.get(Calendar.HOUR_OF_DAY),
            initial.get(Calendar.MINUTE),
            false,
        ).also { dialog ->
            dialog.setTitle("Choose a time")
            dialog.setOnCancelListener { startAlarmSound() }
            dialog.setOnShowListener {
                dialog.getButton(TimePickerDialog.BUTTON_POSITIVE).text = "Reschedule"
            }
            dialog.show()
        }
    }

    private fun scheduleAndFinish(triggerAtMs: Long) {
        ReminderRuntimeBridge.scheduleTimeReminder(
            context = applicationContext,
            id = reminderId,
            title = titleText,
            details = detailsText,
            triggerAtMs = triggerAtMs,
        )
        finishWithAction("reschedule", triggerAtMs)
    }

    private fun finishWithAction(action: String, rescheduleAtMs: Long? = null) {
        if (action != "reschedule") {
            ReminderRuntimeBridge.cancelTimeReminder(applicationContext, reminderId)
        }
        runCatching {
            ReminderRuntimeBridge.enqueueNativeAction(
                applicationContext,
                reminderId,
                action,
                rescheduleAtMs,
                "native_alarm",
            )
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(ReminderRuntimeBridge.managedNotificationId(this, reminderId))
        stopAlarmSound()
        finishAndRemoveTask()
    }

    private fun startAlarmSound() {
        if (player != null) return
        val alarmUri = runCatching { ReminderSoundStore.selectedUri(this) }
            .getOrElse {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            }
        player = runCatching {
            MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                setDataSource(this@ReminderAlarmActivity, alarmUri)
                isLooping = true
                prepare()
                start()
            }
        }.getOrNull()
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0, 700, 450)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun stopAlarmSound() {
        runCatching { player?.stop() }
        player?.release()
        player = null
        vibrator?.cancel()
        vibrator = null
    }

    private fun label(
        value: String,
        size: Float,
        color: Int,
        medium: Boolean = false,
        serif: Boolean = false,
    ) = TextView(this).apply {
        text = value
        textSize = size
        setTextColor(color)
        typeface = when {
            serif -> serifTypeface
            medium -> sansMediumTypeface
            else -> sansTypeface
        }
        includeFontPadding = false
        setLineSpacing(0f, 1.15f)
    }

    private fun actionButton(
        label: String,
        fill: Int,
        foreground: Int,
        stroke: Int? = null,
        height: Int = 56,
        onClick: () -> Unit,
    ) = TextView(this).apply {
        text = label
        textSize = 15f
        typeface = sansMediumTypeface
        setTextColor(foreground)
        gravity = Gravity.CENTER
        isClickable = true
        isFocusable = true
        minHeight = dp(48)
        background = RippleDrawable(
            ColorStateList.valueOf(Color.argb(40, 255, 255, 255)),
            roundedDrawable(fill, stroke, 999),
            null,
        )
        setOnClickListener { onClick() }
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(height),
        )
    }

    private fun roundedDrawable(fill: Int, stroke: Int? = null, radius: Int) =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(fill)
            cornerRadius = dp(radius).toFloat()
            if (stroke != null) setStroke(dp(1), stroke)
        }

    private fun typefaceFromFlutterAssets(fileName: String, fallback: Typeface): Typeface =
        runCatching {
            Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/$fileName")
        }.getOrDefault(fallback)

    private fun space(height: Int) = Space(this).apply {
        layoutParams = LinearLayout.LayoutParams(1, dp(height))
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        internal val QUICK_SNOOZE_MINUTES = listOf(5, 10, 15, 30)

        internal fun quickRescheduleAt(nowMs: Long, minutes: Int): Long =
            nowMs + minutes * 60_000L

        internal fun customRescheduleAt(
            year: Int,
            month: Int,
            day: Int,
            hour: Int,
            minute: Int,
        ): Long = Calendar.getInstance().apply {
            set(year, month, day, hour, minute, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        private val BACKGROUND = Color.rgb(22, 19, 17)
        private val SURFACE_CONTAINER = Color.rgb(34, 31, 29)
        private val SURFACE_CONTAINER_HIGH = Color.rgb(45, 41, 39)
        private val ON_SURFACE = Color.rgb(233, 225, 221)
        private val ON_SURFACE_VARIANT = Color.rgb(216, 195, 175)
        private val OUTLINE_VARIANT = Color.rgb(83, 68, 53)
        private val PRIMARY = Color.rgb(255, 185, 99)
        private val ON_PRIMARY = Color.rgb(71, 42, 0)
        private val PRIMARY_CONTAINER = Color.rgb(212, 134, 10)
        private val ON_PRIMARY_CONTAINER = Color.rgb(71, 41, 0)
        private val PRIMARY_FIXED = Color.rgb(255, 221, 185)
    }
}
