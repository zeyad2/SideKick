package com.sidekick.sidekick

/** Process-live guard paired with the durable journal lifecycle. */
object CaptureRuntimeGuard {
    private val lock = Any()
    private var liveEventId: String? = null

    val hasLiveCapture: Boolean get() = synchronized(lock) { liveEventId != null }

    fun begin(eventId: String) = synchronized(lock) {
        check(liveEventId == null) { "A capture is already live" }
        liveEventId = eventId
    }

    fun end(eventId: String) = synchronized(lock) {
        if (liveEventId == eventId) liveEventId = null
    }

    internal fun resetForTest() = synchronized(lock) {
        liveEventId = null
    }
}
