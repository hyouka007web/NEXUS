package com.tufblade.browser.adblock

import android.content.Context
import android.net.Uri
import java.io.BufferedReader
import java.io.InputStreamReader

class AdBlockEngine private constructor(
    private val blockedHosts: HashSet<String>,
    private val blockedSubstrings: List<String>
) {
    var blockedCount: Int = 0
        private set
    var enabled: Boolean = true

    fun shouldBlock(uri: Uri): Boolean {
        if (!enabled) return false
        val host = uri.host?.lowercase() ?: return false
        var current = host
        while (current.isNotEmpty()) {
            if (blockedHosts.contains(current)) {
                blockedCount++
                return true
            }
            val dot = current.indexOf('.')
            if (dot < 0) break
            current = current.substring(dot + 1)
        }
        val url = uri.toString()
        if (blockedSubstrings.any { url.contains(it, ignoreCase = true) }) {
            blockedCount++
            return true
        }
        return false
    }

    fun resetCounter() { blockedCount = 0 }

    companion object {
        fun loadFromAssets(context: Context): AdBlockEngine {
            val hosts = HashSet<String>()
            val substrings = mutableListOf<String>()
            context.assets.open("blocklist_hosts.txt").use { input ->
                BufferedReader(InputStreamReader(input)).forEachLine { raw ->
                    val line = raw.trim()
                    if (line.isEmpty() || line.startsWith("#") || line.startsWith("!")) return@forEachLine
                    when {
                        line.startsWith("||") -> {
                            val end = line.indexOf('^').takeIf { it > 2 } ?: line.length
                            hosts.add(line.substring(2, end).lowercase())
                        }
                        line.matches(Regex("^(0\\.0\\.0\\.0|127\\.0\\.0\\.1)\\s+\\S+.*$")) -> {
                            val parts = line.split(Regex("\\s+"))
                            if (parts.size > 1) hosts.add(parts[1].lowercase())
                        }
                        else -> substrings.add(line.lowercase())
                    }
                }
            }
            return AdBlockEngine(hosts, substrings)
        }
    }
}
