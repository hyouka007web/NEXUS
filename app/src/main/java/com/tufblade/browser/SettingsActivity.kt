package com.tufblade.browser

import android.os.Bundle
import android.widget.RadioGroup
import android.widget.Switch
import androidx.appcompat.app.AppCompatActivity

class SettingsActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)
        findViewById<android.widget.ImageButton>(R.id.settingsBackButton).setOnClickListener { finish() }

        val group = findViewById<RadioGroup>(R.id.searchEngineGroup)
        group.check(
            when (NexusSettings.getSearchEngine(this)) {
                NexusSettings.SearchEngine.DUCKDUCKGO -> R.id.engineDuckDuckGo
                NexusSettings.SearchEngine.GOOGLE -> R.id.engineGoogle
                NexusSettings.SearchEngine.BING -> R.id.engineBing
            }
        )
        group.setOnCheckedChangeListener { _, id ->
            NexusSettings.setSearchEngine(this, when (id) {
                R.id.engineGoogle -> NexusSettings.SearchEngine.GOOGLE
                R.id.engineBing -> NexusSettings.SearchEngine.BING
                else -> NexusSettings.SearchEngine.DUCKDUCKGO
            })
        }

        val adBlock = findViewById<Switch>(R.id.adBlockSwitch)
        adBlock.isChecked = NexusSettings.isAdBlockEnabled(this)
        adBlock.setOnCheckedChangeListener { _, enabled ->
            NexusSettings.setAdBlockEnabled(this, enabled)
        }
    }
}
