package com.tufblade.browser

import java.net.HttpURLConnection
import java.net.URL
import java.util.regex.Pattern

data class ScrapeResult(
    val title: String,
    val links: List<String>,
    val media: List<String>,
    val htmlSize: Int
)

object ScraperEngine {
    private val hrefPattern = Pattern.compile(
        """(?:href|src)\s*=\s*["']([^"']+)["']""",
        Pattern.CASE_INSENSITIVE
    )
    private val mediaPattern = Pattern.compile(
        """https?://[^"'\s>]+\.(?:jpg|jpeg|png|gif|webp|mp4|webm|m3u8)(?:\?[^"'\s>]*)?""",
        Pattern.CASE_INSENSITIVE
    )
    private val titlePattern = Pattern.compile(
        """<title[^>]*>(.*?)</title>""",
        Pattern.CASE_INSENSITIVE or Pattern.DOTALL
    )

    fun scrape(pageUrl: String): ScrapeResult {
        require(pageUrl.startsWith("http://") || pageUrl.startsWith("https://"))
        val connection = URL(pageUrl).openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 15_000
        connection.instanceFollowRedirects = true
        connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Android; NEXUS Browser)")
        return try {
            val html = connection.inputStream.bufferedReader().use { it.readText() }
            val base = URL(pageUrl)
            val links = linkedSetOf<String>()
            val matcher = hrefPattern.matcher(html)
            while (matcher.find()) {
                runCatching { links += URL(base, matcher.group(1).trim()).toString() }
            }
            val media = linkedSetOf<String>()
            val mediaMatcher = mediaPattern.matcher(html)
            while (mediaMatcher.find()) media += mediaMatcher.group()
            val title = titlePattern.matcher(html).let {
                if (it.find()) it.group(1).replace(Regex("\\s+"), " ").trim() else (base.host ?: "NEXUS")
            }
            ScrapeResult(title, links.toList(), media.toList(), html.length)
        } finally {
            connection.disconnect()
        }
    }
}
