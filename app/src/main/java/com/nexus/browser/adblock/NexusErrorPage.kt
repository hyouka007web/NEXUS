package com.nexus.browser.adblock

import android.util.Base64
import org.mozilla.geckoview.WebRequestError

/** Builds a small dark-themed data: URI error page shown when a page fails to load. */
object NexusErrorPage {

    fun build(uri: String?, error: WebRequestError): String {
        val (title, message) = describe(error)
        val safeUri = (uri ?: "").replace("&", "&amp;").replace("\"", "&quot;").replace("<", "&lt;")
        val html = """
            <!DOCTYPE html>
            <html><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                body { background:#1E1E1E; color:#FFFFFF; font-family:sans-serif;
                       display:flex; flex-direction:column; align-items:center; justify-content:center;
                       height:100vh; margin:0; padding:24px; box-sizing:border-box; text-align:center; }
                h1 { color:#FF3B3B; font-size:20px; margin-bottom:8px; }
                p { color:#A0A0A0; font-size:14px; max-width:320px; word-break:break-all; }
                .actions { margin-top:24px; display:flex; gap:12px; }
                a { color:#1E1E1E; background:#FFB800; text-decoration:none; font-weight:bold;
                    padding:10px 20px; border-radius:6px; font-size:13px; }
                a.secondary { background:transparent; color:#FFB800; border:1px solid #3F4245; }
            </style></head>
            <body>
                <h1>$title</h1>
                <p>$message</p>
                <p style="font-size:11px;opacity:0.6;">$safeUri</p>
                <div class="actions">
                    <a href="$safeUri">ERNEUT VERSUCHEN</a>
                    <a class="secondary" href="https://start.duckduckgo.com">STARTSEITE</a>
                </div>
            </body></html>
        """.trimIndent()
        val encoded = Base64.encodeToString(html.toByteArray(Charsets.UTF_8), Base64.NO_PADDING or Base64.NO_WRAP)
        return "data:text/html;base64,$encoded"
    }

    private fun describe(error: WebRequestError): Pair<String, String> = when (error.category) {
        WebRequestError.ERROR_CATEGORY_NETWORK -> "KEINE VERBINDUNG" to
            "Die Seite konnte nicht erreicht werden. Prüfe deine Internetverbindung."
        WebRequestError.ERROR_CATEGORY_SECURITY -> "UNSICHERE VERBINDUNG" to
            "Das Sicherheitszertifikat dieser Seite konnte nicht geprüft werden. NEXUS hat den Ladevorgang gestoppt."
        WebRequestError.ERROR_CATEGORY_URI -> "UNGÜLTIGE ADRESSE" to
            "Diese Adresse ist ungültig oder wird nicht unterstützt."
        WebRequestError.ERROR_CATEGORY_CONTENT -> "INHALT NICHT VERFÜGBAR" to
            "Der Inhalt dieser Seite konnte nicht dargestellt werden."
        else -> when (error.code) {
            WebRequestError.ERROR_CONNECTION_REFUSED -> "VERBINDUNG ABGELEHNT" to
                "Der Server hat die Verbindung abgelehnt."
            WebRequestError.ERROR_UNKNOWN_HOST -> "SERVER NICHT GEFUNDEN" to
                "Diese Domain konnte nicht aufgelöst werden. Prüfe die Schreibweise."
            WebRequestError.ERROR_NET_TIMEOUT -> "ZEITÜBERSCHREITUNG" to
                "Die Seite hat zu lange zum Antworten gebraucht."
            WebRequestError.ERROR_NET_RESET -> "VERBINDUNG UNTERBROCHEN" to
                "Die Verbindung wurde während des Ladens unterbrochen."
            WebRequestError.ERROR_OFFLINE -> "KEIN NETZWERK" to
                "Es besteht aktuell keine Internetverbindung."
            else -> "SEITE NICHT VERFÜGBAR" to
                "Beim Laden dieser Seite ist ein unerwarteter Fehler aufgetreten."
        }
    }
}
