package com.nexus.browser

import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.nexus.browser.media.DownloadRepository
import com.nexus.browser.media.DownloadState
import com.nexus.browser.media.DownloadTaskAdapter
import com.nexus.browser.media.VideoAdapter
import com.nexus.browser.media.VideoDownloader
import com.nexus.browser.media.VideoEntry

/**
 * Mediathek. Two views:
 *  - "In Arbeit": live progress bars for downloads currently running in this process.
 *  - "Meine Downloads": already-downloaded videos, read straight from local storage —
 *    this view needs no network at all and works fully offline.
 */
class MediathekActivity : AppCompatActivity() {
    private lateinit var videoAdapter: VideoAdapter
    private lateinit var progressAdapter: DownloadTaskAdapter
    private lateinit var progressList: RecyclerView
    private lateinit var grid: RecyclerView
    private lateinit var empty: android.widget.TextView
    private lateinit var tabInProgress: android.widget.TextView
    private lateinit var tabDownloaded: android.widget.TextView

    private var showingProgress = true

    private val repositoryListener: () -> Unit = { runOnUiThread { refreshProgress() } }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_mediathek)
        findViewById<android.widget.ImageButton>(R.id.mediathekBackButton).setOnClickListener { finish() }

        grid = findViewById(R.id.mediathekGrid)
        progressList = findViewById(R.id.mediathekProgressList)
        empty = findViewById(R.id.mediathekEmptyState)
        tabInProgress = findViewById(R.id.tabInProgress)
        tabDownloaded = findViewById(R.id.tabDownloaded)

        grid.layoutManager = GridLayoutManager(this, 2)
        progressList.layoutManager = LinearLayoutManager(this)

        videoAdapter = VideoAdapter(emptyList(), ::playVideo, ::confirmDelete)
        grid.adapter = videoAdapter

        progressAdapter = DownloadTaskAdapter(emptyList())
        progressList.adapter = progressAdapter

        tabInProgress.setOnClickListener { showTab(progress = true) }
        tabDownloaded.setOnClickListener { showTab(progress = false) }

        showTab(progress = DownloadRepository.activeAndRecent().any { it.state == DownloadState.DOWNLOADING || it.state == DownloadState.QUEUED })
    }

    override fun onStart() {
        super.onStart()
        DownloadRepository.addListener(repositoryListener)
        refreshProgress()
        refreshDownloads()
    }

    override fun onStop() {
        DownloadRepository.removeListener(repositoryListener)
        super.onStop()
    }

    private fun showTab(progress: Boolean) {
        showingProgress = progress
        tabInProgress.setTextColor(getColor(if (progress) R.color.accent_primary else R.color.text_muted))
        tabDownloaded.setTextColor(getColor(if (progress) R.color.text_muted else R.color.accent_primary))
        progressList.visibility = if (progress) View.VISIBLE else View.GONE
        grid.visibility = if (progress) View.GONE else View.VISIBLE
        if (progress) refreshProgress() else refreshDownloads()
    }

    private fun refreshProgress() {
        val tasks = DownloadRepository.activeAndRecent()
        progressAdapter.updateItems(tasks)
        if (showingProgress) {
            empty.visibility = if (tasks.isEmpty()) View.VISIBLE else View.GONE
            empty.text = "Keine Downloads in Arbeit.\nStarte einen Download über den Video Harvester."
        }
        // A finished download should show up under "Meine Downloads" without the user
        // having to leave and reopen the Mediathek.
        if (tasks.any { it.state == DownloadState.DONE }) refreshDownloads()
    }

    private fun refreshDownloads() {
        val entries = VideoDownloader.loadIndex(this)
        videoAdapter.updateItems(entries)
        if (!showingProgress) {
            empty.visibility = if (entries.isEmpty()) View.VISIBLE else View.GONE
            empty.text = getString(R.string.mediathek_empty)
        }
    }

    private fun playVideo(entry: VideoEntry) {
        startActivity(Intent(this, NexusPlayerActivity::class.java).apply {
            putExtra(NexusPlayerActivity.EXTRA_FILE_PATH, entry.filePath)
            putExtra(NexusPlayerActivity.EXTRA_TITLE, entry.title)
        })
    }

    private fun confirmDelete(entry: VideoEntry) {
        AlertDialog.Builder(this)
            .setTitle("Video löschen?")
            .setMessage(entry.title)
            .setPositiveButton("Löschen") { _, _ ->
                VideoDownloader.delete(this, entry)
                refreshDownloads()
            }
            .setNegativeButton("Abbrechen", null)
            .show()
    }
}
