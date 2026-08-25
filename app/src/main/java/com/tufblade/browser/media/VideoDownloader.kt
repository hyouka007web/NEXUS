package com.tufblade.browser.media

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

data class VideoEntry(
    val id: String,
    val title: String,
    val filePath: String,
    val sourceUrl: String,
    val downloadedAt: String,
    val sizeBytes: Long
)

object VideoDownloader {
    private const val INDEX_FILE = "mediathek_index.json"

    fun downloadsDir(context: Context): File =
        File(context.filesDir, "downloads").apply { mkdirs() }

    private fun indexFile(context: Context) = File(downloadsDir(context), INDEX_FILE)

    fun loadIndex(context: Context): List<VideoEntry> {
        val file = indexFile(context)
        if (!file.exists()) return emptyList()
        return runCatching {
            val arr = JSONArray(file.readText())
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                VideoEntry(
                    o.getString("id"),
                    o.getString("title"),
                    o.getString("filePath"),
                    o.getString("sourceUrl"),
                    o.getString("downloadedAt"),
                    o.optLong("sizeBytes")
                )
            }
        }.getOrDefault(emptyList())
    }

    private fun saveIndex(context: Context, entries: List<VideoEntry>) {
        val arr = JSONArray()
        entries.forEach { e ->
            arr.put(JSONObject().apply {
                put("id", e.id)
                put("title", e.title)
                put("filePath", e.filePath)
                put("sourceUrl", e.sourceUrl)
                put("downloadedAt", e.downloadedAt)
                put("sizeBytes", e.sizeBytes)
            })
        }
        indexFile(context).writeText(arr.toString())
    }

    fun download(context: Context, videoUrl: String, pageTitle: String): VideoEntry {
        require(videoUrl.startsWith("http://") || videoUrl.startsWith("https://"))
        val id = UUID.randomUUID().toString().take(8)
        val extension = videoUrl.substringBefore("?").substringAfterLast(".")
            .takeIf { it.length in 2..4 } ?: "mp4"
        val target = File(downloadsDir(context), "$id.$extension")
        val connection = URL(videoUrl).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        connection.instanceFollowRedirects = true
        try {
            connection.inputStream.use { input ->
                target.outputStream().use { output -> input.copyTo(output, 64 * 1024) }
            }
        } catch (e: Exception) {
            target.delete()
            throw e
        } finally {
            connection.disconnect()
        }
        val entry = VideoEntry(
            id,
            pageTitle.ifBlank { "Video $id" },
            target.absolutePath,
            videoUrl,
            SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.GERMANY).format(Date()),
            target.length()
        )
        saveIndex(context, loadIndex(context) + entry)
        return entry
    }

    fun delete(context: Context, entry: VideoEntry) {
        File(entry.filePath).delete()
        saveIndex(context, loadIndex(context).filterNot { it.id == entry.id })
    }
}
