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
    private val onAllowedPopup: (uri: String) -> GeckoSession?,
    private val onContentGone: (session: GeckoSession, wasCrash: Boolean) -> Unit
) : GeckoSession.NavigationDelegate, GeckoSession.ContentDelegate, GeckoSession.ProgressDelegate {

    enum class BlockReason { AD_HOST, POPUP_NO_GESTURE, REDIRECT_NO_GESTURE }

    /**
     * Set to true right before the app itself triggers a navigation (address bar,
     * start page search, sidebar back/forward/home — anything that isn't a click
     * inside the page). GeckoView reports hasUserGesture=false for these, since
     * there is no touch event inside the WebView content, so without this flag
     * the redirect heuristic below would treat the user's own deliberate navigation
     * as a suspicious auto-redirect and silently swallow it. Consumed (reset to
     * false) by the very next onLoadRequest.
     */
    @Volatile var pendingAppNavigation: Boolean = false

    private var currentDomain: String? = null
    private var lastGestureAt = 0L

    /** True between onPageStart and onPageStop. Sites like Google routinely chain
     *  several server/JS redirects (consent, region, https-upgrade) as part of a
     *  single navigation *before* the page has finished loading — that's normal
     *  and must not be blocked. The dangerous pattern this shield targets is a
     *  redirect fired by page JS *after* the page has already settled (classic
     *  malvertising "wait a few seconds, then bounce the user away"). Gating on
     *  isLoading instead of a fixed time window tells these two cases apart
     *  reliably, instead of guessing via an arbitrary millisecond cutoff. */
    @Volatile private var isLoading = false

    override fun onLocationChange(
        session: GeckoSession,
        url: String?,
        perms: MutableList<GeckoSession.PermissionDelegate.ContentPermission>,
        hasUserGesture: Boolean
    ) {
        currentDomain = url?.let { Uri.parse(it).host?.lowercase() }
        if (hasUserGesture) lastGestureAt = SystemClock.elapsedRealtime()
    }

    override fun onPageStart(session: GeckoSession, url: String) {
        isLoading = true
        onLoadingStateChange(true)
    }

    override fun onPageStop(session: GeckoSession, success: Boolean) {
        isLoading = false
        onLoadingStateChange(false)
    }

    override fun onLoadRequest(
        session: GeckoSession,
        request: GeckoSession.NavigationDelegate.LoadRequest
    ): GeckoResult<AllowOrDeny> {
        if (request.hasUserGesture) lastGestureAt = SystemClock.elapsedRealtime()
        val uri = Uri.parse(request.uri)
        val isAppNavigation = pendingAppNavigation
        if (isAppNavigation) pendingAppNavigation = false

        if (adBlockEngine.shouldBlock(uri, request.triggerUri?.let { Uri.parse(it).host } ?: currentDomain)) {
            onBlocked(request.uri, BlockReason.AD_HOST)
            return GeckoResult.deny()
        }

        val host = uri.host?.lowercase()
        val crossDomain = currentDomain != null && host != null && host != currentDomain
        if (!isAppNavigation && !request.hasUserGesture && crossDomain && !isLoading) {
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

    /** The Gecko content (renderer) process crashed outright — usually a native
     *  crash inside the engine itself. The GeckoSession object survives on the
     *  Java side, but its surface stays permanently blank/black until reloaded;
     *  nothing did that automatically before, which is why a crashed tab looked
     *  "dead" forever while a *new* tab (fresh content process) worked fine. */
    override fun onCrash(session: GeckoSession) {
        isLoading = false
        onLoadingStateChange(false)
        onContentGone(session, true)
    }

    /** The content process was killed by the system (typically the low-memory/
     *  OOM killer under memory pressure — common on devices with little RAM,
     *  e.g. right after opening a heavy page or a second activity like the
     *  Video Harvester). Same fix as onCrash: reload instead of staying blank. */
    override fun onKill(session: GeckoSession) {
        isLoading = false
        onLoadingStateChange(false)
        onContentGone(session, false)
    }

    override fun onLoadError(
        session: GeckoSession,
        uri: String?,
        error: WebRequestError
    ): GeckoResult<String> = GeckoResult.fromValue(NexusErrorPage.build(uri, error))
}
