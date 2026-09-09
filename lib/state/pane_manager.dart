import 'dart:convert';
import 'package:flutter/foundation.dart';

enum PaneOrientation { horizontal, vertical }
enum PaneKind { browser, terminal, devtools, harvesterDebug }

class PaneState {
  PaneState({required this.id, List<String>? tabIds, this.activeTabId, this.kind = PaneKind.browser, this.terminalText = ''}) : tabIds = List<String>.from(tabIds ?? const []);
  final String id;
  List<String> tabIds;
  String? activeTabId;
  PaneKind kind;
  String terminalText;

  Map<String, dynamic> toJson() => {
    'id': id, 'tabIds': tabIds, 'activeTabId': activeTabId,
    'kind': kind.name, 'terminalText': terminalText,
  };
  static PaneState fromJson(Map<String, dynamic> j) => PaneState(
    id: j['id'] as String,
    tabIds: List<String>.from(j['tabIds'] ?? const []),
    activeTabId: j['activeTabId'] as String?,
    kind: PaneKind.values.firstWhere((e) => e.name == j['kind'], orElse: () => PaneKind.browser),
    terminalText: j['terminalText'] as String? ?? '',
  );
}

class PaneNode {
  PaneNode.leaf(this.pane);
  PaneNode.split(this.orientation, this.ratio, this.first, this.second);
  PaneState? pane;
  PaneOrientation? orientation;
  double ratio = .5;
  PaneNode? first;
  PaneNode? second;
  bool get isLeaf => pane != null;

  Map<String, dynamic> toJson() => isLeaf
      ? {'leaf': pane!.toJson()}
      : {'split': orientation!.name, 'ratio': ratio, 'first': first!.toJson(), 'second': second!.toJson()};
  static PaneNode fromJson(Map<String, dynamic> j) {
    if (j['leaf'] != null) return PaneNode.leaf(PaneState.fromJson(Map<String, dynamic>.from(j['leaf'])));
    return PaneNode.split(
      PaneOrientation.values.firstWhere((e) => e.name == j['split'], orElse: () => PaneOrientation.vertical),
      (j['ratio'] as num?)?.toDouble() ?? .5,
      fromJson(Map<String, dynamic>.from(j['first'])),
      fromJson(Map<String, dynamic>.from(j['second'])),
    );
  }
}

class PaneManager extends ChangeNotifier {
  PaneManager() : root = PaneNode.leaf(PaneState(id: _id(1)));
  PaneNode root;
  String activePaneId = '';
  int _counter = 2;

  List<PaneState> get leaves {
    final out = <PaneState>[];
    void walk(PaneNode n) { if (n.isLeaf) { out.add(n.pane!); } else { walk(n.first!); walk(n.second!); } }
    walk(root); return out;
  }
  PaneState get activePane => leaves.firstWhere((p) => p.id == activePaneId, orElse: () => leaves.first);

  void ensureActive() { if (activePaneId.isEmpty || !leaves.any((p) => p.id == activePaneId)) activePaneId = leaves.first.id; }

  PaneState splitActive(PaneOrientation orientation, String? tabId) {
    ensureActive();
    final old = _find(root, activePaneId)!;
    final oldPane = old.pane!;
    final newPane = PaneState(id: _id(_counter++), tabIds: tabId == null ? [] : [tabId], activeTabId: tabId);
    old.pane = null; old.orientation = orientation; old.ratio = .5;
    old.first = PaneNode.leaf(oldPane); old.second = PaneNode.leaf(newPane);
    activePaneId = newPane.id;
    notifyListeners(); return newPane;
  }

  void closePane(String paneId) {
    if (leaves.length <= 1) return;
    PaneNode? parent;
    PaneNode? target;
    void walk(PaneNode n) { if (!n.isLeaf) { if (n.first!.isLeaf && n.first!.pane!.id == paneId || n.second!.isLeaf && n.second!.pane!.id == paneId) { parent = n; target = n.first!.pane!.id == paneId ? n.first : n.second; return; } walk(n.first!); walk(n.second!); } }
    walk(root);
    if (parent == null || target == null) return;
    final survivor = identical(parent!.first, target) ? parent!.second! : parent!.first!;
    parent!.pane = survivor.pane; parent!.orientation = survivor.orientation; parent!.ratio = survivor.ratio; parent!.first = survivor.first; parent!.second = survivor.second;
    ensureActive(); notifyListeners();
  }

  void setRatio(String paneId, double ratio) {
    final n = _find(root, paneId); if (n == null || n.isLeaf) return;
    n.ratio = ratio.clamp(.2, .8); notifyListeners();
  }

  void setKind(PaneKind kind) { activePane.kind = kind; notifyListeners(); }
  void setTerminalText(String text) { activePane.terminalText = text; notifyListeners(); }

  PaneNode? _find(PaneNode n, String id) { if (n.isLeaf) return n.pane!.id == id ? n : null; return _find(n.first!, id) ?? _find(n.second!, id); }
  static String _id(int n) => 'pane-${DateTime.now().microsecondsSinceEpoch}-$n';

  Map<String, dynamic> toJson() => {'root': root.toJson(), 'activePaneId': activePaneId};
  void restore(Map<String, dynamic> json) { root = PaneNode.fromJson(Map<String, dynamic>.from(json['root'])); activePaneId = json['activePaneId'] as String? ?? ''; ensureActive(); notifyListeners(); }
  String encode() => jsonEncode(toJson());
}
