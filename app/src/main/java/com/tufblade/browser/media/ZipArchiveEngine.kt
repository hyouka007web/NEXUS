package com.tufblade.browser.media

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

object ZipArchiveEngine {
    fun create(context: Context, entries: List<VideoEntry>, archiveName: String): File {
        val dir = File(context.filesDir, "archives").apply { mkdirs() }
        val safe = archiveName.replace(Regex("[^A-Za-z0-9._ -]"), "_").ifBlank { "NEXUS-Archive" }
        val target = File(dir, if (safe.endsWith(".zip", true)) safe else "$safe.zip")
        ZipOutputStream(target.outputStream().buffered()).use { zip ->
            val manifest = JSONArray()
            entries.forEachIndexed { index, entry ->
                val source = File(entry.filePath)
                if (!source.isFile) return@forEachIndexed
                val filename = "%02d - %s.%s".format(index + 1, safeName(entry.title), source.extension.ifBlank { "mp4" })
                zip.putNextEntry(ZipEntry(filename))
                source.inputStream().buffered().use { it.copyTo(zip, 64 * 1024) }
                zip.closeEntry()
                manifest.put(JSONObject().apply {
                    put("index", index + 1)
                    put("title", entry.title)
                    put("sourceUrl", entry.sourceUrl)
                    put("file", filename)
                    put("sizeBytes", entry.sizeBytes)
                })
            }
            zip.putNextEntry(ZipEntry("nexus_manifest.json"))
            zip.write(manifest.toString(2).toByteArray())
            zip.closeEntry()
        }
        return target
    }

    private fun safeName(value: String) = value.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim().take(90).ifBlank { "Video" }
}
