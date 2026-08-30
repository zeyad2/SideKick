package com.sidekick.sidekick

import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.Shadows.shadowOf
import org.robolectric.RobolectricTestRunner
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
class ReminderRuntimeBridgeTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences("sidekick_reminder_runtime", Context.MODE_PRIVATE)
            .edit().clear().commit()
        ReminderRuntimeBridge.forceCommitFailureForTesting = false
    }

    @Test
    fun nativeActionJournalDrainsWithoutDeletingAndAcksOneAction() {
        val doneId = ReminderRuntimeBridge.enqueueNativeAction(context, "r1", "done")
        val laterId = ReminderRuntimeBridge.enqueueNativeAction(context, "r1", "later")

        assertEquals(listOf(doneId, laterId), ReminderRuntimeBridge.drainNativeActions(context).map { it["actionId"] })
        assertEquals(listOf(doneId, laterId), ReminderRuntimeBridge.drainNativeActions(context).map { it["actionId"] })

        ReminderRuntimeBridge.acknowledgeNativeAction(context, doneId)

        assertEquals(listOf(laterId), ReminderRuntimeBridge.drainNativeActions(context).map { it["actionId"] })
    }

    @Test
    fun nativeAlarmJournalPersistsExactRescheduleTime() {
        val selected = 1_800_000_000_000L
        ReminderRuntimeBridge.enqueueNativeAction(
            context,
            "r1",
            "reschedule",
            selected,
            "native_alarm",
        )

        val action = ReminderRuntimeBridge.drainNativeActions(context).single()
        assertEquals("reschedule", action["action"])
        assertEquals("native_alarm", action["source"])
        assertEquals(selected, action["rescheduleAtMs"])
    }

    @Test
    fun managedIdsArePersistedAndCollisionFreeForDifferentKeys() {
        val first = ReminderRuntimeBridge.managedNotificationId(context, "b4a3ec07-c57b-49ba-a2e1-7dd1736c9cfc")
        val second = ReminderRuntimeBridge.managedNotificationId(context, "0cc85ee7-fcfa-4f1a-ad39-d3b10f00395c")

        assertNotEquals(first, second)
        assertEquals(first, ReminderRuntimeBridge.managedNotificationId(context, "b4a3ec07-c57b-49ba-a2e1-7dd1736c9cfc"))
        assertEquals(second, ReminderRuntimeBridge.managedNotificationId(context, "0cc85ee7-fcfa-4f1a-ad39-d3b10f00395c"))
    }

    @Test
    fun nativeActionJournalSerializesConcurrentEnqueuesWithoutLossOrDuplicateIds() {
        val count = 40
        val pool = Executors.newFixedThreadPool(8)
        val start = CountDownLatch(1)
        val done = CountDownLatch(count)
        val ids = Collections.synchronizedList(mutableListOf<String>())

        repeat(count) { index ->
            pool.execute {
                start.await()
                ids.add(ReminderRuntimeBridge.enqueueNativeAction(context, "r$index", "done"))
                done.countDown()
            }
        }
        start.countDown()

        assertTrue(done.await(5, TimeUnit.SECONDS))
        pool.shutdown()
        assertTrue(pool.awaitTermination(5, TimeUnit.SECONDS))
        val drained = ReminderRuntimeBridge.drainNativeActions(context)

        assertEquals(count, ids.toSet().size)
        assertEquals(count, drained.size)
        assertEquals(ids.toSet(), drained.map { it["actionId"] }.toSet())
    }

    @Test
    fun managedIdsSerializeConcurrentAllocationsWithoutDuplicateValues() {
        val count = 40
        val pool = Executors.newFixedThreadPool(8)
        val start = CountDownLatch(1)
        val done = CountDownLatch(count)
        val ids = ConcurrentHashMap<String, Int>()

        repeat(count) { index ->
            val reminderId = "reminder-$index"
            pool.execute {
                start.await()
                ids[reminderId] = ReminderRuntimeBridge.managedNotificationId(context, reminderId)
                done.countDown()
            }
        }
        start.countDown()

        assertTrue(done.await(5, TimeUnit.SECONDS))
        pool.shutdown()
        assertTrue(pool.awaitTermination(5, TimeUnit.SECONDS))

        assertEquals(count, ids.values.toSet().size)
        repeat(count) { index ->
            val reminderId = "reminder-$index"
            assertEquals(
                ids[reminderId],
                ReminderRuntimeBridge.managedNotificationId(context, reminderId),
            )
        }
    }

    @Test
    fun nativeActionCommitFailureDoesNotPersistOrLaunchWrongPlaceEdit() {
        ReminderRuntimeBridge.forceCommitFailureForTesting = true
        val intent = Intent(context, ReminderGeofenceReceiver::class.java)
            .setAction(ReminderGeofenceReceiver.ACTION_REMINDER_ACTION)
            .putExtra(ReminderGeofenceReceiver.EXTRA_REMINDER_ID, "r1")
            .putExtra(ReminderGeofenceReceiver.EXTRA_ACTION, "wrong_place")

        ReminderGeofenceReceiver().onReceive(context, intent)

        assertTrue(ReminderRuntimeBridge.drainNativeActions(context).isEmpty())
        assertNull(shadowOf(context as android.app.Application).nextStartedActivity)
    }

    @Test
    fun checkedCommitFailureRollsBackManagedIdAllocation() {
        ReminderRuntimeBridge.forceCommitFailureForTesting = true
        var failed = false

        try {
            ReminderRuntimeBridge.managedNotificationId(context, "r1")
        } catch (_: IllegalStateException) {
            failed = true
        }

        assertTrue(failed)
        assertEquals(1001, ReminderRuntimeBridge.managedNotificationId(context, "r1"))
    }

    @Test
    fun dwellCancelsWhenExitArrivesBeforeEnterDwellCompletes() {
        assertTrue(
            ReminderRuntimeBridge.recordDwellTransition(
                context = context,
                reminderId = "r1",
                expectedTransition = "enter",
                actualTransition = "enter",
                dwellSeconds = 60,
                nowMs = 1_000L,
            ),
        )
        assertFalse(
            ReminderRuntimeBridge.recordDwellTransition(
                context = context,
                reminderId = "r1",
                expectedTransition = "enter",
                actualTransition = "exit",
                dwellSeconds = 60,
                nowMs = 2_000L,
            ),
        )

        assertFalse(ReminderRuntimeBridge.isDwellReady(context, "r1", "enter", 62_000L))
    }

    @Test
    fun dwellCancelsWhenEnterArrivesBeforeExitDwellCompletes() {
        assertTrue(
            ReminderRuntimeBridge.recordDwellTransition(
                context = context,
                reminderId = "r1",
                expectedTransition = "exit",
                actualTransition = "exit",
                dwellSeconds = 60,
                nowMs = 1_000L,
            ),
        )
        assertFalse(
            ReminderRuntimeBridge.recordDwellTransition(
                context = context,
                reminderId = "r1",
                expectedTransition = "exit",
                actualTransition = "enter",
                dwellSeconds = 60,
                nowMs = 2_000L,
            ),
        )

        assertFalse(ReminderRuntimeBridge.isDwellReady(context, "r1", "exit", 62_000L))
    }

    @Test
    @Config(sdk = [33])
    fun notificationPermissionDeniedDoesNotCrashReminderDelivery() {
        val intent = Intent(context, ReminderGeofenceReceiver::class.java)
            .setAction(ReminderGeofenceReceiver.ACTION_TIME_ELAPSED)
            .putExtra(ReminderGeofenceReceiver.EXTRA_REMINDER_ID, "r1")
            .putExtra(ReminderGeofenceReceiver.EXTRA_TITLE, "Take medicine")

        ReminderGeofenceReceiver().onReceive(context, intent)

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        assertEquals(0, shadowOf(manager).size())
    }
}
