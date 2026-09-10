import 'dart:convert';

class MediaCapture {
  final String url;
  final String source;
  final String pageUrl;
  final String referrer;
  final String userAgent;
  final Map<String, String> headers;
  final String cookies;
  final String mimeType;

  const MediaCapture({
    required this.url,
    this.source = 'NETWORK',
    this.pageUrl = '',
    this.referrer = '',
    this.userAgent = '',
    this.headers = const {},
    this.cookies = '',
    this.mimeType = '',
  });

  factory MediaCapture.fromJson(Map<String, dynamic> json) => MediaCapture(
        url: '${json['url'] ?? ''}',
        source: '${json['source'] ?? 'NETWORK'}',
        pageUrl: '${json['pageUrl'] ?? ''}',
        referrer: '${json['referrer'] ?? ''}',
        userAgent: '${json['userAgent'] ?? ''}',
        cookies: '${json['cookies'] ?? ''}',
        mimeType: '${json['mimeType'] ?? ''}',
        headers: (json['headers'] as Map?)?.map(
              (k, v) => MapEntry('$k', '$v'),
            ) ??
            const {},
      );
}

/// In-page media telemetry. It complements, rather than pretends to replace,
/// Chromium's native Network domain: webview_flutter 4.x does not expose a
/// public per-resource interception callback. The script therefore observes
/// fetch/XHR, media elements, performance resources, player configuration and
/// same-origin iframes. A future native Chromium adapter can feed the exact
/// same MediaCapture schema without changing the harvester UI.
class NetworkSniffer {
  NetworkSniffer._();

  static const String injectionScript = r'''
(function() {
  if (window.__nexusHarvesterInstalled) return;
  window.__nexusHarvesterInstalled = true;
  window.__nexusMedia = window.__nexusMedia || [];
  var list = window.__nexusMedia;
  var MAX = 1200;
  var mediaRe = /\.(m3u8|mpd|mp4|m4v|webm|mov|m4s|ts|ogv|3gp)(?:[?#]|$)/i;
  var pathRe = /\/(hls|dash|manifest|playlist|master|segment|stream|media)(?:[/?#]|$)/i;
  var mimeRe = /^(video\/|application\/(?:vnd\.apple\.mpegurl|x-mpegurl|dash\+xml))/i;

  function abs(url) {
    try { return new URL(String(url), location.href).href; } catch(e) { return ''; }
  }
  function likely(url, mime) {
    if (!url || /^data:|^javascript:/i.test(url)) return false;
    if (/^blob:/i.test(url)) return true;
    return mediaRe.test(url) || pathRe.test(url) || (mime && mimeRe.test(mime));
  }
  function contextHeaders(h) {
    var out = {};
    try {
      if (!h) return out;
      if (h instanceof Headers) h.forEach(function(v,k){ out[k] = v; });
      else Object.keys(h).forEach(function(k){ out[k] = String(h[k]); });
    } catch(e) {}
    return out;
  }
  function record(url, source, extra) {
    try {
      url = abs(url);
      extra = extra || {};
      var mime = extra.mimeType || '';
      if (!likely(url, mime)) return;
      var item = {
        url: url,
        source: source || 'NETWORK',
        pageUrl: location.href,
        referrer: document.referrer || '',
        userAgent: navigator.userAgent || '',
        cookies: document.cookie || '',
        headers: extra.headers || {},
        mimeType: mime
      };
      var key = item.url + '|' + item.source;
      for (var i=0; i<list.length; i++) if (list[i].url + '|' + list[i].source === key) return;
      if (list.length >= MAX) list.shift();
      list.push(item);
    } catch(e) {}
  }

  var oldFetch = window.fetch;
  if (oldFetch) window.fetch = function(input, init) {
    try {
      var url = typeof input === 'string' ? input : (input && input.url);
      var headers = contextHeaders(init && init.headers);
      record(url, 'FETCH', {headers: headers});
    } catch(e) {}
    var p = oldFetch.apply(this, arguments);
    try { p.then(function(res){ if (res && res.url) record(res.url, 'FETCH_RESPONSE', {mimeType: res.headers && res.headers.get('content-type') || ''}); }); } catch(e) {}
    return p;
  };

  var oldOpen = XMLHttpRequest.prototype.open;
  var oldSend = XMLHttpRequest.prototype.send;
  var oldSet = XMLHttpRequest.prototype.setRequestHeader;
  XMLHttpRequest.prototype.open = function(method, url) {
    try { this.__nexusUrl = url; this.__nexusHeaders = {}; } catch(e) {}
    return oldOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.setRequestHeader = function(k,v) {
    try { this.__nexusHeaders = this.__nexusHeaders || {}; this.__nexusHeaders[k] = v; } catch(e) {}
    return oldSet.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function() {
    try { record(this.__nexusUrl, 'XHR', {headers: this.__nexusHeaders || {}}); } catch(e) {}
    return oldSend.apply(this, arguments);
  };

  function scanVideo(root) {
    try {
      (root.querySelectorAll ? root.querySelectorAll('video, audio, source') : []).forEach(function(el){
        record(el.currentSrc || el.src || el.getAttribute('src') || el.getAttribute('data-src'), 'DOM_MEDIA', {mimeType: el.getAttribute('type') || ''});
      });
    } catch(e) {}
  }
  function scanPlayers(root) {
    try {
      var scripts = root.querySelectorAll ? root.querySelectorAll('script') : [];
      scripts.forEach(function(s){
        var t = s.textContent || '';
        if (/hls\.js|video\.js|shaka|plyr|jwplayer|m3u8|\.mpd/i.test(t)) {
          var m, re = /https?:\\?\/\\?\/[^\s"'<>\\]+|(?:blob:)[^\s"'<>]+/gi;
          while ((m = re.exec(t))) record(m[0].replace(/\\\//g,'/'), 'PLAYER_CONFIG');
        }
      });
      ['__INITIAL_STATE__','__NEXT_DATA__','__NUXT__'].forEach(function(k){
        try { var v = window[k]; if (v) scanObject(v, 'PLAYER_CONFIG'); } catch(e) {}
      });
    } catch(e) {}
  }
  function scanObject(obj, source, seen) {
    seen = seen || [];
    if (!obj || seen.indexOf(obj) >= 0 || seen.length > 100) return;
    if (typeof obj === 'string') { if (/^(https?:|blob:)/i.test(obj)) record(obj, source); return; }
    if (typeof obj !== 'object') return;
    seen.push(obj);
    try { Object.keys(obj).slice(0,300).forEach(function(k){ scanObject(obj[k], source, seen); }); } catch(e) {}
  }
  function scanPerformance() {
    try { performance.getEntriesByType('resource').forEach(function(e){ record(e.name, 'PERFORMANCE', {mimeType: e.initiatorType === 'video' ? 'video/*' : ''}); }); } catch(e) {}
  }
  function scanFrames() {
    try {
      document.querySelectorAll('iframe').forEach(function(frame){
        try {
          var d = frame.contentDocument;
          if (d) { scanVideo(d); scanPlayers(d); }
        } catch(e) { /* cross-origin: native/network layer must handle it */ }
      });
    } catch(e) {}
  }
  function scanAll() { scanVideo(document); scanPlayers(document); scanPerformance(); scanFrames(); }

  document.addEventListener('play', function(e){
    try { var t=e.target; record(t.currentSrc || t.src, 'MEDIA_PLAY', {mimeType:t.currentSrc ? 'video/*' : ''}); } catch(e) {}
  }, true);
  document.addEventListener('loadedmetadata', function(e){
    try { var t=e.target; record(t.currentSrc || t.src, 'MEDIA_METADATA', {mimeType:'video/*'}); } catch(e) {}
  }, true);
  new MutationObserver(function(){ scanAll(); }).observe(document.documentElement || document, {subtree:true, childList:true, attributes:true, attributeFilter:['src','srcset','data-src','data-url','data-video','data-file']});
  scanAll();
})();
''';

  /// Starts a bounded discovery pass in the currently rendered document.
  /// It intentionally does not bypass the same-origin policy.
  static const String discoveryScript = r'''
(function(){
  if (window.__nexusDiscoveryRunning) return;
  window.__nexusDiscoveryRunning = true;
  var steps = 0;
  var timer = setInterval(function(){
    try {
      window.scrollBy(0, Math.max(300, window.innerHeight * 0.75));
      document.querySelectorAll('button,[role=\"button\"],video').forEach(function(el){
        var text=((el.innerText||el.getAttribute('aria-label')||el.title||'')+'').toLowerCase();
        if (el.tagName.toLowerCase()==='video' || /^(play|watch|play video)/.test(text)) {
          try { if (el.tagName.toLowerCase()==='video') el.play().catch(function(){}); else el.click(); } catch(e) {}
        }
      });
      if (window.__nexusHarvesterInstalled) {
        document.querySelectorAll('video,source').forEach(function(el){
          var u=el.currentSrc||el.src||el.getAttribute('data-src');
          if (u) { try { var x=new URL(u,location.href).href; if (window.__nexusMedia && window.__nexusMedia.length<1200) window.__nexusMedia.push({url:x,source:'DISCOVERY',pageUrl:location.href,referrer:document.referrer||'',userAgent:navigator.userAgent||'',cookies:document.cookie||'',headers:{},mimeType:el.getAttribute('type')||''}); } catch(e){} }
        });
      }
      steps++;
      if (steps>=12) { clearInterval(timer); window.__nexusDiscoveryRunning=false; window.scrollTo(0,0); }
    } catch(e) { clearInterval(timer); window.__nexusDiscoveryRunning=false; }
  }, 650);
})();
''';

  /// Snapshot der für die Video-Erkennung relevanten Tags — nur
  /// `<video>`, `<iframe>` und `<script>`-Blöcke, deren Inhalt nach einem
  /// Player aussieht ("player"/"video"/"hls"/"m3u8" im Text). Für die
  /// Fehlersuche: zeigt genau, was der Harvester im DOM tatsächlich vorfindet,
  /// ohne die komplette (oft riesige) Seite zu dumpen.
  static const String domSnapshotScript = r'''
(function(){
  function attrs(el){
    var out={};
    for (var i=0;i<el.attributes.length;i++){ var a=el.attributes[i]; out[a.name]=a.value; }
    return out;
  }
  var result=[];
  document.querySelectorAll('video').forEach(function(el){
    result.push({tag:'video', attrs:attrs(el), currentSrc: el.currentSrc||''});
  });
  document.querySelectorAll('iframe').forEach(function(el){
    result.push({tag:'iframe', attrs:attrs(el)});
  });
  document.querySelectorAll('script').forEach(function(el){
    var t = el.textContent || '';
    if (/player|video|hls|m3u8|\.mpd/i.test(t)) {
      result.push({tag:'script', src: el.src||'', preview: t.substring(0,300)});
    }
  });
  return JSON.stringify(result);
})();
''';

  static List<Map<String, dynamic>> parseDomSnapshot(Object raw) {
    try {
      dynamic decoded = jsonDecode(raw.toString());
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is List) {
        return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return const [];
  }

  static List<MediaCapture> parseCaptures(Object raw) {
    try {
      dynamic decoded = jsonDecode(raw.toString());
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => MediaCapture.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.url.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  static List<String> parseResult(Object raw) =>
      parseCaptures(raw).map((e) => e.url).toSet().toList();
}
