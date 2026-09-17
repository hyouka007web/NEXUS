import 'package:shared_preferences/shared_preferences.dart';

/// Speichert die zuletzt abgespielte Position je Datei (Master-Prompt
/// Kapitel 26: "Resume from 42:17?"). Schlüssel ist der lokale Dateipfad.
class PlaybackPositionStore {
  static String _keyFor(String path) => 'nexus_playback_pos_$path';

  static Future<void> save(String path, Duration position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyFor(path), position.inMilliseconds);
    } catch (_) {}
  }

  static Future<Duration?> load(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_keyFor(path));
      if (ms == null) return null;
      return Duration(milliseconds: ms);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyFor(path));
    } catch (_) {}
  }
}
