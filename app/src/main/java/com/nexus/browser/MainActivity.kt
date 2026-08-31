package com.nexus.browser

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.KeyEvent
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.snackbar.Snackbar
import com.nexus.browser.adblock.AdBlockEngine
import com.nexus.browser.adblock.RedirectShield
import com.nexus.browser.databinding.ActivityMainBinding
import com.nexus.browser.media.MediaLinkFinder
import com.nexus.browser.media.VideoDownloader
import com.nexus.browser.tabs.SavedTab
import com.nexus.browser.tabs.Tab
import com.nexus.browser.tabs.TabManager
import com.nexus.browser.tabs.TabPersistence
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoSessionSettings
import org.mozilla.geckoview.GeckoView
import kotlin.concurrent.thread

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var adBlockEngine: AdBlockEngine
    private val tabManager = TabManager()
    private val handler = Handler(Looper.getMainLooper())
    private var geckoView: GeckoView? = null
    private var sidebarExpanded = false
    private val startPage = HOME_SENTINEL
    private var lastScrape: ScrapeResult? = null
    private var panelDismiss: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val crash = filesDir.resolve(LAST_CRASH_FILE_NAME)
        if (crash.exists()) {
            showStackTrace(crash.readText())
            crash.delete()
            return
        }

        adBlockEngine = AdBlockEngine.loadFromAssets(this)
        adBlockEngine.enabled = NexusSettings.isAdBlockEnabled(this)
        setupUi()
        restoreTabsOrOpenDefault()
    }

    private fun restoreTabsOrOpenDefault() {
        val (saved, activeIndex) = TabPersistence.restore(this)
        if (saved.isEmpty()) {
            openNewTab(startPage)
            return
        }
        // Older versions persisted the external DuckDuckGo homepage as the
        // "home" URL; route those onto the new native start page instead.
        saved.forEach { openNewTab(migrateLegacyHomeUrl(it.url)) }
        switchToTab(activeIndex.coerceIn(0, tabManager.tabs.lastIndex))
    }

    private fun migrateLegacyHomeUrl(url: String): String =
        if (url == "https://start.duckduckgo.com") startPage else url

    private fun persistTabs() {
        val saved = tabManager.tabs.map { SavedTab(it.url, it.title) }
        TabPersistence.save(this, saved, tabManager.activeIndex)
    }

    private fun setupUi() {
        binding.menuButton.setOnClickListener { showMainMenu(it) }
        binding.sidebarToggle.setOnClickListener { toggleSidebar() }

        binding.urlField.setOnEditorActionListener { _, actionId, event ->
            if (actionId == EditorInfo.IME_ACTION_GO ||
                event?.keyCode == KeyEvent.KEYCODE_ENTER
            ) {
                loadFromUrlField()
                true
            } else false
        }
        binding.reloadButton.setOnClickListener {
            tabManager.activeTab()?.takeIf { it.url != HOME_SENTINEL }?.session?.reload()
        }

        binding.startSearchButton.setOnClickListener { loadFromStartPage() }
        binding.startSearchField.setOnEditorActionListener { _, actionId, event ->
            if (actionId == EditorInfo.IME_ACTION_SEARCH ||
                event?.keyCode == KeyEvent.KEYCODE_ENTER
            ) {
                loadFromStartPage()
                true
            } else false
        }

        renderSidebar()
    }

    private fun loadFromStartPage() {
        val input = binding.startSearchField.text.toString().trim()
        if (input.isBlank()) return
        binding.startSearchField.setText("")
        navigate(resolveInput(input))
    }

    private fun showStackTrace(stackTrace: String) {
        binding.contentContainer.removeAllViews()
        val text = TextView(this).apply {
            setTextColor(Color.WHITE)
            setBackgroundColor(getColor(R.color.bg_base))
            typeface = Typeface.MONOSPACE
            text = "NEXUS CRASH REPORT\n\n$stackTrace"
            setTextIsSelectable(true)
            setPadding(24, 24, 24, 24)
        }
        binding.contentContainer.addView(ScrollView(this).apply { addView(text) })
    }

    private fun renderSidebar() {
        binding.sidebarActions.removeAllViews()
        val buttons = listOf(
            "⌂" to { navigate(startPage) },
            "‹" to { tabManager.activeTab()?.session?.let { markAppNavigation(it); it.goBack(true) } },
            "›" to { tabManager.activeTab()?.session?.let { markAppNavigation(it); it.goForward(true) } },
            "↻" to { tabManager.activeTab()?.session?.reload() },
            "+" to { openNewTab(startPage) },
            "⌁" to { openVideoHarvester() },
            "↓" to { downloadVideoFromCurrentTab() },
            "▦" to { startActivity(android.content.Intent(this, MediathekActivity::class.java)) }
        )
        buttons.forEach { (label, action) ->
            val button = TextView(this).apply {
                text = label
                textSize = 20f
                gravity = Gravity.CENTER
                setTextColor(getColor(R.color.text_muted))
                background = getDrawable(R.drawable.ripple_accent_circle)
                contentDescription = label
                setOnClickListener { action() }
                layoutParams = LinearLayout.LayoutParams(
                    resources.getDimensionPixelSize(R.dimen.sidebar_icon_size),
                    resources.getDimensionPixelSize(R.dimen.sidebar_icon_size)
                ).apply {
                    gravity = Gravity.CENTER_HORIZONTAL
                    topMargin = resources.getDimensionPixelSize(R.dimen.space_8)
                }
            }
            binding.sidebarActions.addView(button)
        }
    }

    private fun toggleSidebar() {
        sidebarExpanded = !sidebarExpanded
        val width = if (sidebarExpanded) 112 else resources.getDimensionPixelSize(R.dimen.sidebar_collapsed_width)
        binding.sidebar.layoutParams.width = width
        binding.sidebar.requestLayout()
        binding.sidebarLabel.visibility = if (sidebarExpanded) View.VISIBLE else View.GONE
        binding.sidebarToggle.text = if (sidebarExpanded) "‹" else "›"
    }

    private fun showMainMenu(anchor: View) {
        PopupMenu(this, anchor).apply {
            menu.add(0, 1, 0, getString(R.string.menu_new_tab))
            menu.add(0, 2, 1, getString(R.string.menu_video_harvester))
            menu.add(0, 3, 2, getString(R.string.menu_download))
            menu.add(0, 4, 3, getString(R.string.menu_mediathek))
            menu.add(0, 5, 4, getString(R.string.menu_settings))
            setOnMenuItemClickListener {
                when (it.itemId) {
                    1 -> openNewTab(startPage)
                    2 -> openVideoHarvester()
                    3 -> downloadVideoFromCurrentTab()
                    4 -> startActivity(android.content.Intent(this@MainActivity, MediathekActivity::class.java))
                    5 -> startActivity(android.content.Intent(this@MainActivity, SettingsActivity::class.java))
                }
                true
            }
            show()
        }
    }

    private fun openNewTab(url: String, load: Boolean = true): Int {
        val session = createSession()
        val index = tabManager.addTab(Tab(session, "Neuer Tab", url))
        if (load && url != HOME_SENTINEL) {
            markAppNavigation(session)
            session.loadUri(url)
        }
        renderTabs()
        switchToTab(index)
        return index
    }

    /** Flags the next onLoadRequest on this session as app-initiated (address bar,
     *  start page search, sidebar back/forward/home) rather than an in-page redirect —
     *  see [com.nexus.browser.adblock.RedirectShield.pendingAppNavigation]. */
    private fun markAppNavigation(session: GeckoSession) {
        (session.navigationDelegate as? RedirectShield)?.pendingAppNavigation = true
    }

    private fun createSession(): GeckoSession {
        val settings = GeckoSessionSettings.Builder()
            .usePrivateMode(false)
            .userAgentMode(GeckoSessionSettings.USER_AGENT_MODE_MOBILE)
            .build()

        val session = GeckoSession(settings)
        val shield = RedirectShield(
            adBlockEngine = adBlockEngine,
            onBlocked = { uri, reason ->
                runOnUiThread { showBlockedPanel(uri, reason) }
            },
            onTitleUpdate = { updated, title ->
                runOnUiThread {
                    tabManager.tabs.find { it.session == updated }?.let { tab ->
                        tab.title = title?.takeIf { it.isNotBlank() } ?: tab.url
                        renderTabs()
                    }
                }
            },
            onLoadingStateChange = { loading ->
                runOnUiThread {
                    binding.loadProgress.visibility = if (loading) View.VISIBLE else View.GONE
                }
            },
            onAllowedPopup = { popupUri ->
                // GeckoView calls onNewSession on the UI thread. Returning the
                // newly-created session synchronously is required by its API.
                val index = openNewTab(popupUri, load = false)
                tabManager.tabs.getOrNull(index)?.session
            }
        )

        session.navigationDelegate = shield
        session.contentDelegate = shield
        session.progressDelegate = shield
        session.open((application as NexusApp).geckoRuntime)
        return session
    }

    private fun switchToTab(index: Int) {
        tabManager.setActive(index)
        val tab = tabManager.activeTab() ?: return

        if (tab.url == HOME_SENTINEL) {
            showStartPage()
        } else {
            showWebContent()
            val view = geckoView ?: GeckoView(this).also {
                geckoView = it
                binding.contentContainer.addView(
                    it,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                )
            }
            // GeckoView requires releaseSession() before assigning another session.
            view.releaseSession()
            view.setSession(tab.session)
        }

        binding.urlField.setText(if (tab.url == HOME_SENTINEL) "" else tab.url)
        renderTabs()
    }

    private fun showStartPage() {
        binding.startPageContainer.visibility = View.VISIBLE
        binding.contentContainer.visibility = View.GONE
        binding.startEngineLabel.text =
            "Suchmaschine: ${NexusSettings.getSearchEngine(this).label} · ändern in Einstellungen"
    }

    private fun showWebContent() {
        binding.startPageContainer.visibility = View.GONE
        binding.contentContainer.visibility = View.VISIBLE
    }

    private fun closeTab(index: Int) {
        val closingActive = index == tabManager.activeIndex
        if (closingActive) geckoView?.releaseSession()
        tabManager.closeTab(index)
        if (tabManager.tabs.isEmpty()) openNewTab(startPage)
        else switchToTab(tabManager.activeIndex.coerceAtMost(tabManager.tabs.lastIndex))
    }

    private fun renderTabs() {
        binding.tabStrip.removeAllViews()
        tabManager.tabs.forEachIndexed { index, tab ->
            val chip = LayoutInflater.from(this).inflate(R.layout.item_tab, binding.tabStrip, false)
            val title = chip.findViewById<TextView>(R.id.tabTitle)
            val close = chip.findViewById<TextView>(R.id.tabClose)
            title.text = tab.title.ifBlank { "Tab" }
            title.setTextColor(
                if (index == tabManager.activeIndex) getColor(R.color.accent_primary)
                else getColor(R.color.text_muted)
            )
            chip.setOnClickListener { switchToTab(index) }
            close.setOnClickListener { closeTab(index) }
            binding.tabStrip.addView(chip)
        }
    }

    private fun loadFromUrlField() {
        val input = binding.urlField.text.toString().trim()
        if (input.isBlank()) return
        navigate(resolveInput(input))
    }

    private fun resolveInput(raw: String): String = when {
        raw.startsWith("http://") || raw.startsWith("https://") -> raw
        raw.contains(" ") || !raw.contains(".") -> {
            val engine = NexusSettings.getSearchEngine(this)
            engine.queryUrl + java.net.URLEncoder.encode(raw, "UTF-8")
        }
        else -> "https://$raw"
    }

    private fun navigate(url: String) {
        val tab = tabManager.activeTab() ?: return
        tab.url = url
        if (url == HOME_SENTINEL) {
            showStartPage()
            binding.urlField.setText("")
            renderTabs()
            return
        }
        adBlockEngine.resetCounter()
        showWebContent()
        markAppNavigation(tab.session)
        tab.session.loadUri(url)
        binding.urlField.setText(url)
        renderTabs()
    }

    private fun openVideoHarvester() {
        val url = tabManager.activeTab()?.url ?: return
        if (!url.startsWith("http")) {
            toastNoPageLoaded()
            return
        }
        startActivity(android.content.Intent(this, VideoHarvesterActivity::class.java).putExtra(VideoHarvesterActivity.EXTRA_URL, url))
    }

    private fun toastNoPageLoaded() {
        android.widget.Toast.makeText(
            this,
            "Erst eine Seite öffnen – auf der Startseite gibt es nichts zu durchsuchen.",
            android.widget.Toast.LENGTH_SHORT
        ).show()
    }

    private fun downloadVideoFromCurrentTab() {
        val tab = tabManager.activeTab() ?: return
        val pageUrl = tab.url.ifBlank { binding.urlField.text.toString() }
        if (!pageUrl.startsWith("http")) {
            toastNoPageLoaded()
            return
        }
        showBottomPanel("MEDIA SNIFFER", "Suche nach direkten Quellen und öffentlichen HLS-Streams…", null)

        thread {
            runCatching {
                val candidates = MediaLinkFinder.findVideoUrls(pageUrl)
                if (candidates.isEmpty()) error("Keine direkte Videoquelle gefunden")
                VideoDownloader.download(this, candidates.first(), tab.title, pageUrl)
            }.onSuccess { entry ->
                runOnUiThread {
                    showBottomPanel(
                        "DOWNLOAD FERTIG",
                        entry.title.take(48),
                        { startActivity(android.content.Intent(this, MediathekActivity::class.java)) }
                    )
                }
            }.onFailure { error ->
                runOnUiThread {
                    showBottomPanel("DOWNLOAD", error.message ?: "Unbekannter Fehler", null)
                }
            }
        }
    }

    private fun runScraper() {
        val url = tabManager.activeTab()?.url ?: return
        if (!url.startsWith("http")) return
        showBottomPanel("SCRAPER", "Analysiere öffentliche HTML-Struktur…", null)

        thread {
            runCatching { ScraperEngine.scrape(url) }
                .onSuccess { result ->
                    runOnUiThread {
                        lastScrape = result
                        showBottomPanel(
                            "SCRAPER FERTIG",
                            "${result.links.size} Links · ${result.media.size} Medien · ${result.htmlSize / 1024} KB",
                            { showScrapeDialog(result) }
                        )
                    }
                }
                .onFailure { error ->
                    runOnUiThread {
                        showBottomPanel("SCRAPER", error.message ?: "Analyse fehlgeschlagen", null)
                    }
                }
        }
    }

    private fun showScrapeDialog(result: ScrapeResult) {
        val all = buildString {
            appendLine(result.title)
            appendLine("HTML: ${result.htmlSize} Bytes")
            appendLine()
            appendLine("LINKS")
            result.links.take(100).forEach { appendLine(it) }
            appendLine()
            appendLine("MEDIEN")
            result.media.take(100).forEach { appendLine(it) }
        }
        val text = TextView(this).apply {
            text = all
            typeface = Typeface.MONOSPACE
            textSize = 12f
            setTextColor(getColor(R.color.text_primary))
            setPadding(20, 20, 20, 20)
            setTextIsSelectable(true)
        }
        AlertDialog.Builder(this)
            .setTitle("NEXUS SCRAPER")
            .setView(ScrollView(this).apply { addView(text) })
            .setPositiveButton("Schließen", null)
            .show()
    }

    private fun showBlockedPanel(uri: String, reason: RedirectShield.BlockReason) {
        if (reason == RedirectShield.BlockReason.AD_HOST) {
            binding.shieldBadge.text = adBlockEngine.blockedCount.toString()
            return
        }
        val title = when (reason) {
            RedirectShield.BlockReason.POPUP_NO_GESTURE -> "POPUP BLOCKIERT"
            RedirectShield.BlockReason.REDIRECT_NO_GESTURE -> "REDIRECT BLOCKIERT"
            else -> "BLOCKIERT"
        }
        showBottomPanel(title, uri, {
            openNewTab(uri)
        })
        binding.shieldBadge.text = adBlockEngine.blockedCount.toString()
    }

    private fun showBottomPanel(title: String, message: String, action: (() -> Unit)?) {
        panelDismiss?.let(handler::removeCallbacks)
        binding.snifferPanel.removeAllViews()
        binding.snifferPanel.visibility = View.VISIBLE

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val textBox = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        textBox.addView(TextView(this).apply {
            text = title
            textSize = 12f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(getColor(R.color.accent_primary))
        })
        textBox.addView(TextView(this).apply {
            text = message
            textSize = 13f
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
            setTextColor(getColor(R.color.text_primary))
        })
        row.addView(textBox)

        if (action != null) {
            row.addView(TextView(this).apply {
                text = "ÖFFNEN"
                textSize = 12f
                setTypeface(typeface, Typeface.BOLD)
                setTextColor(getColor(R.color.bg_base))
                gravity = Gravity.CENTER
                background = getDrawable(R.drawable.ripple_accent)
                setPadding(18, 12, 18, 12)
                setOnClickListener {
                    action()
                    binding.snifferPanel.visibility = View.GONE
                }
            })
        }
        binding.snifferPanel.addView(row)

        panelDismiss = Runnable { binding.snifferPanel.visibility = View.GONE }
        handler.postDelayed(panelDismiss!!, if (action == null) 4200L else 6500L)
    }

    override fun onResume() {
        super.onResume()
        if (::adBlockEngine.isInitialized) {
            adBlockEngine.enabled = NexusSettings.isAdBlockEnabled(this)
        }
        if (::binding.isInitialized) renderSidebar()
    }

    override fun onPause() {
        super.onPause()
        persistTabs()
    }

    override fun onDestroy() {
        panelDismiss?.let(handler::removeCallbacks)
        geckoView?.releaseSession()
        tabManager.closeAll()
        super.onDestroy()
    }
}
