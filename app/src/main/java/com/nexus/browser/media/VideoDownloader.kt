package com.nexus.browser.media

import android.content.Context
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/**
 * NEXUS media downloader. Supports progressive HTTP(S) media with resume and public,
 * unencrypted HLS playlists. It deliberately does not bypass DRM, login, CAPTCHA or paywalls.
 */
data class VideoEntry(
    val id: String,
    val title: String,
    val filePath: String,
    val sourceUrl: String,
    val downloadedAt: String,
    val sizeBytes: Long
)

data class DownloadProgress(val bytes: Long, val total: Long, val percent: Int)

object VideoDownloader {
    private const val INDEX_FILE = "mediathek_index.json"
    private const val CONNECT_TIMEOUT = 15_000
    private const val READ_TIMEOUT = 45_000
    private const val BUFFER = 128 * 1024

    fun downloadsDir(context: Context): File = File(context.filesDir, "downloads").apply { mkdirs() }
    private fun indexFile(context: Context) = File(downloadsDir(context), INDEX_FILE)

    fun loadIndex(context: Context): List<VideoEntry> {
        val file = indexFile(context)
        if (!file.exists()) return emptyList()
        return runCatching {
            val arr = JSONArray(file.readText())
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                VideoEntry(o.getString("id"), o.getString("title"), o.getString("filePath"), o.getString("sourceUrl"), o.getString("downloadedAt"), o.optLong("sizeBytes"))
            }.filter { File(it.filePath).exists() }
        }.getOrDefault(emptyList())
    }

    private fun saveIndex(context: Context, entries: List<VideoEntry>) {
        val arr = JSONArray()
        entries.forEach { e -> arr.put(JSONObject().apply {
            put("id", e.id); put("title", e.title); put("filePath", e.filePath); put("sourceUrl", e.sourceUrl)
            put("downloadedAt", e.downloadedAt); put("sizeBytes", e.sizeBytes)
        }) }
        val tmp = File(indexFile(context).absolutePath + ".tmp")
        tmp.writeText(arr.toString())
        if (!tmp.renameTo(indexFile(context))) indexFile(context).writeText(arr.toString())
    }

    fun download(context: Context, mediaUrl: String, pageTitle: String, referer: String? = null, onProgress: ((DownloadProgress) -> Unit)? = null): VideoEntry {
        require(mediaUrl.startsWith("http://") || mediaUrl.startsWith("https://"))
        return if (looksLikeHls(mediaUrl)) downloadHls(context, mediaUrl, pageTitle, referer, onProgress) else downloadDirect(context, mediaUrl, pageTitle, referer, onProgress)
    }

    private fun downloadDirect(context: Context, mediaUrl: String, pageTitle: String, referer: String?, onProgress: ((DownloadProgress) -> Unit)?): VideoEntry {
        val id = UUID.randomUUID().toString().replace("-", "").take(12)
        val ext = guessExtension(mediaUrl, null)
        val target = File(downloadsDir(context), "${sanitize(pageTitle).take(60).ifBlank { "video" }}-$id.$ext")
        val part = File(target.absolutePath + ".part")
        var existing = if (part.exists()) part.length() else 0L
        var total = -1L
        var responseCode: Int
        var connection: HttpURLConnection? = null
        try {
            connection = (URL(mediaUrl).openConnection() as HttpURLConnection).apply {
                connectTimeout = CONNECT_TIMEOUT; readTimeout = READ_TIMEOUT; instanceFollowRedirects = true
                setRequestProperty("User-Agent", UA); setRequestProperty("Accept", "*/*")
                if (!referer.isNullOrBlank()) setRequestProperty("Referer", referer)
                if (existing > 0) setRequestProperty("Range", "bytes=$existing-")
            }
            responseCode = connection.responseCode
            // java.net.HttpURLConnection hat keine Konstante für 416 (Range Not
            // Satisfiable) — anders als z.B. HTTP_OK oder HTTP_PARTIAL ist das
            // kein Standardfeld der Klasse, deshalb hier der Literalwert.
            if (responseCode == 416) {
                existing = 0
                part.delete()
                connection.disconnect()
                connection = null
                return downloadDirect(context, mediaUrl, pageTitle, referer, onProgress)
            }
            if (responseCode !in 200..299) error("HTTP $responseCode")
            val supportsResume = responseCode == HttpURLConnection.HTTP_PARTIAL
            if (!supportsResume && existing > 0) { existing = 0; part.delete() }
            val contentLength = connection.contentLengthLong
            total = if (contentLength >= 0) contentLength + existing else -1
            val append = supportsResume && existing > 0
            BufferedInputStream(connection.inputStream, BUFFER).use { input ->
                FileOutputStream(part, append).use { output ->
                    var done = existing
                    val buffer = ByteArray(BUFFER)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        output.write(buffer, 0, n)
                        done += n
                        val percent = if (total > 0) ((done * 100) / total).toInt().coerceIn(0, 100) else -1
                        onProgress?.invoke(DownloadProgress(done, total, percent))
                    }
                    output.fd.sync()
                }
            }
            if (!part.renameTo(target)) error("Datei konnte nicht finalisiert werden")
            val entry = makeEntry(id, pageTitle, target, mediaUrl)
            saveIndex(context, loadIndex(context) + entry)
            return entry
        } catch (e: Exception) {
            throw e
        } finally { connection?.disconnect() }
    }

    private fun downloadHls(context: Context, mediaUrl: String, pageTitle: String, referer: String?, onProgress: ((DownloadProgress) -> Unit)?): VideoEntry {
        val master = fetchText(mediaUrl, referer)
        val playlist = chooseVariant(master, mediaUrl, referer)
        if (playlist.contains("#EXT-X-KEY", true) && !playlist.contains("METHOD=NONE", true)) {
            error("Verschlüsselte HLS-Streams werden nicht entschlüsselt")
        }
        val segments = parseSegments(playlist, mediaUrl).take(5000)
        if (segments.isEmpty()) error("HLS-Playlist enthält keine Segmente")

        val id = UUID.randomUUID().toString().replace("-", "").take(12)
        val ext = if (playlist.contains("#EXT-X-MAP")) "mp4" else "ts"
        val target = File(downloadsDir(context), "${sanitize(pageTitle).take(60).ifBlank { "video" }}-$id.$ext")
        val part = File(target.absolutePath + ".part")
        FileOutputStream(part, false).use { output ->
            var done = 0L
            segments.forEachIndexed { index, segment ->
                val c = open(segment, referer)
                c.inputStream.use { input ->
                    val buffer = ByteArray(BUFFER)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        output.write(buffer, 0, n)
                        done += n
                    }
                }
                c.disconnect()
                onProgress?.invoke(DownloadProgress(done, -1, ((index + 1) * 100 / segments.size)))
            }
            output.fd.sync()
        }
        if (!part.renameTo(target)) error("Datei konnte nicht finalisiert werden")
        val entry = makeEntry(id, pageTitle, target, mediaUrl)
        saveIndex(context, loadIndex(context) + entry)
        return entry
    }

    private fun chooseVariant(master: String, base: String, referer: String?): String {
        val lines = master.lines().map { it.trim() }.filter { it.isNotEmpty() }
        if (!lines.any { it.startsWith("#EXT-X-STREAM-INF", true) }) return master
        var bestUrl: String? = null
        var bestBandwidth = -1L
        for (i in lines.indices) {
            if (!lines[i].startsWith("#EXT-X-STREAM-INF", true)) continue
            val bandwidth = Regex("(?:AVERAGE-BANDWIDTH|BANDWIDTH)=(\\d+)", RegexOption.IGNORE_CASE).find(lines[i])?.groupValues?.get(1)?.toLongOrNull() ?: 0L
            val next = lines.drop(i + 1).firstOrNull { !it.startsWith("#") } ?: continue
            if (bandwidth > bestBandwidth) { bestBandwidth = bandwidth; bestUrl = resolve(base, next) }
        }
        return bestUrl?.let { fetchText(it, referer) } ?: master
    }

    private fun parseSegments(playlist: String, base: String): List<String> = buildList {
        var map: String? = null
        playlist.lines().forEach { raw ->
            val line = raw.trim()
            if (line.startsWith("#EXT-X-MAP", true)) {
                val uri = Regex("URI=\"([^\"]+)\"").find(line)?.groupValues?.get(1)
                if (uri != null) map = resolve(base, uri)
            } else if (line.isNotEmpty() && !line.startsWith("#")) add(resolve(base, line))
        }
        if (map != null) add(0, map!!)
    }

    private fun fetchText(url: String, referer: String?): String {
        val c = open(url, referer)
        return try { c.inputStream.use { it.readNBytes(8 * 1024 * 1024).toString(Charsets.UTF_8) } } finally { c.disconnect() }
    }


    private fun open(url: String, referer: String?): HttpURLConnection = (URL(url).openConnection() as HttpURLConnection).apply {
        connectTimeout = CONNECT_TIMEOUT; readTimeout = READ_TIMEOUT; instanceFollowRedirects = true
        setRequestProperty("User-Agent", UA); setRequestProperty("Accept", "*/*")
        if (!referer.isNullOrBlank()) setRequestProperty("Referer", referer)
        if (responseCode !in 200..299) error("HTTP $responseCode")
    }

    private fun looksLikeHls(url: String) = URI(url).path.orEmpty().lowercase(Locale.US).endsWith(".m3u8")

    private fun guessExtension(url: String, contentType: String?): String {
        val path = runCatching { URI(url).path.orEmpty() }.getOrDefault("").lowercase(Locale.US)
        val fromPath = Regex("\\.([a-z0-9]{2,5})$").find(path)?.groupValues?.get(1)
        if (fromPath != null) return fromPath
        return when {
            contentType?.contains("webm") == true -> "webm"
            contentType?.contains("mpeg") == true -> "mpg"
            contentType?.contains("mp4") == true -> "mp4"
            else -> "bin"
        }
    }

    private fun makeEntry(id: String, title: String, target: File, source: String) = VideoEntry(
        id, title.ifBlank { "Video $id" }, target.absolutePath, source,
        SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.GERMANY).format(Date()), target.length()
    )

    private fun sanitize(value: String) = value.replace(Regex("[\\/:*?\"<>|\\r\\n]+"), "_").trim().ifBlank { "video" }
    private fun resolve(base: String, child: String): String = URI(base).resolve(child).toString()
    fun delete(context: Context, entry: VideoEntry) { File(entry.filePath).delete(); saveIndex(context, loadIndex(context).filterNot { it.id == entry.id }) }

    private const val UA = "Mozilla/5.0 (Android; NEXUS Browser/1.0)"
}
