package com.nexus.browser.media

import android.graphics.Typeface
import android.view.ViewGroup
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

class VideoHarvesterAdapter(private val onChanged: () -> Unit) : RecyclerView.Adapter<VideoHarvesterAdapter.Holder>() {
    private var all = emptyList<HarvestedVideo>()
    private var shown = emptyList<HarvestedVideo>()
    private val selected = LinkedHashSet<String>()

    fun submit(items: List<HarvestedVideo>) { all = items; selected.clear(); items.forEach { selected.add(it.url) }; shown = items; notifyDataSetChanged() }
    fun filter(q: String) { shown = if (q.isBlank()) all else all.filter { listOf(it.title, it.url, it.host, it.type).any { v -> v.contains(q, true) } }; notifyDataSetChanged() }
    fun toggleAll() { if (selected.size == all.size) selected.clear() else { selected.clear(); all.forEach { selected.add(it.url) } }; notifyDataSetChanged(); onChanged() }
    fun selectedCount() = selected.size
    fun itemCount() = all.size
    fun selectedItems(): List<HarvestedVideo> = all.filter { selected.contains(it.url) }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder = Holder(LinearLayout(parent.context).apply {
        orientation = LinearLayout.HORIZONTAL; setPadding(12, 10, 12, 10)
        addView(CheckBox(context), LinearLayout.LayoutParams(44, 48))
        addView(LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }, LinearLayout.LayoutParams(0, -2, 1f))
    })
    override fun getItemCount() = shown.size
    override fun onBindViewHolder(holder: Holder, position: Int) {
        val item = shown[position]
        holder.box.isChecked = selected.contains(item.url)
        holder.title.text = item.title
        holder.title.setTypeface(null, Typeface.BOLD)
        holder.meta.text = "${item.type} · ${item.host}\n${item.status}\n${item.url}"
        holder.box.setOnClickListener { if (holder.box.isChecked) selected.add(item.url) else selected.remove(item.url); onChanged() }
        holder.itemView.setOnClickListener { holder.box.performClick() }
    }
    class Holder(view: LinearLayout) : RecyclerView.ViewHolder(view) {
        val box = view.getChildAt(0) as CheckBox
        private val body = view.getChildAt(1) as LinearLayout
        val title = TextView(view.context).also { body.addView(it) }
        val meta = TextView(view.context).also { body.addView(it) }
    }
}
