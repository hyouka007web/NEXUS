package com.nexus.browser

import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.Locale
import java.util.regex.Pattern

/**
 * Public-resource scraper. It inspects the delivered HTML only; it does not bypass
 * authentication, CAPTCHA, DRM or access controls. Designed to be deterministic and bounded.
 */
data class ScrapeResult(
    val title: String,
    val links: List<String>,
    val media: List<String>,
    val htmlSize: Int
)

object ScraperEngine {
    private const val MAX_HTML_BYTES = 5 * 1024 * 1024
    private const val MAX_LINKS = 2500
    private const val MAX_MEDIA = 1000

    private val attrPattern = Pattern.compile(
        "(?:href|src|data-src|data-url|data-video|data-file|content)\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]",
        Pattern.CASE_INSENSITIVE
    )
    private val srcSetPattern = Pattern.compile("(?:srcset|data-srcset)\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]", Pattern.CASE_INSENSITIVE)
    private val titlePattern = Pattern.compile("<title[^>]*>(.*?)</title>", Pattern.CASE_INSENSITIVE or Pattern.DOTALL)
    private val ogPattern = Pattern.compile("<meta[^>]+(?:property|name)\\s*=\\s*['\\\"](?:og:video(?::secure_url)?|og:image|twitter:image|twitter:player:stream)['\\\"][^>]+content\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]", Pattern.CASE_INSENSITIVE)
    private val urlPattern = Pattern.compile("https?://[^\\s\\\"'<>\\\\]+", Pattern.CASE_INSENSITIVE)
    private val escapedUrlPattern = Pattern.compile("https?:\\\\?/\\\\?/[^\\s\\\"'<>]+", Pattern.CASE_INSENSITIVE)
    private val cssUrlPattern = Pattern.compile("url\\(\\s*['\\\"]?([^'\\\")]+)['\\\"]?\\s*\\)", Pattern.CASE_INSENSITIVE)

    fun scrape(pageUrl: String): ScrapeResult {
        require(pageUrl.startsWith("http://") || pageUrl.startsWith("https://"))
        val response = fetch(pageUrl)
        val html = response.body
        val base = URI(response.finalUrl)
        val links = LinkedHashSet<String>()
        val media = LinkedHashSet<String>()

        fun add(raw: String?) {
            if (raw.isNullOrBlank() || links.size >= MAX_LINKS) return
            val value = decodeHtml(raw.trim())
            if (value.startsWith("data:") || value.startsWith("javascript:") || value.startsWith("mailto:")) return
            val resolved = runCatching { base.resolve(value).toString() }.getOrNull() ?: return
            if (!resolved.startsWith("http://") && !resolved.startsWith("https://")) return
            links.add(resolved)
            if (isMedia(resolved) && media.size < MAX_MEDIA) media.add(resolved)
        }

        val attrs = attrPattern.matcher(html)
        while (attrs.find()) add(attrs.group(1))

        val srcsets = srcSetPattern.matcher(html)
        while (srcsets.find()) srcsets.group(1).split(',').forEach { add(it.trim().substringBefore(' ')) }

        val og = ogPattern.matcher(html)
        while (og.find()) add(og.group(1))

        val css = cssUrlPattern.matcher(html)
        while (css.find()) add(css.group(1))

        val rawUrls = urlPattern.matcher(html)
        while (rawUrls.find()) add(rawUrls.group())

        val escaped = escapedUrlPattern.matcher(html)
        while (escaped.find()) add(escaped.group().replace("\\/", "/"))

        // Media-looking JSON/config strings are common in JS players.
        val decoded = runCatching { URLDecoder.decode(html, StandardCharsets.UTF_8.name()) }.getOrDefault(html)
        val decodedUrls = urlPattern.matcher(decoded)
        while (decodedUrls.find()) add(decodedUrls.group())

        val finalLinks = links.take(MAX_LINKS)
        val finalMedia = media.filter { isMedia(it) }.distinct().take(MAX_MEDIA)
        val title = titlePattern.matcher(html).let {
            if (it.find()) decodeHtml(it.group(1)).replace(Regex("\\s+"), " ").trim().take(200)
            else base.host ?: "NEXUS"
        }
        return ScrapeResult(title, finalLinks, finalMedia, html.toByteArray(StandardCharsets.UTF_8).size)
    }

    private data class Response(val body: String, val finalUrl: String)

    private fun fetch(pageUrl: String): Response {
        val c = URL(pageUrl).openConnection() as HttpURLConnection
        c.connectTimeout = 12_000
        c.readTimeout = 20_000
        c.instanceFollowRedirects = true
        c.setRequestProperty("User-Agent", "Mozilla/5.0 (Android; NEXUS Browser/1.0)")
        c.setRequestProperty("Accept", "text/html,application/xhtml+xml,application/json,text/plain,*/*;q=0.8")
        c.setRequestProperty("Accept-Encoding", "gzip")
        return try {
            val bytes = c.inputStream.use { it.readNBytes(MAX_HTML_BYTES) }
            Response(bytes.toString(StandardCharsets.UTF_8), c.url.toString())
        } finally { c.disconnect() }
    }

    private fun isMedia(url: String): Boolean {
        val p = runCatching { URI(url).path.orEmpty().lowercase(Locale.US) }.getOrDefault("")
        return p.endsWith(".mp4") || p.endsWith(".m4v") || p.endsWith(".webm") || p.endsWith(".mov") ||
            p.endsWith(".m3u8") || p.endsWith(".mp3") || p.endsWith(".m4a") || p.endsWith(".aac") ||
            p.endsWith(".flac") || p.endsWith(".wav") || p.endsWith(".jpg") || p.endsWith(".jpeg") ||
            p.endsWith(".png") || p.endsWith(".webp") || p.endsWith(".gif") || p.endsWith(".avif")
    }

    private fun decodeHtml(value: String): String = value
        .replace("&amp;", "&", true)
        .replace("&quot;", "\"", true)
        .replace("&#39;", "'", true)
        .replace("&lt;", "<", true)
        .replace("&gt;", ">", true)
}

