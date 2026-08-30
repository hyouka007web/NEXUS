package com.nexus.browser.adblock

import android.content.Context
import android.net.Uri
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.URI
import java.util.Locale

/** Fast request blocker supporting hosts files and a safe subset of ABP syntax. */
class AdBlockEngine private constructor(
    private val blockedHosts: Set<String>,
    private val blockedRules: List<Rule>,
    private val allowRules: List<Rule>
) {
    @Volatile var enabled: Boolean = true
    @Volatile var blockedCount: Int = 0
        private set

    /**
     * A single filter rule.
     * [token] is the URL-matching part with any `$options` already stripped off.
     * [domainIncludes]/[domainExcludes] come from a `domain=` option (comma separated,
     * `~` prefix = exclude). [thirdPartyOnly]/[firstPartyOnly] come from the
     * `third-party`/`~third-party` option. Unsupported options (e.g. `$script`, `$image`)
     * are ignored rather than being left inside the match text, which used to cause
     * false-positive blocks whenever an option string happened to appear in a URL.
     */
    data class Rule(
        val raw: String,
        val host: String?,
        val token: String,
        val domainIncludes: Set<String> = emptySet(),
        val domainExcludes: Set<String> = emptySet(),
        val thirdPartyOnly: Boolean = false,
        val firstPartyOnly: Boolean = false
    )

    fun shouldBlock(uri: Uri, sourceHost: String? = null): Boolean {
        if (!enabled) return false
        val host = uri.host?.lowercase(Locale.US) ?: return false
        val url = uri.toString().lowercase(Locale.US)
        val source = sourceHost?.lowercase(Locale.US)
        if (allowRules.any { it.matches(url, host, source) }) return false

        var current = host
        while (current.isNotEmpty()) {
            if (blockedHosts.contains(current)) return markBlocked()
            val dot = current.indexOf('.')
            if (dot < 0) break
            current = current.substring(dot + 1)
        }
        return if (blockedRules.any { it.matches(url, host, source) }) markBlocked() else false
    }

    private fun markBlocked(): Boolean { blockedCount++; return true }
    fun resetCounter() { blockedCount = 0 }

    companion object {
        fun loadFromAssets(context: Context): AdBlockEngine {
            val hosts = HashSet<String>()
            val rules = mutableListOf<Rule>()
            val exceptions = mutableListOf<Rule>()
            context.assets.open("blocklist_hosts.txt").use { input ->
                BufferedReader(InputStreamReader(input)).forEachLine { parse(it, hosts, rules, exceptions) }
            }
            return AdBlockEngine(hosts, rules, exceptions)
        }

        private fun parse(raw: String, hosts: MutableSet<String>, rules: MutableList<Rule>, exceptions: MutableList<Rule>) {
            var line = raw.trim()
            if (line.isEmpty() || line.startsWith("!") || line.startsWith("#")) return
            // Element-hiding / cosmetic rules (##, #@#, #?#) are not applicable to a
            // network-level request blocker — skip them instead of falling through to
            // generic substring matching, which previously matched CSS selector text
            // against request URLs and caused unrelated false positives.
            if (line.contains("##") || line.contains("#@#") || line.contains("#?#")) return

            val exception = line.startsWith("@@")
            if (exception) line = line.removePrefix("@@")

            if (line.matches(Regex("^(0\\.0\\.0\\.0|127\\.0\\.0\\.1)\\s+\\S+.*$"))) {
                line.split(Regex("\\s+"))[1].lowercase(Locale.US).trimEnd('.').let(hosts::add)
                return
            }

            // Split off "$option1,option2,~option3" — everything after the first
            // unescaped '$' that isn't part of a regex-style rule.
            var body = line
            var domainIncludes = emptySet<String>()
            var domainExcludes = emptySet<String>()
            var thirdPartyOnly = false
            var firstPartyOnly = false
            val dollar = line.lastIndexOf('$')
            if (dollar >= 0 && dollar < line.length - 1) {
                val optionsPart = line.substring(dollar + 1)
                // Only treat it as an options block if it looks like one (comma-separated
                // known tokens) — otherwise leave the raw line alone.
                val looksLikeOptions = optionsPart.split(",").all { opt ->
                    val o = opt.removePrefix("~")
                    o.startsWith("domain=") || o in KNOWN_OPTIONS
                }
                if (looksLikeOptions) {
                    body = line.substring(0, dollar)
                    val includes = mutableSetOf<String>()
                    val excludes = mutableSetOf<String>()
                    optionsPart.split(",").forEach { opt ->
                        when {
                            opt.startsWith("domain=") -> {
                                opt.removePrefix("domain=").split("|").forEach { d ->
                                    if (d.startsWith("~")) excludes.add(d.removePrefix("~").lowercase(Locale.US))
                                    else includes.add(d.lowercase(Locale.US))
                                }
                            }
                            opt == "third-party" -> thirdPartyOnly = true
                            opt == "~third-party" -> firstPartyOnly = true
                            // other options (script, image, subdocument, ...) are request-type
                            // filters we have no signal for here — ignored, not matched as text.
                        }
                    }
                    domainIncludes = includes
                    domainExcludes = excludes
                }
            }

            if (body.startsWith("||")) {
                val hostBody = body.removePrefix("||")
                val hostPart = hostBody.substringBeforeAny("/", "^")
                val host = hostPart.lowercase(Locale.US)
                val isPlainHost = host.matches(Regex("[a-z0-9._-]+")) && (hostBody == host || hostBody == "$host^")
                if (isPlainHost && domainIncludes.isEmpty() && domainExcludes.isEmpty() && !thirdPartyOnly && !firstPartyOnly) {
                    if (exception) exceptions.add(Rule(body, host, host)) else hosts.add(host)
                } else {
                    val ruleHost = host.takeIf { it.matches(Regex("[a-z0-9._-]+")) }
                    (if (exception) exceptions else rules).add(
                        Rule(body, ruleHost, hostBody, domainIncludes, domainExcludes, thirdPartyOnly, firstPartyOnly)
                    )
                }
                return
            }

            if (body.startsWith("http://") || body.startsWith("https://") || !body.contains("$")) {
                (if (exception) exceptions else rules).add(
                    Rule(
                        body, runCatching { URI(body).host }.getOrNull(), body.lowercase(Locale.US),
                        domainIncludes, domainExcludes, thirdPartyOnly, firstPartyOnly
                    )
                )
            }
        }

        private val KNOWN_OPTIONS = setOf(
            "third-party", "~third-party", "script", "~script", "image", "~image",
            "stylesheet", "~stylesheet", "subdocument", "~subdocument", "xmlhttprequest",
            "~xmlhttprequest", "media", "~media", "font", "~font", "popup", "~popup",
            "document", "~document", "important", "match-case"
        )

        private fun String.substringBeforeAny(vararg delimiters: String): String {
            val i = delimiters.mapNotNull { indexOf(it).takeIf { x -> x >= 0 } }.minOrNull() ?: length
            return substring(0, i)
        }

        private fun Rule.matches(url: String, host: String, source: String?): Boolean {
            if (this.host != null && host != this.host && !host.endsWith(".${this.host}") && source != this.host && source?.endsWith(".${this.host}") != true) return false

            if (domainIncludes.isNotEmpty() && source != null) {
                val onIncludedDomain = domainIncludes.any { d -> source == d || source.endsWith(".$d") }
                if (!onIncludedDomain) return false
            }
            if (domainExcludes.isNotEmpty() && source != null) {
                val onExcludedDomain = domainExcludes.any { d -> source == d || source.endsWith(".$d") }
                if (onExcludedDomain) return false
            }
            if (thirdPartyOnly && source != null && (source == host || host.endsWith(".$source") || source.endsWith(".$host"))) return false
            if (firstPartyOnly && source != null && source != host && !host.endsWith(".$source") && !source.endsWith(".$host")) return false

            return if (raw.startsWith("||")) {
                url.contains("//${token.removeSuffix("^").substringBefore('/')}") && (token == host || token.endsWith("^") || url.contains(token.removeSuffix("^")))
            } else url.contains(token)
        }
    }
}
