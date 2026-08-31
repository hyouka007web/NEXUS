package com.nexus.browser.media

import java.io.File

data class VideoEntry(
    val title: String = "",
    val filePath: String = "",
    val sourceUrl: String = "",
    val sizeBytes: Long = 0L,
    val downloadedAt: Long = System.currentTimeMillis()
) {
    val file: File get() = File(filePath)
    val isFile: Boolean get() = file.exists() && file.isFile
    val name: String get() = title
    fun delete(): Boolean = file.delete()
}
