import 'package:flutter/services.dart';

/// Trie-Knoten für Domain-Matching. Bewusst als eigene Klasse (nicht als
/// Map<String, dynamic>), damit es keine Typkonflikte gibt.
class _TrieNode {
  final Map<String, _TrieNode> children = {};
  bool isEnd = false;
}

/// AdBlockEngine: Domain-Trie + Substring-Pattern-Matching.
/// WICHTIG: initialize() MUSS vor der ersten Nutzung aufgerufen werden
/// (siehe main.dart) — vorher blockt isBlocked() nichts.
class AdBlockEngine {
  static final AdBlockEngine _instance = AdBlockEngine._internal();
  factory AdBlockEngine() => _instance;
  AdBlockEngine._internal();

  final _TrieNode _root = _TrieNode();
  final List<String> _substringPatterns = [];
  final Set<String> _whitelistedHosts = {};
  bool _initialized = false;
  bool enabled = true;
  int _ruleCount = 0;

  bool get isInitialized => _initialized;
  int get ruleCount => _ruleCount;

  /// Eingebettete Basis-Filterliste (greift sofort, auch ohne Asset-Datei).
  static const List<String> _builtInRules = [
    '||doubleclick.net^',
    '||googlesyndication.com^',
    '||googletagmanager.com^',
    '||google-analytics.com^',
    '||analytics.google.com^',
    '||adservice.google.com^',
    '||pagead2.googlesyndication.com^',
    '||googleadservices.com^',
    '||facebook.com/tr^',
    '||connect.facebook.net^',
    '||ads.yahoo.com^',
    '||ads.rubiconproject.com^',
    '||ads.twitter.com^',
    '||amazon-adsystem.com^',
    '||scorecardresearch.com^',
    '||taboola.com^',
    '||outbrain.com^',
    '||criteo.com^',
    '||adnxs.com^',
    '||pubmatic.com^',
    '||openx.net^',
    '||moatads.com^',
    '||adform.net^',
    '||bidswitch.net^',
    '||smartadserver.com^',
    '||media.net^',
    '||propellerads.com^',
    '||popads.net^',
    '||adcolony.com^',
    '||exoclick.com^',
    '||juicyads.com^',
    '||trafficjunky.net^',
    '||yieldmo.com^',
    '||sharethrough.com^',
    '||quantserve.com^',
    '||hotjar.com^',
  ];

  /// Lädt eingebettete Regeln + optional eine Filterdatei aus den Assets.
  Future<void> initialize({String? assetPath}) async {
    if (_initialized) return;
    for (final rule in _builtInRules) {
      _addRule(rule);
    }
    if (assetPath != null) {
      try {
        final content = await rootBundle.loadString(assetPath);
        loadCustomList(content);
      } catch (_) {
        // Asset fehlt oder ist leer — eingebaute Regeln reichen als Fallback.
      }
    }
    _initialized = true;
  }

  void loadCustomList(String content) {
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('!') || trimmed.startsWith('#')) {
        continue;
      }
      _addRule(trimmed);
    }
  }

  void _addRule(String rule) {
    if (rule.startsWith('||')) {
      var domain = rule.substring(2);
      if (domain.endsWith('^')) domain = domain.substring(0, domain.length - 1);
      // Pfad-Anteil abtrennen, falls vorhanden (||example.com/ads^)
      final slashIdx = domain.indexOf('/');
      if (slashIdx >= 0) domain = domain.substring(0, slashIdx);
      if (domain.isEmpty) return;
      _addDomainToTrie(domain);
      _ruleCount++;
    } else if (rule.startsWith('@@')) {
      // Whitelist-Regel (Ausnahme) — vereinfachtes Handling: Host merken.
      final host = rule.replaceFirst('@@', '').replaceAll('||', '').replaceAll('^', '');
      if (host.isNotEmpty) _whitelistedHosts.add(host);
    } else if (rule.contains('*') || rule.length > 3) {
      _substringPatterns.add(rule.toLowerCase());
      _ruleCount++;
    }
  }

  void _addDomainToTrie(String domain) {
    final parts = domain.toLowerCase().split('.').reversed.toList();
    var node = _root;
    for (final part in parts) {
      node = node.children.putIfAbsent(part, () => _TrieNode());
    }
    node.isEnd = true;
  }

  /// Prüft, ob eine Domain (oder eine ihrer Eltern-Domains) im Trie geblockt ist.
  bool _domainBlocked(String host) {
    final parts = host.toLowerCase().split('.').reversed.toList();
    var node = _root;
    for (final part in parts) {
      final next = node.children[part];
      if (next == null) return false;
      node = next;
      if (node.isEnd) return true; // Prefix-Match reicht (Subdomains mitblocken)
    }
    return false;
  }

  bool isBlocked(String url, {String resourceType = 'other'}) {
    if (!_initialized || !enabled) return false;
    final host = _extractHost(url);
    if (host.isEmpty) return false;
    if (_whitelistedHosts.any((w) => host.endsWith(w))) return false;

    if (_domainBlocked(host)) return true;

    final lower = url.toLowerCase();
    for (final pattern in _substringPatterns) {
      final cleaned = pattern.replaceAll('*', '');
      if (cleaned.isNotEmpty && lower.contains(cleaned)) return true;
    }
    return false;
  }

  String _extractHost(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return '';
    }
  }

  void toggle() => enabled = !enabled;
}
