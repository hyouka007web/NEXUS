import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// AdBlockEngine: Trie-basierter Domain-Matcher für effizientes Blockieren.
/// Nutzt Bloom-Filter-ähnliche Struktur für Performance.
class AdBlockEngine {
  static final AdBlockEngine _instance = AdBlockEngine._internal();
  factory AdBlockEngine() => _instance;
  AdBlockEngine._internal();

  final Set<String> _blockedDomains = {};
  final Set<String> _blockedPatterns = {};
  final Map<String, List<String>> _domainTrie = {};
  bool _initialized = false;

  /// Initialisiert den Engine mit Filterlisten.
  Future<void> initialize() async {
    if (_initialized) return;

    // EasyList + EasyPrivacy als Embedded-Filter
    const easyListData = '''
||googleadservices.com^
||doubleclick.net^
||googlesyndication.com^
||facebook.com^
||ads.twitter.com^
||googletagmanager.com^
||analytics.google.com^
||stats.g.doubleclick.net^
||adservice.google.com^
||pagead2.googlesyndication.com^
''';

    for (final line in easyListData.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && !trimmed.startsWith('!')) {
        _addRule(trimmed);
      }
    }

    _initialized = true;
  }

  /// Fügt eine Filterregel hinzu.
  void _addRule(String rule) {
    if (rule.startsWith('||')) {
      final domain = rule.substring(2).split('^')[0];
      _blockedDomains.add(domain);
      _addToTrie(domain);
    } else if (rule.contains('*')) {
      _blockedPatterns.add(rule);
    }
  }

  /// Trie-basierte Domain-Einfügung.
  void _addToTrie(String domain) {
    final parts = domain.split('.').reversed.toList();
    var node = _domainTrie;
    for (final part in parts) {
      if (!node.containsKey(part)) {
        node[part] = {};
      }
      node = node[part] as Map<String, dynamic>;
    }
    node['_end'] = true;
  }

  /// Prüft ob eine URL geblockt wird (O(k) Trie-Lookup).
  bool isBlocked(String url) {
    if (!_initialized) return false;
    final host = _extractHost(url);
    if (_blockedDomains.contains(host)) return true;

    // Trie-basierte Suche
    final parts = host.split('.').reversed.toList();
    var node = _domainTrie;
    for (final part in parts) {
      if (!node.containsKey(part)) {
        break;
      }
      node = node[part] as Map<String, dynamic>;
      if (node.containsKey('_end')) return true;
    }
    return false;
  }

  /// Extrahiert Host aus URL.
  String _extractHost(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (e) {
      return '';
    }
  }

  /// Lädt benutzerdefinierte Filterliste aus Datei.
  Future<void> loadCustomList(String content) async {
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && !trimmed.startsWith('!')) {
        _addRule(trimmed);
      }
    }
  }
}
