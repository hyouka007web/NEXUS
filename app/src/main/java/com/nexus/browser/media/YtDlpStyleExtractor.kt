package com.nexus.browser.media

import java.net.URI
import java.util.Locale

/**
 * yt-dlp-style extractor orchestration for Android: extractor candidates are scored and
 * normalized before the downloader is invoked. This is an original implementation, not a
 * bundled copy of yt-dlp. It only handles publicly exposed media and player URLs.
 */
data class MediaCandidate(
    val url: String,
    val type: String,
    val score: Int,
    val title: String
)

object YtDlpStyleExtractor {
    fun extract(pageUrl: String): List<MediaCandidate> {
        val harvested = VideoHarvesterEngine.harvest(pageUrl, deepInspect = true)
        return harvested.map { item ->
            MediaCandidate(item.url, item.type, score(item), item.title)
        }.distinctBy { it.url }.sortedByDescending { it.score }
    }

    private fun score(item: HarvestedVideo): Int {
        val url = item.url.lowercase(Locale.US)
        var score = when (item.type) {
            "MP4" -> 100
            "WEBM" -> 95
            "M3U8" -> 90
            "MEDIA" -> 85
            "PLAYER" -> 55
            else -> 0
        }
        if (url.contains("1080")) score += 30
        if (url.contains("720")) score += 20
        if (url.contains("480")) score += 10
        if (url.contains("master")) score += 8
        if (url.contains("playlist")) score += 5
        if (runCatching { URI(url).query.orEmpty() }.getOrDefault("").contains("token")) score -= 2
        return score
    }
}
