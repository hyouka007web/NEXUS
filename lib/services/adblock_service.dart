import 'dart:convert';
import 'package:flutter/services.dart';

/// Adblock-Service: Lädt Filterlisten und prüft URLs
class AdblockService {
  static final AdblockService _instance = AdblockService._internal();
  factory AdblockService() => _instance;
  AdblockService._internal();

  bool _enabled = true;
  final Set<String> _blockedPatterns = {};

  bool get enabled => _enabled;

  /// Filterung ein-/ausschalten
  void toggle() {
    _enabled = !_enabled;
  }

  /// Filterlisten laden
  Future<void> loadFilters() async {
    try {
      final manifest = await rootBundle.loadString('assets/filters/easylist_sample.txt');
      for (final line in LineSplitter().convert(manifest)) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty && !trimmed.startsWith('!')) {
          _blockedPatterns.add(trimmed);
        }
      }
    } catch (e) {
      // Fallback: Standard-Filter manuell hinzufügen
      _loadDefaultFilters();
    }
  }

  /// Standard-Filter (wenn Asset-Ladung fehlschlägt)
  void _loadDefaultFilters() {
    const defaults = [
      '||doubleclick.net^',
      '||googlesyndication.com^',
      '||googletagmanager.com^',
      '||facebook.com^',
      '||analytics.google.com^',
      '||googletagmanager.com^',
      '||pagead2.googlesyndication.com^',
      '||googleadservices.com^',
      '||ads.yahoo.com^',
      '||ads.rubiconproject.com^',
    ];
    _blockedPatterns.addAll(defaults);
  }

  /// Prüfen ob eine URL geblockt werden soll
  bool isBlocked(String url) {
    if (!_enabled) return false;

    for (final pattern in _blockedPatterns) {
      if (_urlMatchesPattern(url, pattern)) {
        return true;
      }
    }
    return false;
  }

  /// Einfache Pattern-Matching für Adblock-Regeln
  bool _urlMatchesPattern(String url, String pattern) {
    if (pattern.startsWith('||')) {
      // Domain-basiert: ||example.com^
      final domain = pattern.substring(2);
      final endChar = domain.endsWith('^') ? domain.length - 1 : domain.length;
      final domainPart = domain.substring(0, endChar);

      if (url.contains(domainPart)) {
        return true;
      }
    }
    return false;
  }

  /// Alle geblockten Patterns zurückgeben (für Logging)
  List<String> get blockedPatterns => _blockedPatterns.toList();
}
