package com.sidekick.sidekick

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

object ReminderSoundStore {
    private const val PREFS = "sidekick_reminder_sounds"
    private const val KEY_SELECTED = "selected_id"
    private const val KEY_LOCAL_NAME = "local_name"
    private const val DIRECTORY = "reminder_sounds"
    private const val LOCAL_FILE = "local_audio"
    private const val MAX_CATALOG_BYTES = 2 * 1024 * 1024
    private const val MAX_LOCAL_BYTES = 20 * 1024 * 1024

    private data class CatalogSound(
        val id: String,
        val name: String,
        val fileName: String,
        val url: String,
    )

    // Both tones are synthesized, CC0/public-domain WAV files. Pinning the
    // immutable source commit prevents a future upstream change from silently
    // replacing bytes downloaded by Sidekick.
    private val catalog = listOf(
        CatalogSound(
            id = "gentle_bell",
            name = "Gentle Bell",
            fileName = "gentle_bell.wav",
            url = "https://raw.githubusercontent.com/ibrews/Understudy/1567b96ac99904d10a757be1a71092c3d4a0734a/android/app/src/main/res/raw/bell.wav",
        ),
        CatalogSound(
            id = "bright_chime",
            name = "Bright Chime",
            fileName = "bright_chime.wav",
            url = "https://raw.githubusercontent.com/ibrews/Understudy/1567b96ac99904d10a757be1a71092c3d4a0734a/android/app/src/main/res/raw/chime.wav",
        ),
    )

    @Volatile
    private var previewPlayer: MediaPlayer? = null

    fun state(context: Context): Map<String, Any?> {
        val selected = selectedId(context)
        val local = localFile(context)
        val localAvailable = local.isFile && local.length() > 0
        return mapOf(
            "selectedId" to selected,
            "localAvailable" to localAvailable,
            "localName" to context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_LOCAL_NAME, null),
            "catalog" to catalog.map { sound ->
                mapOf(
                    "id" to sound.id,
                    "name" to sound.name,
                    "downloaded" to catalogFile(context, sound).let { it.isFile && it.length() > 0 },
                    "selected" to (selected == sound.id),
                )
            },
        )
    }

    fun download(context: Context, id: String) {
        val sound = catalog.firstOrNull { it.id == id }
            ?: throw IllegalArgumentException("Unknown reminder sound.")
        val directory = soundDirectory(context)
        val destination = catalogFile(context, sound)
        val temporary = File(directory, "${sound.fileName}.part")
        temporary.delete()
        val connection = URL(sound.url).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        connection.instanceFollowRedirects = true
        connection.setRequestProperty("Accept", "audio/wav,application/octet-stream")
        try {
            val status = connection.responseCode
            if (status !in 200..299) {
                throw IllegalStateException("Sound download failed ($status).")
            }
            val declared = connection.contentLengthLong
            if (declared > MAX_CATALOG_BYTES) {
                throw IllegalStateException("Sound download is unexpectedly large.")
            }
            connection.inputStream.use { input ->
                FileOutputStream(temporary).use { output ->
                    copyBounded(input, output, MAX_CATALOG_BYTES)
                    output.fd.sync()
                }
            }
            requireWaveFile(temporary)
            requirePlayable(context, Uri.fromFile(temporary))
            if (destination.exists() && !destination.delete()) {
                throw IllegalStateException("Could not replace the downloaded sound.")
            }
            if (!temporary.renameTo(destination)) {
                throw IllegalStateException("Could not save the downloaded sound.")
            }
        } finally {
            connection.disconnect()
            temporary.delete()
        }
    }

    fun importLocal(context: Context, uri: Uri) {
        val name = displayName(context, uri) ?: "Local reminder sound"
        val destination = localFile(context)
        val temporary = File(soundDirectory(context), "$LOCAL_FILE.part")
        temporary.delete()
        val input = context.contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("The selected audio file could not be opened.")
        try {
            input.use { source ->
                FileOutputStream(temporary).use { output ->
                    copyBounded(source, output, MAX_LOCAL_BYTES)
                    output.fd.sync()
                }
            }
            requirePlayable(context, Uri.fromFile(temporary))
            if (destination.exists() && !destination.delete()) {
                throw IllegalStateException("Could not replace the local sound.")
            }
            if (!temporary.renameTo(destination)) {
                throw IllegalStateException("Could not save the local sound.")
            }
            commit(
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .putString(KEY_LOCAL_NAME, name)
                    .putString(KEY_SELECTED, "local"),
            )
        } finally {
            temporary.delete()
        }
    }

    fun select(context: Context, id: String) {
        when {
            id == "system" -> Unit
            id == "local" && localFile(context).isFile -> Unit
            catalog.any { it.id == id && catalogFile(context, it).isFile } -> Unit
            else -> throw IllegalStateException("Download or import this sound before selecting it.")
        }
        commit(
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_SELECTED, id),
        )
    }

    fun delete(context: Context, id: String) {
        val target = when (id) {
            "local" -> localFile(context)
            else -> catalog.firstOrNull { it.id == id }?.let { catalogFile(context, it) }
                ?: throw IllegalArgumentException("Unknown reminder sound.")
        }
        if (target.exists() && !target.delete()) {
            throw IllegalStateException("Could not remove the reminder sound.")
        }
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val editor = prefs.edit()
        if (id == "local") editor.remove(KEY_LOCAL_NAME)
        if (prefs.getString(KEY_SELECTED, "system") == id) {
            editor.putString(KEY_SELECTED, "system")
        }
        commit(editor)
    }

    fun preview(context: Context, id: String) {
        val uri = uriForId(context, id)
        stopPreview()
        val player = MediaPlayer()
        try {
            player.apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                setDataSource(context, uri)
                isLooping = false
                setOnCompletionListener { stopPreview() }
                prepare()
                start()
            }
            previewPlayer = player
        } catch (error: Exception) {
            player.release()
            throw error
        }
    }

    fun stopPreview() {
        previewPlayer?.runCatching {
            if (isPlaying) stop()
            release()
        }
        previewPlayer = null
    }

    fun selectedUri(context: Context): Uri = uriForId(context, selectedId(context))

    fun channelSuffix(context: Context): String = selectedId(context)
        .replace(Regex("[^a-zA-Z0-9_]"), "_")

    private fun selectedId(context: Context): String {
        val stored = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_SELECTED, "system") ?: "system"
        val available = when {
            stored == "system" -> true
            stored == "local" -> localFile(context).isFile
            else -> catalog.any { it.id == stored && catalogFile(context, it).isFile }
        }
        if (available) return stored
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_SELECTED, "system")
            .commit()
        return "system"
    }

    private fun uriForId(context: Context, id: String): Uri {
        if (id == "system") {
            return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        }
        val file = when (id) {
            "local" -> localFile(context)
            else -> catalog.firstOrNull { it.id == id }?.let { catalogFile(context, it) }
        }
        if (file == null || !file.isFile) {
            throw IllegalStateException("The selected reminder sound is unavailable.")
        }
        return FileProvider.getUriForFile(
            context,
            "${context.packageName}.reminder_sounds",
            file,
        )
    }

    private fun soundDirectory(context: Context): File =
        File(context.filesDir, DIRECTORY).apply { mkdirs() }

    private fun catalogFile(context: Context, sound: CatalogSound): File =
        File(soundDirectory(context), sound.fileName)

    private fun localFile(context: Context): File = File(soundDirectory(context), LOCAL_FILE)

    private fun displayName(context: Context, uri: Uri): String? {
        return context.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst()) null else cursor.getString(0)?.take(120)
        }
    }

    private fun copyBounded(
        input: java.io.InputStream,
        output: java.io.OutputStream,
        maxBytes: Int,
    ) {
        val buffer = ByteArray(16 * 1024)
        var total = 0
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            total += read
            if (total > maxBytes) throw IllegalStateException("The selected sound is too large.")
            output.write(buffer, 0, read)
        }
        if (total == 0) throw IllegalStateException("The selected sound is empty.")
    }

    private fun requireWaveFile(file: File) {
        val header = ByteArray(12)
        file.inputStream().use { input ->
            if (input.read(header) != header.size) {
                throw IllegalStateException("Downloaded sound is not a valid WAV file.")
            }
        }
        val riff = String(header, 0, 4, Charsets.US_ASCII)
        val wave = String(header, 8, 4, Charsets.US_ASCII)
        if (riff != "RIFF" || wave != "WAVE") {
            throw IllegalStateException("Downloaded sound is not a valid WAV file.")
        }
    }

    private fun requirePlayable(context: Context, uri: Uri) {
        val player = MediaPlayer()
        try {
            player.setDataSource(context, uri)
            player.prepare()
            if (player.duration <= 0) throw IllegalStateException("The selected file has no playable audio.")
        } catch (error: Exception) {
            throw IllegalStateException("Choose a playable audio file.", error)
        } finally {
            player.release()
        }
    }

    private fun commit(editor: android.content.SharedPreferences.Editor) {
        if (!editor.commit()) throw IllegalStateException("Could not save the reminder sound setting.")
    }
}
