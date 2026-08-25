package com.tufblade.browser.media

import java.net.HttpURLConnection
import java.net.URL
import java.util.regex.Pattern

object MediaLinkFinder {
    private val videoPattern = Pattern.compile(
        """https?://[^"'\s>]+\.(mp4|webm|m3u8)(\?[^"'\s>]*)?""",
        Pattern.CASE_INSENSITIVE
    )

    fun findVideoUrls(pageUrl: String): List<String> {
        require(pageUrl.startsWith("http://") || pageUrl.startsWith("https://"))
        val connection = URL(pageUrl).openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 15_000
        connection.instanceFollowRedirects = true
        connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Android; NEXUS Browser)")
        return try {
            val html = connection.inputStream.bufferedReader().use { it.readText() }
            val matcher = videoPattern.matcher(html)
            buildList {
                while (matcher.find()) add(matcher.group().replace("&amp;", "&"))
            }.distinct()
        } finally {
            connection.disconnect()
        }
    }
}
