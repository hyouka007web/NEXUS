package com.nexus.browser.media

import android.content.Context
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

object VideoDownloader {
    private const val BUFFER = 8192

    fun download(
        context: Context,
        mediaUrl: String,
        pageTitle: String,
        referer: String?,
        onProgress: (percent: Int) -> Unit
    ) {
        downloadDirect(context, mediaUrl, pageTitle, referer, onProgress)
    }

    fun downloadDirect(
        context: Context,
        mediaUrl: String,
        pageTitle: String,
        referer: String?,
        onProgress: (Int) -> Unit
    ) {
        val url = URL(mediaUrl)
        var connection = url.openConnection() as HttpURLConnection
        connection.connectTimeout = 15000
        connection.readTimeout = 15000
        referer?.let { connection.setRequestProperty("Referer", it) }

        val fileName = "${pageTitle.take(30).replace(Regex("[^a-zA-Z0-9]"), "_")}.mp4"
        val part = File(context.cacheDir, "$fileName.part")
        var existing = if (part.exists()) part.length() else 0L

        if (existing > 0) {
            connection.setRequestProperty("Range", "bytes=$existing-")
        }

        connection.connect()
        var responseCode = connection.responseCode

        if (responseCode == 416) {
            existing = 0L
            part.delete()
            connection.disconnect()
            val newConn = url.openConnection() as HttpURLConnection
            newConn.connectTimeout = 15000
            newConn.readTimeout = 15000
            referer?.let { newConn.setRequestProperty("Referer", it) }
            newConn.connect()
            connection = newConn
            responseCode = connection.responseCode
        }

        if (responseCode !in 200..299) error("HTTP $responseCode")

        val supportsResume = responseCode == 206
        if (!supportsResume && existing > 0) {
            existing = 0L
            part.delete()
        }

        val contentLength = connection.contentLengthLong
        val total = if (contentLength >= 0) contentLength + existing else -1L
        val append = supportsResume && existing > 0

        val conn = connection
        BufferedInputStream(conn.inputStream, BUFFER).use { input ->
            FileOutputStream(part, append).use { output ->
                var done = existing
                val buffer = ByteArray(BUFFER)
                while (true) {
                    val n = input.read(buffer)
                    if (n <= 0) break
                    output.write(buffer, 0, n)
                    done += n
                    if (total > 0) {
                        onProgress(((done * 100) / total).toInt())
                    }
                }
            }
        }
        conn.disconnect()
    }

    fun loadIndex(context: Context): List<VideoEntry> {
        val dir = context.cacheDir
        return dir.listFiles { _, name -> name.endsWith(".mp4") }?.map { file ->
            VideoEntry(
                title = file.nameWithoutExtension,
                filePath = file.absolutePath,
                sizeBytes = file.length(),
                downloadedAt = file.lastModified()
            )
        } ?: emptyList()
    }
}
