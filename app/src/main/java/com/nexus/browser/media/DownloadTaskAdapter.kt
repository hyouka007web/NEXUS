package com.nexus.browser.media

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ProgressBar
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.nexus.browser.R

class DownloadTaskAdapter(
    private var items: List<DownloadTask>
) : RecyclerView.Adapter<DownloadTaskAdapter.ViewHolder>() {

    class ViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val title: TextView = itemView.findViewById(R.id.taskTitle)
        val progressBar: ProgressBar = itemView.findViewById(R.id.taskProgressBar)
        val status: TextView = itemView.findViewById(R.id.taskStatus)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
        ViewHolder(LayoutInflater.from(parent.context).inflate(R.layout.item_download_progress, parent, false))

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val task = items[position]
        holder.title.text = task.title
        holder.progressBar.progress = if (task.percent >= 0) task.percent else 0
        holder.progressBar.isIndeterminate = task.percent < 0
        holder.status.text = when (task.state) {
            DownloadState.QUEUED -> "In der Warteschlange…"
            DownloadState.DOWNLOADING -> if (task.percent >= 0) "${task.percent}%" else "Lädt…"
            DownloadState.DONE -> "Fertig"
            DownloadState.FAILED -> "Fehler: ${task.errorMessage ?: "unbekannt"}"
        }
    }

    override fun getItemCount() = items.size

    fun updateItems(newItems: List<DownloadTask>) {
        items = newItems
        notifyDataSetChanged()
    }
}
