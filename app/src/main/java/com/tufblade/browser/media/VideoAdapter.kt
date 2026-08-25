package com.tufblade.browser.media

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.tufblade.browser.R

class VideoAdapter(
    private var items: List<VideoEntry>,
    private val onClick: (VideoEntry) -> Unit,
    private val onLongClick: (VideoEntry) -> Unit
) : RecyclerView.Adapter<VideoViewHolder>() {
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
        VideoViewHolder(LayoutInflater.from(parent.context).inflate(R.layout.item_video, parent, false))

    override fun onBindViewHolder(holder: VideoViewHolder, position: Int) =
        holder.bind(items[position], onClick, onLongClick)

    override fun getItemCount() = items.size

    fun updateItems(newItems: List<VideoEntry>) {
        items = newItems
        notifyDataSetChanged()
    }
}

class VideoViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
    fun bind(entry: VideoEntry, onClick: (VideoEntry) -> Unit, onLongClick: (VideoEntry) -> Unit) {
        itemView.findViewById<TextView>(R.id.videoTitle).text = entry.title
        itemView.findViewById<TextView>(R.id.videoMeta).text =
            "${entry.sizeBytes / 1024 / 1024} MB · ${entry.downloadedAt}"
        itemView.setOnClickListener { onClick(entry) }
        itemView.setOnLongClickListener { onLongClick(entry); true }
    }
}
