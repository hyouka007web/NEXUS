package com.nexus.browser.media

import java.util.Collections
import java.util.UUID

enum class DownloadState { QUEUED, DOWNLOADING, DONE, FAILED }

data class DownloadTask(
    val id: String = UUID.randomUUID().toString().replace("-", "").take(12),
    val title: String,
    val sourceUrl: String,
    var percent: Int = 0,
    var state: DownloadState = DownloadState.QUEUED,
    var errorMessage: String? = null
)

/**
 * In-memory registry of downloads currently running in this app process, so the
 * Mediathek "In Arbeit" tab can show a live progress bar per video. Downloads only run
 * while NEXUS is in the foreground/alive (there is no background download service yet),
 * so this intentionally does not persist across a full process kill — a task that was
 * still running when the process died is simply gone on next launch, same as the
 * underlying download itself.
 */
object DownloadRepository {
    private val tasks = Collections.synchronizedList(mutableListOf<DownloadTask>())
    private val listeners = Collections.synchronizedList(mutableListOf<() -> Unit>())

    fun addListener(listener: () -> Unit) = listeners.add(listener)
    fun removeListener(listener: () -> Unit) = listeners.remove(listener)

    private fun notifyChanged() {
        // Copy to avoid ConcurrentModificationException if a listener unregisters itself.
        listeners.toList().forEach { it.invoke() }
    }

    fun start(title: String, sourceUrl: String): DownloadTask {
        val task = DownloadTask(title = title, sourceUrl = sourceUrl, state = DownloadState.DOWNLOADING)
        tasks.add(task)
        notifyChanged()
        return task
    }

    fun update(task: DownloadTask, percent: Int) {
        task.percent = percent.coerceIn(0, 100)
        task.state = DownloadState.DOWNLOADING
        notifyChanged()
    }

    fun finish(task: DownloadTask) {
        task.percent = 100
        task.state = DownloadState.DONE
        notifyChanged()
        // Keep it visible briefly as "fertig" instead of yanking it instantly — the
        // Mediathek UI removes DONE tasks itself once "Meine Downloads" is refreshed.
    }

    fun fail(task: DownloadTask, message: String) {
        task.state = DownloadState.FAILED
        task.errorMessage = message
        notifyChanged()
    }

    fun clearFinished() {
        tasks.removeAll { it.state == DownloadState.DONE || it.state == DownloadState.FAILED }
        notifyChanged()
    }

    fun activeAndRecent(): List<DownloadTask> = tasks.toList()
}
