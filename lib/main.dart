import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart' as win;

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

/// Windows-Übergangslösung: einzelne WebView ohne Tabs/Sidebar/Adblock,
/// plus Zugang zum Werkzeug-Test. Wird ersetzt, sobald Windows sein eigenes
/// BrowserScreen-Äquivalent auf Basis von webview_windows' API bekommt.
class _WindowsFallbackScreen extends StatefulWidget {
  const _WindowsFallbackScreen();

  @override
  State<_WindowsFallbackScreen> createState() =>
      _WindowsFallbackScreenState();
}

class _WindowsFallbackScreenState extends State<_WindowsFallbackScreen> {
  win.WebviewController? _controller;
  String _status = 'Lädt…';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = win.WebviewController();
    try {
      await controller.initialize();
      await controller.loadUrl(testUrl);
      setState(() {
        _controller = controller;
        _status = 'Geladen (Windows/WebView2) — Tabs/Sidebar folgen noch';
      });
    } catch (error) {
      setState(() => _status = 'Fehler beim Initialisieren: $error');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text('NEXUS · $_status'),
        actions: [
          IconButton(
            icon: const Icon(Icons.build_circle_outlined),
            tooltip: 'Scraper / Video Harvester testen',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ToolsTestScreen()),
            ),
          ),
        ],
      ),
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : win.Webview(controller),
    );
  }
}
