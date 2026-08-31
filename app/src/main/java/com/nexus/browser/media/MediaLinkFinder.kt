package com.nexus.browser.media

object MediaLinkFinder {
    fun findVideoUrls(pageUrl: String): List<String> =
        YtDlpStyleExtractor.extract(pageUrl)
            .filter { it.type in setOf("MP4", "WEBM", "M3U8", "MEDIA") }
            .map { it.url }
            .distinct()
}
