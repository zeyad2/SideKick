package com.sidekick.sidekick

import android.media.MediaExtractor
import java.io.File
import java.io.FileOutputStream

object CaptureAudioValidator {
    private const val MIN_AUDIO_BYTES = 256L

    /** A capture is publishable only after an explicit flush and media parse. */
    fun syncAndValidate(file: File): Boolean {
        if (!file.exists() || file.length() < MIN_AUDIO_BYTES) return false
        if (runCatching { FileOutputStream(file, true).use { it.fd.sync() } }.isFailure) return false
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(file.absolutePath)
            extractor.trackCount > 0
        } catch (_: Throwable) {
            false
        } finally {
            extractor.release()
        }
    }
}
