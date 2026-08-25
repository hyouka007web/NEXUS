package com.tufblade.browser

import android.os.Bundle
import android.view.Gravity
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.tufblade.browser.media.HarvestedVideo
import com.tufblade.browser.media.VideoHarvesterAdapter
import com.tufblade.browser.media.VideoHarvesterEngine
import kotlin.concurrent.thread

class VideoHarvesterActivity : AppCompatActivity() {
    private lateinit var adapter: VideoHarvesterAdapter
    private lateinit var count: TextView
    private lateinit var search: EditText
    private var all = emptyList<HarvestedVideo>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(getColor(R.color.bg_base)) }
        val header = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(16, 14, 16, 8) }
        header.addView(TextView(this).apply { text = "NEXUS // VIDEO HARVESTER"; textSize = 16f; setTextColor(getColor(R.color.accent_primary)) }, LinearLayout.LayoutParams(0, 52, 1f))
        count = TextView(this).apply { textSize = 12f; setTextColor(getColor(R.color.text_muted)) }
        header.addView(count)
        root.addView(header)
        search = EditText(this).apply { hint = "Videos suchen…"; setSingleLine(true); setTextColor(getColor(R.color.text_primary)); setHintTextColor(getColor(R.color.text_muted)); setPadding(16, 0, 16, 0) }
        root.addView(search, LinearLayout.LayoutParams(-1, 48).apply { setMargins(12, 0, 12, 8) })
        val select = TextView(this).apply { text = "☑ ALLE AUSWÄHLEN"; textSize = 13f; setTextColor(getColor(R.color.accent_primary)); setPadding(16, 10, 16, 10); setOnClickListener { adapter.toggleAll(); updateCount() } }
        root.addView(select)
        adapter = VideoHarvesterAdapter { updateCount() }
        root.addView(RecyclerView(this).apply { layoutManager = LinearLayoutManager(this@VideoHarvesterActivity); adapter = this@VideoHarvesterActivity.adapter }, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)

        search.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, st: Int, c: Int, a: Int) = Unit
            override fun onTextChanged(s: CharSequence?, st: Int, before: Int, count: Int) { adapter.filter(s?.toString().orEmpty()) }
            override fun afterTextChanged(s: android.text.Editable?) = Unit
        })

        val page = intent.getStringExtra(EXTRA_URL).orEmpty()
        if (page.isBlank()) { count.text = "Keine Seite"; return }
        count.text = "Analysiere…"
        thread {
            val found = VideoHarvesterEngine.harvest(page, deepInspect = true)
            runOnUiThread { all = found; adapter.submit(found); updateCount() }
        }
    }

    private fun updateCount() { count.text = "${adapter.selectedCount()} / ${adapter.itemCount()} ausgewählt" }
    companion object { const val EXTRA_URL = "page_url" }
}
