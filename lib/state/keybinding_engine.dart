import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;
import 'package:path_provider/path_provider.dart';

/// Wandelt einen gespeicherten Shortcut-String ("Ctrl+Shift+M", "Alt+Left",
/// "F1", "/") in einen echten `SingleActivator` um. Vorher stand
/// [KeybindingEngine.bindings] nur als Daten da — die tatsächliche
/// Tastenverarbeitung in `browser_screen.dart` war komplett hartkodiert
/// und hat diese Map nie gelesen, wodurch Änderungen an den Keybindings
/// (z.B. der Moduswechsel auf "Vim"/"Gaming") wirkungslos blieben.
SingleActivator? parseShortcut(String raw) {
  final parts = raw.split('+').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  final keyPart = parts.removeLast();
  bool control = false, alt = false, shift = false, meta = false;
  for (final mod in parts) {
    switch (mod.toLowerCase()) {
      case 'ctrl':
      case 'control':
        control = true;
        break;
      case 'alt':
        alt = true;
        break;
      case 'shift':
        shift = true;
        break;
      case 'meta':
      case 'cmd':
        meta = true;
        break;
    }
  }
  final key = _keyFor(keyPart);
  if (key == null) return null;
  return SingleActivator(key, control: control, alt: alt, shift: shift, meta: meta);
}

const _letterKeys = {
  'a': LogicalKeyboardKey.keyA, 'b': LogicalKeyboardKey.keyB, 'c': LogicalKeyboardKey.keyC,
  'd': LogicalKeyboardKey.keyD, 'e': LogicalKeyboardKey.keyE, 'f': LogicalKeyboardKey.keyF,
  'g': LogicalKeyboardKey.keyG, 'h': LogicalKeyboardKey.keyH, 'i': LogicalKeyboardKey.keyI,
  'j': LogicalKeyboardKey.keyJ, 'k': LogicalKeyboardKey.keyK, 'l': LogicalKeyboardKey.keyL,
  'm': LogicalKeyboardKey.keyM, 'n': LogicalKeyboardKey.keyN, 'o': LogicalKeyboardKey.keyO,
  'p': LogicalKeyboardKey.keyP, 'q': LogicalKeyboardKey.keyQ, 'r': LogicalKeyboardKey.keyR,
  's': LogicalKeyboardKey.keyS, 't': LogicalKeyboardKey.keyT, 'u': LogicalKeyboardKey.keyU,
  'v': LogicalKeyboardKey.keyV, 'w': LogicalKeyboardKey.keyW, 'x': LogicalKeyboardKey.keyX,
  'y': LogicalKeyboardKey.keyY, 'z': LogicalKeyboardKey.keyZ,
};
const _digitKeys = {
  '0': LogicalKeyboardKey.digit0, '1': LogicalKeyboardKey.digit1, '2': LogicalKeyboardKey.digit2,
  '3': LogicalKeyboardKey.digit3, '4': LogicalKeyboardKey.digit4, '5': LogicalKeyboardKey.digit5,
  '6': LogicalKeyboardKey.digit6, '7': LogicalKeyboardKey.digit7, '8': LogicalKeyboardKey.digit8,
  '9': LogicalKeyboardKey.digit9,
};

LogicalKeyboardKey? _keyFor(String name) {
  final n = name.toLowerCase();
  if (_letterKeys.containsKey(n)) return _letterKeys[n];
  if (_digitKeys.containsKey(n)) return _digitKeys[n];
  const named = {
    'left': LogicalKeyboardKey.arrowLeft,
    'right': LogicalKeyboardKey.arrowRight,
    'up': LogicalKeyboardKey.arrowUp,
    'down': LogicalKeyboardKey.arrowDown,
    'esc': LogicalKeyboardKey.escape,
    'escape': LogicalKeyboardKey.escape,
    'enter': LogicalKeyboardKey.enter,
    'space': LogicalKeyboardKey.space,
    'tab': LogicalKeyboardKey.tab,
    '/': LogicalKeyboardKey.slash,
    'f1': LogicalKeyboardKey.f1,
    'f2': LogicalKeyboardKey.f2,
    'f3': LogicalKeyboardKey.f3,
    'f4': LogicalKeyboardKey.f4,
    'f5': LogicalKeyboardKey.f5,
  };
  return named[n];
}

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
