package com.nexus.browser.tabs

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persists the tab strip (URL + title per tab, plus the active index) across process
 * death / app restarts. This restores *which pages were open*, not full page/back-stack
 * state (GeckoView session state serialization would be needed for that) — each saved
 * tab is simply reloaded fresh. Good enough so the user never opens the app to a single
 * blank tab after Android kills it in the background.
 */
data class SavedTab(val url: String, val title: String)

object TabPersistence {
    private const val PREFS = "nexus_tabs"
    private const val KEY_TABS = "tabs"
    private const val KEY_ACTIVE = "active"

    fun save(context: Context, tabs: List<SavedTab>, activeIndex: Int) {
        val arr = JSONArray()
        tabs.forEach { t ->
            arr.put(JSONObject().apply {
                put("url", t.url)
                put("title", t.title)
            })
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_TABS, arr.toString())
            .putInt(KEY_ACTIVE, activeIndex)
            .apply()
    }

    fun restore(context: Context): Pair<List<SavedTab>, Int> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_TABS, null) ?: return emptyList<SavedTab>() to -1
        val tabs = runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                val url = o.optString("url").takeIf { it.startsWith("http") } ?: return@mapNotNull null
                SavedTab(url, o.optString("title", "Neuer Tab"))
            }
        }.getOrDefault(emptyList())
        val active = prefs.getInt(KEY_ACTIVE, 0)
        return tabs to active
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }
}
