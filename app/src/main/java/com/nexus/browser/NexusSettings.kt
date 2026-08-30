package com.nexus.browser

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class PinnedAppPref(val label: String, val url: String)

object NexusSettings {
    private const val PREFS = "nexus_settings"
    private const val KEY_SEARCH_ENGINE = "search_engine"
    private const val KEY_ADBLOCK_ENABLED = "adblock_enabled"
    private const val KEY_PINNED_APPS = "pinned_apps"

    enum class SearchEngine(val label: String, val queryUrl: String) {
        DUCKDUCKGO("DuckDuckGo", "https://start.duckduckgo.com/?q="),
        GOOGLE("Google", "https://www.google.com/search?q="),
        BING("Bing", "https://www.bing.com/search?q=")
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun getSearchEngine(context: Context): SearchEngine =
        runCatching {
            SearchEngine.valueOf(
                prefs(context).getString(KEY_SEARCH_ENGINE, SearchEngine.DUCKDUCKGO.name)
                    ?: SearchEngine.DUCKDUCKGO.name
            )
        }.getOrDefault(SearchEngine.DUCKDUCKGO)

    fun setSearchEngine(context: Context, engine: SearchEngine) {
        prefs(context).edit().putString(KEY_SEARCH_ENGINE, engine.name).apply()
    }

    fun isAdBlockEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ADBLOCK_ENABLED, true)

    fun setAdBlockEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ADBLOCK_ENABLED, enabled).apply()
    }

    fun getPinnedApps(context: Context): List<PinnedAppPref> {
        val raw = prefs(context).getString(KEY_PINNED_APPS, null) ?: return defaultPinnedApps()
        return runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                PinnedAppPref(o.getString("label"), o.getString("url"))
            }
        }.getOrDefault(defaultPinnedApps())
    }

    fun addPinnedApp(context: Context, app: PinnedAppPref) {
        savePinnedApps(context, getPinnedApps(context) + app)
    }

    fun removePinnedApp(context: Context, app: PinnedAppPref) {
        savePinnedApps(context, getPinnedApps(context).filterNot { it.url == app.url })
    }

    private fun savePinnedApps(context: Context, apps: List<PinnedAppPref>) {
        val arr = JSONArray()
        apps.forEach { app ->
            arr.put(JSONObject().apply {
                put("label", app.label)
                put("url", app.url)
            })
        }
        prefs(context).edit().putString(KEY_PINNED_APPS, arr.toString()).apply()
    }

    private fun defaultPinnedApps() = listOf(
        PinnedAppPref("YT", "https://m.youtube.com"),
        PinnedAppPref("SP", "https://open.spotify.com"),
        PinnedAppPref("DC", "https://discord.com/app")
    )
}
