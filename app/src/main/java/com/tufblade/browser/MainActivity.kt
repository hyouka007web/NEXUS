package com.tufblade.browser

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
import com.tufblade.browser.adblock.AdBlockEngine
import com.tufblade.browser.adblock.RedirectShield
import com.tufblade.browser.databinding.ActivityMainBinding
import com.tufblade.browser.media.MediaLinkFinder
import com.tufblade.browser.media.VideoDownloader
import com.tufblade.browser.tabs.Tab
import com.tufblade.browser.tabs.TabManager
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
    private val startPage = "https://start.duckduckgo.com"
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
        openNewTab(startPage)
    }

    private fun setupUi() {
        binding.menuButton.setOnClickListener { showMainMenu(it) }
        binding.scraperButton.setOnClickListener { openVideoHarvester() }
        binding.sidebarToggle.setOnClickListener { toggleSidebar() }

        binding.urlField.setOnEditorActionListener { _, actionId, event ->
            if (actionId == EditorInfo.IME_ACTION_GO ||
                event?.keyCode == KeyEvent.KEYCODE_ENTER
            ) {
                loadFromUrlField()
                true
            } else false
        }

        binding.homeButton.setOnClickListener { navigate(startPage) }
        binding.backButton.setOnClickListener { tabManager.activeTab()?.session?.goBack(true) }
        binding.forwardButton.setOnClickListener { tabManager.activeTab()?.session?.goForward(true) }
        binding.reloadButton.setOnClickListener { tabManager.activeTab()?.session?.reload() }
        binding.downloadButton.setOnClickListener { downloadVideoFromCurrentTab() }
        binding.mediaButton.setOnClickListener {
            startActivity(android.content.Intent(this, MediathekActivity::class.java))
        }

        renderSidebar()
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
            "‹" to { tabManager.activeTab()?.session?.goBack(true) },
            "›" to { tabManager.activeTab()?.session?.goForward(true) },
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
        if (load) session.loadUri(url)
        renderTabs()
        switchToTab(index)
        return index
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
        binding.urlField.setText(tab.url)
        renderTabs()
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
        var input = binding.urlField.text.toString().trim()
        if (input.isBlank()) return
        input = when {
            input.startsWith("http://") || input.startsWith("https://") -> input
            input.contains(" ") || !input.contains(".") -> {
                val engine = NexusSettings.getSearchEngine(this)
                engine.queryUrl + java.net.URLEncoder.encode(input, "UTF-8")
            }
            else -> "https://$input"
        }
        navigate(input)
    }

    private fun navigate(url: String) {
        val tab = tabManager.activeTab() ?: return
        adBlockEngine.resetCounter()
        tab.url = url
        tab.session.loadUri(url)
        binding.urlField.setText(url)
        renderTabs()
    }

    private fun openVideoHarvester() {
        val url = tabManager.activeTab()?.url ?: return
        if (!url.startsWith("http")) return
        startActivity(android.content.Intent(this, VideoHarvesterActivity::class.java).putExtra(VideoHarvesterActivity.EXTRA_URL, url))
    }

    private fun downloadVideoFromCurrentTab() {
        val tab = tabManager.activeTab() ?: return
        val pageUrl = tab.url.ifBlank { binding.urlField.text.toString() }
        if (!pageUrl.startsWith("http")) return
        showBottomPanel("MEDIA SNIFFER", "Suche nach direkten Videoquellen…", null)

        thread {
            runCatching {
                val candidates = MediaLinkFinder.findVideoUrls(pageUrl)
                if (candidates.isEmpty()) error("Keine direkte Videoquelle gefunden")
                VideoDownloader.download(this, candidates.first(), tab.title)
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

    override fun onDestroy() {
        panelDismiss?.let(handler::removeCallbacks)
        geckoView?.releaseSession()
        tabManager.closeAll()
        super.onDestroy()
    }
}
