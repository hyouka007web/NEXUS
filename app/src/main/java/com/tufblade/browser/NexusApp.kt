package com.tufblade.browser

import android.app.Application
import android.util.Log
import org.mozilla.geckoview.ContentBlocking
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.GeckoRuntimeSettings

const val LAST_CRASH_FILE_NAME = "last_crash.txt"

class NexusApp : Application() {
    lateinit var geckoRuntime: GeckoRuntime
        private set

    override fun onCreate() {
        super.onCreate()

        val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            runCatching {
                filesDir.resolve(LAST_CRASH_FILE_NAME).writeText(Log.getStackTraceString(throwable))
            }
            previousHandler?.uncaughtException(thread, throwable)
        }

        val blocking = ContentBlocking.Settings.Builder()
            .antiTracking(ContentBlocking.AntiTracking.STRICT)
            .safeBrowsing(ContentBlocking.SafeBrowsing.DEFAULT)
            .cookieBehavior(ContentBlocking.CookieBehavior.ACCEPT_NON_TRACKERS)
            .build()

        val settings = GeckoRuntimeSettings.Builder()
            .contentBlocking(blocking)
            .build()

        geckoRuntime = GeckoRuntime.create(this, settings)
    }
}
