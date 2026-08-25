package com.tufblade.browser

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import androidx.recyclerview.widget.GridLayoutManager
import com.tufblade.browser.media.VideoAdapter
import com.tufblade.browser.media.VideoDownloader
import java.io.File

class MediathekActivity : AppCompatActivity() {
    private lateinit var adapter: VideoAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_mediathek)
        findViewById<android.widget.ImageButton>(R.id.mediathekBackButton).setOnClickListener { finish() }

        val grid = findViewById<androidx.recyclerview.widget.RecyclerView>(R.id.mediathekGrid)
        val empty = findViewById<android.widget.TextView>(R.id.mediathekEmptyState)
        grid.layoutManager = GridLayoutManager(this, 2)

        val entries = VideoDownloader.loadIndex(this)
        adapter = VideoAdapter(entries, ::playVideo, ::confirmDelete)
        grid.adapter = adapter
        empty.visibility = if (entries.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE
    }

    private fun playVideo(entry: com.tufblade.browser.media.VideoEntry) {
        val file = File(entry.filePath)
        if (!file.exists()) return
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "video/*")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
    }

    private fun confirmDelete(entry: com.tufblade.browser.media.VideoEntry) {
        AlertDialog.Builder(this)
            .setTitle("Video löschen?")
            .setMessage(entry.title)
            .setPositiveButton("Löschen") { _, _ ->
                VideoDownloader.delete(this, entry)
                refresh()
            }
            .setNegativeButton("Abbrechen", null)
            .show()
    }

    private fun refresh() {
        val entries = VideoDownloader.loadIndex(this)
        adapter.updateItems(entries)
        findViewById<android.widget.TextView>(R.id.mediathekEmptyState).visibility =
            if (entries.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE
    }
}
