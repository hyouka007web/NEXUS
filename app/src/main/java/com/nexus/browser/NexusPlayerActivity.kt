package com.nexus.browser

import android.net.Uri
import android.os.Bundle
import android.os.CountDownTimer
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.ImageButton
import android.widget.PopupMenu
import android.widget.ProgressBar
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import android.widget.VideoView
import androidx.appcompat.app.AppCompatActivity
import java.io.File
import java.util.Locale

/**
 * Local-file video player styled after YouTube's mobile player: video on top, title +
 * details below, tap-to-toggle overlay controls, and a bonus sleep timer (clock icon in
 * the top-right of the overlay). Picking a duration replaces the clock icon with a live
 * countdown; when it reaches zero the video is paused — nothing else in the app is
 * affected, and the timer never closes the player itself.
 */
class NexusPlayerActivity : AppCompatActivity() {

    private lateinit var videoView: VideoView
    private lateinit var overlay: View
    private lateinit var tapCatcher: View
    private lateinit var playPauseButton: ImageButton
    private lateinit var sleepTimerIcon: ImageButton
    private lateinit var sleepTimerLabel: TextView
    private lateinit var seekBar: SeekBar
    private lateinit var currentTimeView: TextView
    private lateinit var totalTimeView: TextView
    private lateinit var loadingSpinner: ProgressBar

    private val handler = Handler(Looper.getMainLooper())
    private var userIsSeeking = false
    private var overlayVisible = true
    private var sleepTimer: CountDownTimer? = null
    private var pauseAfterCurrentVideo = false

    private val progressTicker = object : Runnable {
        override fun run() {
            if (!userIsSeeking && videoView.duration > 0) {
                seekBar.max = videoView.duration
                seekBar.progress = videoView.currentPosition
                currentTimeView.text = formatTime(videoView.currentPosition)
                totalTimeView.text = formatTime(videoView.duration)
            }
            handler.postDelayed(this, 400)
        }
    }

    private val autoHideOverlay = Runnable {
        if (videoView.isPlaying) setOverlayVisible(false)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_nexus_player)

        videoView = findViewById(R.id.playerVideoView)
        overlay = findViewById(R.id.playerOverlay)
        tapCatcher = findViewById(R.id.playerTapCatcher)
        playPauseButton = findViewById(R.id.playerPlayPauseButton)
        sleepTimerIcon = findViewById(R.id.playerSleepTimerIcon)
        sleepTimerLabel = findViewById(R.id.playerSleepTimerLabel)
        seekBar = findViewById(R.id.playerSeekBar)
        currentTimeView = findViewById(R.id.playerCurrentTime)
        totalTimeView = findViewById(R.id.playerTotalTime)
        loadingSpinner = findViewById(R.id.playerLoadingSpinner)

        val path = intent.getStringExtra(EXTRA_FILE_PATH)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Video"
        findViewById<TextView>(R.id.playerTitle).text = title
        findViewById<TextView>(R.id.playerSubtitle).text = "Aus deiner Mediathek · offline verfügbar"

        if (path.isNullOrBlank() || !File(path).exists()) {
            Toast.makeText(this, "Datei nicht gefunden", Toast.LENGTH_LONG).show()
            finish()
            return
        }

        loadingSpinner.visibility = View.VISIBLE
        videoView.setVideoURI(Uri.fromFile(File(path)))
        videoView.setOnPreparedListener { mp ->
            loadingSpinner.visibility = View.GONE
            seekBar.max = mp.duration
            totalTimeView.text = formatTime(mp.duration)
            mp.isLooping = false
            videoView.start()
            updatePlayPauseIcon()
            scheduleAutoHide()
        }
        videoView.setOnCompletionListener {
            updatePlayPauseIcon()
            setOverlayVisible(true)
            if (pauseAfterCurrentVideo) {
                pauseAfterCurrentVideo = false
                clearSleepTimerUi()
            }
        }
        videoView.setOnErrorListener { _, _, _ ->
            loadingSpinner.visibility = View.GONE
            Toast.makeText(this, "Wiedergabe fehlgeschlagen", Toast.LENGTH_LONG).show()
            true
        }

        findViewById<ImageButton>(R.id.playerBackButton).setOnClickListener { finish() }

        playPauseButton.setOnClickListener {
            if (videoView.isPlaying) videoView.pause() else videoView.start()
            updatePlayPauseIcon()
            scheduleAutoHide()
        }

        tapCatcher.setOnClickListener { setOverlayVisible(!overlayVisible) }

        sleepTimerIcon.setOnClickListener { showSleepTimerMenu(sleepTimerIcon) }
        sleepTimerLabel.setOnClickListener { showSleepTimerMenu(sleepTimerLabel) }

        seekBar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(sb: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) currentTimeView.text = formatTime(progress)
            }
            override fun onStartTrackingTouch(sb: SeekBar?) { userIsSeeking = true }
            override fun onStopTrackingTouch(sb: SeekBar?) {
                userIsSeeking = false
                videoView.seekTo(sb?.progress ?: 0)
            }
        })

        handler.post(progressTicker)
    }

    private fun setOverlayVisible(visible: Boolean) {
        overlayVisible = visible
        overlay.visibility = if (visible) View.VISIBLE else View.GONE
        handler.removeCallbacks(autoHideOverlay)
        if (visible) scheduleAutoHide()
    }

    private fun scheduleAutoHide() {
        handler.removeCallbacks(autoHideOverlay)
        handler.postDelayed(autoHideOverlay, 3000)
    }

    private fun updatePlayPauseIcon() {
        playPauseButton.setImageResource(
            if (videoView.isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        )
    }

    private fun showSleepTimerMenu(anchor: View) {
        val menu = PopupMenu(this, anchor)
        menu.menu.add(0, 1, 0, "15 Minuten")
        menu.menu.add(0, 2, 1, "30 Minuten")
        menu.menu.add(0, 3, 2, "45 Minuten")
        menu.menu.add(0, 4, 3, "1 Stunde")
        menu.menu.add(0, 5, 4, "Nach diesem Video")
        if (sleepTimer != null || pauseAfterCurrentVideo) {
            menu.menu.add(0, 6, 5, "Timer ausschalten")
        }
        menu.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                1 -> startSleepTimer(15)
                2 -> startSleepTimer(30)
                3 -> startSleepTimer(45)
                4 -> startSleepTimer(60)
                5 -> {
                    cancelSleepTimer()
                    pauseAfterCurrentVideo = true
                    sleepTimerIcon.visibility = View.GONE
                    sleepTimerLabel.visibility = View.VISIBLE
                    sleepTimerLabel.text = "Nach Video"
                }
                6 -> {
                    cancelSleepTimer()
                    pauseAfterCurrentVideo = false
                    clearSleepTimerUi()
                }
            }
            true
        }
        menu.show()
    }

    private fun startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        pauseAfterCurrentVideo = false
        sleepTimerIcon.visibility = View.GONE
        sleepTimerLabel.visibility = View.VISIBLE
        val totalMillis = minutes * 60_000L
        sleepTimer = object : CountDownTimer(totalMillis, 1000L) {
            override fun onTick(millisUntilFinished: Long) {
                val totalSeconds = (millisUntilFinished / 1000L).toInt()
                sleepTimerLabel.text = String.format(Locale.GERMANY, "%d:%02d", totalSeconds / 60, totalSeconds % 60)
            }
            override fun onFinish() {
                // Sleep timer only pauses playback — like on YouTube, it never closes
                // the player or the app itself.
                if (videoView.isPlaying) {
                    videoView.pause()
                    updatePlayPauseIcon()
                    setOverlayVisible(true)
                }
                clearSleepTimerUi()
            }
        }.start()
    }

    private fun cancelSleepTimer() {
        sleepTimer?.cancel()
        sleepTimer = null
    }

    private fun clearSleepTimerUi() {
        sleepTimerIcon.visibility = View.VISIBLE
        sleepTimerLabel.visibility = View.GONE
    }

    private fun formatTime(ms: Int): String {
        val totalSeconds = ms / 1000
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return String.format(Locale.GERMANY, "%d:%02d", minutes, seconds)
    }

    override fun onPause() {
        super.onPause()
        if (videoView.isPlaying) videoView.pause()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        cancelSleepTimer()
        videoView.stopPlayback()
        super.onDestroy()
    }

    companion object {
        const val EXTRA_FILE_PATH = "file_path"
        const val EXTRA_TITLE = "title"
    }
}
