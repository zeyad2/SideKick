package com.sidekick.sidekick

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.Calendar

@RunWith(RobolectricTestRunner::class)
class ReminderAlarmActivityTest {
    @Test
    fun quickSnoozeOptionsPrioritizeMinutes() {
        assertEquals(listOf(5, 10, 15, 30), ReminderAlarmActivity.QUICK_SNOOZE_MINUTES)

        val now = 1_800_000_000_000L
        assertEquals(now + 5 * 60_000L, ReminderAlarmActivity.quickRescheduleAt(now, 5))
        assertEquals(now + 30 * 60_000L, ReminderAlarmActivity.quickRescheduleAt(now, 30))
    }

    @Test
    fun customReschedulePreservesBothDateAndTime() {
        val result = Calendar.getInstance().apply {
            timeInMillis = ReminderAlarmActivity.customRescheduleAt(
                2027,
                Calendar.MARCH,
                14,
                16,
                45,
            )
        }

        assertEquals(2027, result.get(Calendar.YEAR))
        assertEquals(Calendar.MARCH, result.get(Calendar.MONTH))
        assertEquals(14, result.get(Calendar.DAY_OF_MONTH))
        assertEquals(16, result.get(Calendar.HOUR_OF_DAY))
        assertEquals(45, result.get(Calendar.MINUTE))
        assertEquals(0, result.get(Calendar.SECOND))
        assertEquals(0, result.get(Calendar.MILLISECOND))
    }
}
