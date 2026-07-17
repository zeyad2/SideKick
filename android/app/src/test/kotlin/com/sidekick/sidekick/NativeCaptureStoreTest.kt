package com.sidekick.sidekick

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.concurrent.CountDownLatch

@RunWith(RobolectricTestRunner::class)
class NativeCaptureStoreTest {
    private lateinit var context: Context
    private lateinit var store: NativeCaptureStore

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences("sidekick_capture_journal", Context.MODE_PRIVATE)
            .edit().clear().commit()
        store = NativeCaptureStore(context)
        CaptureRuntimeGuard.resetForTest()
    }

    @After
    fun tearDown() {
        CaptureRuntimeGuard.resetForTest()
    }

    @Test
    fun acknowledgementCannotEraseConcurrentCompletion() {
        val first = event("first")
        val second = event("second")
        store.markActive(first)
        store.completeActive()
        store.markActive(second)

        val start = CountDownLatch(1)
        val ack = Thread { start.await(); NativeCaptureStore(context).acknowledge(first.eventId) }
        val complete = Thread { start.await(); NativeCaptureStore(context).completeActive() }
        ack.start()
        complete.start()
        start.countDown()
        ack.join()
        complete.join()

        assertEquals(listOf("second"), store.pending().map { it.eventId })
    }

    @Test
    fun quarantinePreservesFailureAndDoesNotWedgeNextCapture() {
        val failed = event("failed")
        store.markActive(failed)
        store.updateActiveState(STATE_FINALIZING)
        store.quarantineActive("audio_finalization_failed")

        assertNull(store.active())
        assertEquals("audio_finalization_failed", store.failed("owner").single().failureCode)
        store.markActive(event("next"))
        assertEquals("next", store.active()?.eventId)
    }

    @Test
    fun processLiveGuardBlocksRecoveryWindowUntilEnd() {
        CaptureRuntimeGuard.begin("live")
        assertTrue(CaptureRuntimeGuard.hasLiveCapture)
        CaptureRuntimeGuard.end("other")
        assertTrue(CaptureRuntimeGuard.hasLiveCapture)
        CaptureRuntimeGuard.end("live")
        assertFalse(CaptureRuntimeGuard.hasLiveCapture)
    }

    private fun event(id: String) = NativeCaptureEvent(
        eventId = id,
        audioPath = context.filesDir.resolve("$id.aac").absolutePath,
        capturedAtMs = id.length.toLong(),
        ownerId = "owner",
    )
}
