package com.nexus.browser.media

import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.util.Locale
import java.util.regex.Pattern

/** Discovers publicly exposed video/player URLs. No DRM/login/CAPTCHA/access-control bypass. */
data class HarvestedVideo(
    val title: String,
    val url: String,
    val host: String,
    val type: String,
    val status: String,
    val selected: Boolean = true
)

object VideoHarvesterEngine {
    private const val MAX_HTML_BYTES = 5 * 1024 * 1024
    private const val MAX_LINKED_PAGES = 60
    private const val MAX_RESULTS = 1000

    private val attrPattern = Pattern.compile("(?:href|src|data-src|data-url|data-video|data-file|content)\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]", Pattern.CASE_INSENSITIVE)
    private val urlPattern = Pattern.compile("https?://[^\\s\\\"'<>\\\\]+", Pattern.CASE_INSENSITIVE)
    private val escapedUrlPattern = Pattern.compile("https?:\\\\?/\\\\?/[^\\s\\\"'<>]+", Pattern.CASE_INSENSITIVE)
    private val titlePattern = Pattern.compile("<title[^>]*>(.*?)</title>", Pattern.CASE_INSENSITIVE or Pattern.DOTALL)

    fun harvest(pageUrl: String, deepInspect: Boolean = true): List<HarvestedVideo> {
        val queue = ArrayDeque<Pair<String, String>>()
        val visited = HashSet<String>()
        val result = LinkedHashMap<String, HarvestedVideo>()
        queue.add(pageUrl to "Page")

        while (queue.isNotEmpty() && visited.size < MAX_LINKED_PAGES && result.size < MAX_RESULTS) {
            val (url, inheritedTitle) = queue.removeFirst()
            val normalizedPage = normalize(url) ?: continue
            if (!visited.add(normalizedPage)) continue
            val html = fetchHtml(normalizedPage) ?: continue
            val pageTitle = extractTitle(html).ifBlank { inheritedTitle }
            extractCandidates(html, normalizedPage).forEach { candidate ->
                val normalized = normalize(candidate) ?: return@forEach
                val type = classify(normalized)
                if (type == "LINK") return@forEach
                val host = runCatching { URI(normalized).host.orEmpty() }.getOrDefault("")
                val status = if (type in setOf("MP4", "WEBM", "M3U8", "MEDIA")) "MEDIA SOURCE" else "PLAYER / VIDEO PAGE"
                result.putIfAbsent(normalized, HarvestedVideo(pageTitle, normalized, host, type, status))
                if (deepInspect && type == "PLAYER" && queue.size + visited.size < MAX_LINKED_PAGES) queue.add(normalized to pageTitle)
            }
        }
        return result.values.toList()
    }

    private fun fetchHtml(url: String): String? = runCatching {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = 12_000; c.readTimeout = 20_000; c.instanceFollowRedirects = true
        c.setRequestProperty("User-Agent", UA)
        c.setRequestProperty("Accept", "text/html,application/xhtml+xml,application/json,text/plain,*/*;q=0.8")
        try { c.inputStream.use { it.readNBytes(MAX_HTML_BYTES).toString(Charsets.UTF_8) } } finally { c.disconnect() }
    }.getOrNull()

    private fun extractCandidates(html: String, baseUrl: String): List<String> {
        val out = LinkedHashSet<String>()
        fun add(raw: String?) {
            if (raw.isNullOrBlank()) return
            val value = decode(raw.trim())
            if (value.startsWith("data:") || value.startsWith("javascript:") || value.startsWith("mailto:")) return
            runCatching { URI(baseUrl).resolve(value).toString() }.getOrNull()?.let(out::add)
        }
        val attrs = attrPattern.matcher(html)
        while (attrs.find()) add(attrs.group(1))
        val urls = urlPattern.matcher(html)
        while (urls.find()) add(urls.group())
        val escaped = escapedUrlPattern.matcher(html)
        while (escaped.find()) add(escaped.group().replace("\\/", "/"))
        return out.toList()
    }

    private fun normalize(url: String): String? = runCatching {
        val u = URI(url)
        if (u.scheme?.lowercase(Locale.US) !in setOf("http", "https") || u.host.isNullOrBlank()) null else u.toString()
    }.getOrNull()

    private fun classify(url: String): String {
        val p = runCatching { URI(url).path.orEmpty().lowercase(Locale.US) }.getOrDefault("")
        return when {
            p.endsWith(".mp4") || p.endsWith(".m4v") || p.endsWith(".mov") -> "MP4"
            p.endsWith(".webm") -> "WEBM"
            p.endsWith(".m3u8") -> "M3U8"
            p.endsWith(".ts") -> "MEDIA"
            isLikelyVideoPage(url) -> "PLAYER"
            else -> "LINK"
        }
    }

    private fun isLikelyVideoPage(url: String): Boolean {
        val s = url.lowercase(Locale.US)
        return listOf("/video", "/watch", "/embed", "/player", "/stream", "/trailer", "/episode", "/play", "videoplayer").any(s::contains)
    }

    private fun extractTitle(html: String): String = titlePattern.matcher(html).let {
        if (!it.find()) "" else decode(it.group(1)).replace(Regex("<[^>]+>"), "").replace(Regex("\\s+"), " ").trim().take(160)
    }

    private fun decode(value: String) = value.replace("&amp;", "&").replace("&quot;", "\"").replace("&#39;", "'").replace("\\/", "/")
    private const val UA = "Mozilla/5.0 (Android; NEXUS Browser/1.0)"
}
