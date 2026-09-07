import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'pane_manager.dart';

class WorkspaceSnapshot {
  WorkspaceSnapshot({required this.name, required this.tabs, required this.panes, this.createdAt});
  final String name;
  final List<Map<String, dynamic>> tabs;
  final Map<String, dynamic> panes;
  final DateTime? createdAt;
  Map<String, dynamic> toJson() => {'name': name, 'tabs': tabs, 'panes': panes, 'createdAt': (createdAt ?? DateTime.now()).toIso8601String()};
  static WorkspaceSnapshot fromJson(Map<String, dynamic> j) => WorkspaceSnapshot(name: j['name'], tabs: List<Map<String, dynamic>>.from((j['tabs'] as List).map((e) => Map<String,dynamic>.from(e))), panes: Map<String,dynamic>.from(j['panes']), createdAt: DateTime.tryParse(j['createdAt'] ?? ''));
}

class WorkspaceManager extends ChangeNotifier {
  static final instance = WorkspaceManager._();
  WorkspaceManager._();
  List<WorkspaceSnapshot> workspaces = [];
  static const _fileName = 'workspaces.json';

  Future<File> _file() async { final d = await getApplicationDocumentsDirectory(); return File('${d.path}/$_fileName'); }
  Future<void> restore() async { try { final f = await _file(); if (await f.exists()) { final list = jsonDecode(await f.readAsString()) as List; workspaces = list.map((e) => WorkspaceSnapshot.fromJson(Map<String,dynamic>.from(e))).toList(); notifyListeners(); } } catch (_) {} }
  Future<void> save(String name, List<Map<String,dynamic>> tabs, PaneManager panes) async {
    final snap = WorkspaceSnapshot(name: name.trim(), tabs: tabs, panes: panes.toJson());
    workspaces.removeWhere((w) => w.name.toLowerCase() == snap.name.toLowerCase()); workspaces.insert(0, snap); await _persist(); notifyListeners();
  }
  Future<void> remove(String name) async { workspaces.removeWhere((w) => w.name == name); await _persist(); notifyListeners(); }
  Future<void> _persist() async { try { final f = await _file(); await f.writeAsString(jsonEncode(workspaces.map((e) => e.toJson()).toList())); } catch (_) {} }
}
