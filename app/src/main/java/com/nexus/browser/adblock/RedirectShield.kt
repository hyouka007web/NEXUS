package com.nexus.browser.adblock

import android.net.Uri
import android.os.SystemClock
import android.util.Log
import org.mozilla.geckoview.AllowOrDeny
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.WebRequestError

class RedirectShield(
    private val adBlockEngine: AdBlockEngine,
    private val onBlocked: (uri: String, reason: BlockReason) -> Unit,
    private val onTitleUpdate: (session: GeckoSession, title: String?) -> Unit,
    private val onLoadingStateChange: (loading: Boolean) -> Unit,
    private val onAllowedPopup: (uri: String) -> GeckoSession?
) : GeckoSession.NavigationDelegate, GeckoSession.ContentDelegate, GeckoSession.ProgressDelegate {

    enum class BlockReason { AD_HOST, POPUP_NO_GESTURE, REDIRECT_NO_GESTURE }

    private var currentDomain: String? = null
    private var lastLoadAt = 0L
    private var lastGestureAt = 0L

    override fun onLocationChange(
        session: GeckoSession,
        url: String?,
        perms: MutableList<GeckoSession.PermissionDelegate.ContentPermission>,
        hasUserGesture: Boolean
    ) {
        currentDomain = url?.let { Uri.parse(it).host?.lowercase() }
        lastLoadAt = SystemClock.elapsedRealtime()
        if (hasUserGesture) lastGestureAt = SystemClock.elapsedRealtime()
    }

    override fun onPageStart(session: GeckoSession, url: String) = onLoadingStateChange(true)
    override fun onPageStop(session: GeckoSession, success: Boolean) = onLoadingStateChange(false)

    override fun onLoadRequest(
        session: GeckoSession,
        request: GeckoSession.NavigationDelegate.LoadRequest
    ): GeckoResult<AllowOrDeny> {
        if (request.hasUserGesture) lastGestureAt = SystemClock.elapsedRealtime()
        val uri = Uri.parse(request.uri)

        if (adBlockEngine.shouldBlock(uri, request.triggerUri?.let { Uri.parse(it).host } ?: currentDomain)) {
            onBlocked(request.uri, BlockReason.AD_HOST)
            return GeckoResult.deny()
        }

        val host = uri.host?.lowercase()
        val crossDomain = currentDomain != null && host != null && host != currentDomain
        val fastRedirect = SystemClock.elapsedRealtime() - lastLoadAt < 4000L
        if (!request.hasUserGesture && crossDomain && fastRedirect) {
            Log.i("NEXUS", "Blocked redirect: ${request.uri}")
            onBlocked(request.uri, BlockReason.REDIRECT_NO_GESTURE)
            return GeckoResult.deny()
        }
        return GeckoResult.allow()
    }

    override fun onSubframeLoadRequest(
        session: GeckoSession,
        request: GeckoSession.NavigationDelegate.LoadRequest
    ): GeckoResult<AllowOrDeny> {
        val uri = Uri.parse(request.uri)
        if (adBlockEngine.shouldBlock(uri, request.triggerUri?.let { Uri.parse(it).host } ?: currentDomain)) {
            onBlocked(request.uri, BlockReason.AD_HOST)
            return GeckoResult.deny()
        }
        return GeckoResult.allow()
    }

    override fun onNewSession(session: GeckoSession, uri: String): GeckoResult<GeckoSession>? {
        val recentGesture = SystemClock.elapsedRealtime() - lastGestureAt < 1500L
        val scheme = runCatching { Uri.parse(uri).scheme?.lowercase() }.getOrNull()
        if (scheme !in listOf("http", "https")) {
            onBlocked(uri, BlockReason.POPUP_NO_GESTURE)
            return null
        }
        if (recentGesture) {
            val popup = onAllowedPopup(uri)
            if (popup != null) return GeckoResult.fromValue(popup)
        }
        onBlocked(uri, BlockReason.POPUP_NO_GESTURE)
        return null
    }

    override fun onTitleChange(session: GeckoSession, title: String?) {
        onTitleUpdate(session, title)
    }

    override fun onLoadError(
        session: GeckoSession,
        uri: String?,
        error: WebRequestError
    ): GeckoResult<String> = GeckoResult.fromValue(NexusErrorPage.build(uri, error))
}
