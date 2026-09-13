import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'screens/browser_screen.dart';
import 'screens/tools_test_screen.dart';
import 'theme/nexus_theme.dart';
import 'state/theme_config.dart';

const String testUrl = 'https://example.com';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NexusFlutterApp());
}

class NexusFlutterApp extends StatefulWidget {
  const NexusFlutterApp({super.key});
  @override State<NexusFlutterApp> createState()=>_NexusFlutterAppState();
}

class _NexusFlutterAppState extends State<NexusFlutterApp> {
  bool ready=false;
  @override void initState(){super.initState(); ThemeConfig.instance.load().whenComplete(()=>setState(()=>ready=true));}

  @override
  Widget build(BuildContext context) {
    if(!ready) return const MaterialApp(home:Scaffold(body:Center(child:CircularProgressIndicator())));
    return MaterialApp(
      title: 'NEXUS',
      theme: ThemeConfig.instance.materialTheme(),
      home: _home,
    );
  }

  /// Plattform-Weiche: die neue Tabs/Sidebar/Adblock-Oberfläche
  /// (`BrowserScreen`) hängt komplett an `webview_flutter`s
  /// `WebViewController`/`NavigationDelegate`-API — die existiert nur für
  /// Android (und iOS), nicht für Windows/Linux (siehe redirect_shield.dart
  /// für Details zur API selbst). Windows/Linux bleiben deshalb bewusst auf
  /// der einfacheren Vorstufe, bis sie ihr eigenes, zu ihrer jeweiligen
  /// WebView-API passendes Tabs/Sidebar/Adblock-Äquivalent bekommen.
  Widget get _home {
    if (!kIsWeb && Platform.isAndroid) return const BrowserScreen();
    if (!kIsWeb && Platform.isWindows) return const _WindowsFallbackScreen();
    return const ToolsTestScreen(); // Linux: kein WebView, nur Werkzeug-Test
  }
}

/// Windows-Fallback: zeigt einen einfachen Platzhalter an.
/// Windows WebView-Implementierung ist deaktiviert (webview_windows entfernt).
class _WindowsFallbackScreen extends StatelessWidget {
  const _WindowsFallbackScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('Windows WebView wird noch nicht unterstützt.'),
      ),
    );
  }
}
