import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class KeybindingEngine extends ChangeNotifier {
  static final instance = KeybindingEngine._();
  KeybindingEngine._();
  String mode = 'Custom';
  final Map<String, String> bindings = {
    'command.palette': 'Ctrl+K', 'browser.focusAddress': 'Ctrl+L',
    'browser.newTab': 'Ctrl+T', 'browser.closeTab': 'Ctrl+W',
    'browser.back': 'Alt+Left', 'browser.forward': 'Alt+Right',
    'browser.reload': 'Ctrl+R', 'browser.harvest': 'Ctrl+Shift+M',
    'pane.splitVertical': 'Ctrl+Alt+V', 'pane.splitHorizontal': 'Ctrl+Alt+H',
    'pane.terminal': 'Ctrl+Alt+T', 'pane.devtools': 'Ctrl+Shift+I',
    'browser.frameless': 'Ctrl+Shift+F', 'workspace.save': 'Ctrl+Shift+S',
  };

  Future<void> restore() async {
    try {
      final d = await getApplicationDocumentsDirectory();
      final f = File('${d.path}/keybindings.json');
      if (await f.exists()) {
        final j = Map<String, dynamic>.from(jsonDecode(await f.readAsString()));
        mode = j['mode'] as String? ?? mode;
        bindings.addAll(Map<String, String>.from(j['bindings'] ?? {}));
      }
    } catch (_) {}
  }

  Future<void> set(String command, String shortcut) async {
    bindings[command] = shortcut;
    mode = 'Custom';
    notifyListeners();
    await _persist();
  }

  Future<void> applyMode(String value) async {
    mode = value;
    if (value == 'Vim') {
      bindings.addAll({'browser.focusAddress': '/', 'browser.back': 'H', 'browser.forward': 'L', 'browser.reload': 'R'});
    } else if (value == 'Emacs') {
      bindings.addAll({'browser.back': 'Alt+Left', 'browser.forward': 'Alt+Right', 'browser.focusAddress': 'Ctrl+L'});
    } else if (value == 'Gaming') {
      bindings.addAll({'command.palette': 'F1', 'browser.newTab': 'Ctrl+T', 'browser.closeTab': 'Ctrl+W', 'pane.splitVertical': 'F2', 'pane.splitHorizontal': 'F3'});
    }
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final d = await getApplicationDocumentsDirectory();
      await File('${d.path}/keybindings.json').writeAsString(jsonEncode({'mode': mode, 'bindings': bindings}));
    } catch (_) {}
  }
}
