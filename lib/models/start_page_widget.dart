import 'package:flutter/material.dart';

/// Die Arten von Start-Page-Widgets (Master-Prompt Kapitel 11).
/// Neue Typen können hier ergänzt werden, ohne das Grid-System
/// anzufassen (Downloads-/System-/Workspace-Widgets etc. später).
enum StartPageWidgetType { shortcut, webPanel, clock, note }

StartPageWidgetType _typeFromString(String s) {
  return StartPageWidgetType.values.firstWhere(
    (t) => t.name == s,
    orElse: () => StartPageWidgetType.shortcut,
  );
}

/// Kleine, JSON-fähige Icon-Auswahl für Shortcuts (IconData selbst lässt
/// sich nicht sauber (de-)serialisieren, daher ein fester Schlüssel-Satz).
const Map<String, IconData> startPageIconSet = {
  'web': Icons.public,
  'search': Icons.search,
  'video': Icons.smart_display_outlined,
  'tv': Icons.live_tv_outlined,
  'book': Icons.menu_book_outlined,
  'code': Icons.code_rounded,
  'news': Icons.newspaper_outlined,
  'mail': Icons.mail_outline,
  'social': Icons.forum_outlined,
  'shop': Icons.shopping_bag_outlined,
  'music': Icons.music_note_outlined,
  'cloud': Icons.cloud_outlined,
};

IconData iconForKey(String? key) => startPageIconSet[key] ?? Icons.public;

/// Ein einzelnes Widget auf der Start-Page. `colSpan`/`rowSpan` bestimmen
/// die Kachelgröße im Grid (1x1 = normale Kachel, 2x2 = großes Web-Panel).
class StartPageWidgetConfig {
  String id;
  StartPageWidgetType type;
  String title;
  String? url; // für shortcut + webPanel
  String? note; // für note
  String iconKey;
  int colSpan;
  int rowSpan;

  StartPageWidgetConfig({
    required this.id,
    required this.type,
    required this.title,
    this.url,
    this.note,
    this.iconKey = 'web',
    this.colSpan = 1,
    this.rowSpan = 1,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'url': url,
        'note': note,
        'iconKey': iconKey,
        'colSpan': colSpan,
        'rowSpan': rowSpan,
      };

  factory StartPageWidgetConfig.fromJson(Map<String, dynamic> json) => StartPageWidgetConfig(
        id: json['id'] as String,
        type: _typeFromString(json['type'] as String? ?? 'shortcut'),
        title: json['title'] as String? ?? '',
        url: json['url'] as String?,
        note: json['note'] as String?,
        iconKey: json['iconKey'] as String? ?? 'web',
        colSpan: json['colSpan'] as int? ?? 1,
        rowSpan: json['rowSpan'] as int? ?? 1,
      );
}

/// Standard-Kacheln für neu angelegte Workspaces.
List<StartPageWidgetConfig> defaultStartPageWidgets() => [
      StartPageWidgetConfig(id: 'sp_1', type: StartPageWidgetType.clock, title: 'Uhr', colSpan: 1, rowSpan: 1),
      StartPageWidgetConfig(id: 'sp_2', type: StartPageWidgetType.shortcut, title: 'DuckDuckGo', url: 'https://duckduckgo.com', iconKey: 'search'),
      StartPageWidgetConfig(id: 'sp_3', type: StartPageWidgetType.shortcut, title: 'YouTube', url: 'https://youtube.com', iconKey: 'video'),
      StartPageWidgetConfig(id: 'sp_4', type: StartPageWidgetType.shortcut, title: 'ARD Mediathek', url: 'https://www.ardmediathek.de', iconKey: 'tv'),
      StartPageWidgetConfig(id: 'sp_5', type: StartPageWidgetType.shortcut, title: 'GitHub', url: 'https://github.com', iconKey: 'code'),
      StartPageWidgetConfig(id: 'sp_6', type: StartPageWidgetType.shortcut, title: 'Wikipedia', url: 'https://wikipedia.org', iconKey: 'book'),
    ];
