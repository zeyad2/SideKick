package com.sidekick.sidekick

import android.content.Context
import org.json.JSONObject
import java.io.File

data class NativeCaptureEvent(
    val eventId: String,
    val audioPath: String,
    val capturedAtMs: Long,
    val ownerId: String,
    val state: String = STATE_PREPARING,
    val failureCode: String? = null,
) {
    fun toJson() = JSONObject()
        .put("eventId", eventId)
        .put("audioPath", audioPath)
        .put("capturedAtMs", capturedAtMs)
        .put("ownerId", ownerId)
        .put("state", state)
        .apply { failureCode?.let { put("failureCode", it) } }

    fun toMap() = mapOf(
        "eventId" to eventId,
        "audioPath" to audioPath,
        "capturedAtMs" to capturedAtMs,
        "ownerId" to ownerId,
        "state" to state,
        "failureCode" to failureCode,
    )

    companion object {
        fun fromJson(json: JSONObject) = NativeCaptureEvent(
            eventId = json.getString("eventId"),
            audioPath = json.getString("audioPath"),
            capturedAtMs = json.getLong("capturedAtMs"),
            ownerId = json.getString("ownerId"),
            state = json.optString("state", STATE_PREPARING),
            failureCode = json.optString("failureCode").ifBlank { null },
        )
    }
}

const val STATE_PREPARING = "preparing"
const val STATE_RECORDING = "recording"
const val STATE_FINALIZING = "finalizing"
const val STATE_PENDING = "pending"
const val STATE_FAILED = "failed"

/** Synchronous, process-independent journal between the recorder and Flutter. */
class NativeCaptureStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun setConfiguredOwner(ownerId: String?) = synchronized(LOCK) {
        val edit = prefs.edit()
        if (ownerId == null) edit.remove(OWNER) else edit.putString(OWNER, ownerId)
        check(edit.commit())
    }

    fun configuredOwner(): String? = synchronized(LOCK) {
        prefs.getString(OWNER, null)
    }

    fun markActive(event: NativeCaptureEvent) = synchronized(LOCK) {
        check(prefs.edit().putString(ACTIVE, event.toJson().toString()).commit())
    }

    fun updateActiveState(state: String) = synchronized(LOCK) {
        val event = active() ?: return@synchronized
        check(
            prefs.edit()
                .putString(ACTIVE, event.copy(state = state).toJson().toString())
                .commit(),
        )
    }

    fun active(): NativeCaptureEvent? = synchronized(LOCK) {
        prefs.getString(ACTIVE, null)?.let {
            runCatching { NativeCaptureEvent.fromJson(JSONObject(it)) }.getOrNull()
        }
    }

    /** One key per event: ack(A) can never overwrite a concurrent complete(B). */
    fun completeActive(): NativeCaptureEvent? = synchronized(LOCK) {
        val event = active() ?: return@synchronized null
        val pending = event.copy(state = STATE_PENDING, failureCode = null)
        check(
            prefs.edit()
                .putString("$PENDING_PREFIX${event.eventId}", pending.toJson().toString())
                .remove(ACTIVE)
                .commit(),
        )
        pending
    }

    fun recoverInterrupted(): NativeCaptureEvent? = synchronized(LOCK) {
        val event = active() ?: return@synchronized null
        return@synchronized if (CaptureAudioValidator.syncAndValidate(File(event.audioPath))) {
            completeActive()
        } else {
            quarantineActive("interrupted_invalid_audio")
            null
        }
    }

    fun quarantineActive(code: String): NativeCaptureEvent? = synchronized(LOCK) {
        val event = active() ?: return@synchronized null
        val failed = event.copy(state = STATE_FAILED, failureCode = code)
        check(
            prefs.edit()
                .putString("$FAILED_PREFIX${event.eventId}", failed.toJson().toString())
                .remove(ACTIVE)
                .commit(),
        )
        failed
    }

    fun discardActive(): NativeCaptureEvent? = synchronized(LOCK) {
        val event = active() ?: return@synchronized null
        check(prefs.edit().remove(ACTIVE).commit())
        runCatching { File(event.audioPath).delete() }
        event
    }

    fun pending(ownerId: String? = null): List<NativeCaptureEvent> = synchronized(LOCK) {
        prefs.all.entries
            .asSequence()
            .filter { it.key.startsWith(PENDING_PREFIX) }
            .mapNotNull { (_, value) ->
                (value as? String)?.let {
                    runCatching { NativeCaptureEvent.fromJson(JSONObject(it)) }.getOrNull()
                }
            }
            .filter { ownerId == null || it.ownerId == ownerId }
            .sortedBy { it.capturedAtMs }
            .toList()
    }

    fun acknowledge(eventId: String) = synchronized(LOCK) {
        check(prefs.edit().remove("$PENDING_PREFIX$eventId").commit())
    }

    fun retryFailed(ownerId: String): List<NativeCaptureEvent> = synchronized(LOCK) {
        val promoted = mutableListOf<NativeCaptureEvent>()
        failed(ownerId).forEach { event ->
            if (CaptureAudioValidator.syncAndValidate(File(event.audioPath))) {
                val pending = event.copy(state = STATE_PENDING, failureCode = null)
                check(
                    prefs.edit()
                        .putString("$PENDING_PREFIX${event.eventId}", pending.toJson().toString())
                        .remove("$FAILED_PREFIX${event.eventId}")
                        .commit(),
                )
                promoted.add(pending)
            }
        }
        promoted
    }

    fun failed(ownerId: String): List<NativeCaptureEvent> = synchronized(LOCK) {
        prefs.all.entries
            .asSequence()
            .filter { it.key.startsWith(FAILED_PREFIX) }
            .mapNotNull { (_, value) ->
                (value as? String)?.let {
                    runCatching { NativeCaptureEvent.fromJson(JSONObject(it)) }.getOrNull()
                }
            }
            .filter { it.ownerId == ownerId }
            .sortedBy { it.capturedAtMs }
            .toList()
    }

    companion object {
        private val LOCK = Any()
        private const val PREFS = "sidekick_capture_journal"
        private const val ACTIVE = "active_capture"
        private const val OWNER = "configured_owner"
        private const val PENDING_PREFIX = "pending_capture_"
        private const val FAILED_PREFIX = "failed_capture_"
    }
}
