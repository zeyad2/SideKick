package com.sidekick.sidekick

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

@RunWith(RobolectricTestRunner::class)
class ReminderSoundStoreTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences("sidekick_reminder_sounds", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
        File(context.filesDir, "reminder_sounds").deleteRecursively()
    }

    @Test
    fun `catalog is named but not downloaded by default`() {
        val state = ReminderSoundStore.state(context)
        val catalog = state["catalog"] as List<*>
        val first = catalog.first() as Map<*, *>

        assertEquals("system", state["selectedId"])
        assertEquals("Gentle Bell", first["name"])
        assertFalse(first["downloaded"] as Boolean)
    }

    @Test
    fun `local choice is durable and deletion falls back to system`() {
        val directory = File(context.filesDir, "reminder_sounds").apply { mkdirs() }
        File(directory, "local_audio").writeBytes(byteArrayOf(1, 2, 3))
        context.getSharedPreferences("sidekick_reminder_sounds", Context.MODE_PRIVATE)
            .edit()
            .putString("local_name", "Mine.wav")
            .commit()

        ReminderSoundStore.select(context, "local")
        assertEquals("local", ReminderSoundStore.state(context)["selectedId"])
        assertTrue(ReminderSoundStore.state(context)["localAvailable"] as Boolean)

        ReminderSoundStore.delete(context, "local")
        assertEquals("system", ReminderSoundStore.state(context)["selectedId"])
        assertFalse(ReminderSoundStore.state(context)["localAvailable"] as Boolean)
    }
}
