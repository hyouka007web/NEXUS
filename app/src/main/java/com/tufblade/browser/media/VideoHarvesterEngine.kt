package com.tufblade.browser.media

import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.util.Locale
import java.util.regex.Pattern

/** Discovers publicly exposed video/player links. Does not bypass DRM, login, CAPTCHA or access controls. */
data class HarvestedVideo(
    val title: String,
    val url: String,
    val host: String,
    val type: String,
    val status: String,
    val selected: Boolean = true
)

object VideoHarvesterEngine {
    private const val MAX_HTML_BYTES = 2_500_000
    private const val MAX_LINKED_PAGES = 30

    fun harvest(pageUrl: String, deepInspect: Boolean = true): List<HarvestedVideo> {
        val root = fetchHtml(pageUrl) ?: return emptyList()
        val links = extractLinks(root, pageUrl)
        val result = LinkedHashMap<String, HarvestedVideo>()

        fun add(url: String, title: String) {
            val normalized = normalize(url) ?: return
            val type = classify(normalized)
            if (type == "LINK" && !isLikelyVideoPage(normalized)) return
            val host = runCatching { URI(normalized).host.orEmpty() }.getOrDefault("")
            val status = if (type == "MP4" || type == "WEBM" || type == "M3U8") "MEDIA SOURCE" else "PLAYER / VIDEO PAGE"
            result.putIfAbsent(normalized, HarvestedVideo(title.ifBlank { "Video" }, normalized, host, type, status))
        }

        links.forEach { add(it.url, it.title) }
        if (deepInspect) {
            links.asSequence().filter { isLikelyVideoPage(it.url) }.take(MAX_LINKED_PAGES).forEach { link ->
                fetchHtml(link.url)?.let { html -> extractLinks(html, link.url).forEach { nested -> add(nested.url, nested.title.ifBlank { link.title }) } }
            }
        }
        return result.values.filter { it.type != "LINK" }.mapIndexed { i, v ->
            if (v.title == "Video") v.copy(title = "Video ${i + 1}") else v
        }
    }

    private data class Link(val url: String, val title: String)

    private fun fetchHtml(url: String): String? = runCatching {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = 12_000
        c.readTimeout = 15_000
        c.instanceFollowRedirects = true
        c.setRequestProperty("User-Agent", "Mozilla/5.0 (Android) NEXUS/1.0")
        c.setRequestProperty("Accept", "text/html,application/xhtml+xml")
        c.inputStream.use { it.readNBytes(MAX_HTML_BYTES).toString(Charsets.UTF_8) }.also { c.disconnect() }
    }.getOrNull()

    private fun extractLinks(html: String, baseUrl: String): List<Link> {
        val out = LinkedHashMap<String, Link>()
        val tagPattern = Pattern.compile("<(a|iframe|video|source)[^>]+(?:href|src)\\s*=\\s*[\\\"']([^\\\"']+)[\\\"'][^>]*>(.*?)</a>|<(iframe|video|source)[^>]+(?:href|src)\\s*=\\s*[\\\"']([^\\\"']+)[\\\"'][^>]*>", Pattern.CASE_INSENSITIVE or Pattern.DOTALL)
        val m = tagPattern.matcher(html)
        while (m.find()) {
            val raw = m.group(2) ?: m.group(5) ?: continue
            val title = cleanTitle(m.group(3).orEmpty())
            resolve(baseUrl, raw)?.let { out.putIfAbsent(it, Link(it, title)) }
        }
        val literalPattern = Pattern.compile("[\\\"'](https?://[^\\\"'\\s<>]+)[\\\"']", Pattern.CASE_INSENSITIVE)
        val lm = literalPattern.matcher(html)
        while (lm.find()) {
            val url = lm.group(1) ?: continue
            if (isLikelyVideoPage(url) || isDirectMedia(url)) out.putIfAbsent(url, Link(url, "Video"))
        }
        return out.values.toList()
    }

    private fun resolve(base: String, raw: String): String? = runCatching { URI(base).resolve(raw.trim()).toString() }.getOrNull()
    private fun normalize(url: String): String? = runCatching {
        val u = URI(url)
        if (u.scheme !in listOf("http", "https") || u.host.isNullOrBlank()) null else u.toString()
    }.getOrNull()
    private fun isDirectMedia(url: String): Boolean {
        val p = url.substringBefore('?').lowercase(Locale.US)
        return p.endsWith(".mp4") || p.endsWith(".webm") || p.endsWith(".m3u8") || p.endsWith(".m4v") || p.endsWith(".mov")
    }
    private fun isLikelyVideoPage(url: String): Boolean {
        if (isDirectMedia(url)) return true
        val s = url.lowercase(Locale.US)
        return listOf("video", "watch", "embed", "player", "stream", "trailer", "episode", "play").any(s::contains)
    }
    private fun classify(url: String): String {
        val p = url.substringBefore('?').lowercase(Locale.US)
        return when {
            p.endsWith(".mp4") || p.endsWith(".m4v") || p.endsWith(".mov") -> "MP4"
            p.endsWith(".webm") -> "WEBM"
            p.endsWith(".m3u8") -> "M3U8"
            isLikelyVideoPage(url) -> "PLAYER"
            else -> "LINK"
        }
    }
    private fun cleanTitle(value: String) = value.replace(Regex("<[^>]+>"), "").replace(Regex("\\s+"), " ").trim().take(120)
}
