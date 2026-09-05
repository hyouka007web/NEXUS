import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_windows/webview_windows.dart' as win;

// Linux nutzt denselben package:webview_flutter-API-Oberbau wie Android,
// nur mit anderer Plattform-Engine dahinter (CEF statt Android-WebView).
// Das Paket registriert sich selbst als Linux-Implementierung — daher hier
// kein eigenständiger Import einer anderen Widget-Klasse nötig wie bei
// Windows, sondern nur eine Plattform-Weiche unten in main().
import 'package:flutter_linux_webview/flutter_linux_webview.dart' as linux_webview;

import 'screens/tools_test_screen.dart';

const String testUrl = 'https://example.com';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android: explizit Surface-basiertes Rendering statt virtuellem Display.
  // Standard-Empfehlung für webview_flutter 3.x, stabiler auf schwächeren
  // Geräten und bei Hardware-Beschleunigung.
  if (!kIsWeb && Platform.isAndroid) {
    WebView.platform = SurfaceAndroidWebView();
  }

  // Linux: CEF-Prozess muss vor runApp() initialisiert werden.
  if (!kIsWeb && Platform.isLinux) {
    await linux_webview.LinuxWebViewPlugin.initialize();
    WebView.platform = linux_webview.LinuxWebView();
  }

  runApp(const NexusFlutterApp());
}

class NexusFlutterApp extends StatelessWidget {
  const NexusFlutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NEXUS (Flutter, Stufe 0)',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.amber,
        useMaterial3: true,
      ),
      home: const WebViewTestScreen(),
    );
  }
}

class WebViewTestScreen extends StatefulWidget {
  const WebViewTestScreen({super.key});

  @override
  State<WebViewTestScreen> createState() => _WebViewTestScreenState();
}

class _WebViewTestScreenState extends State<WebViewTestScreen> {
  // Nur für Windows befüllt — Android/Linux laufen über das WebView-Widget
  // aus package:webview_flutter direkt im build()-Baum.
  win.WebviewController? _windowsController;
  String _status = 'Lädt…';

  bool get _isWindows => !kIsWeb && Platform.isWindows;

  @override
  void initState() {
    super.initState();
    if (_isWindows) {
      _initWindowsWebview();
    }
  }

  Future<void> _initWindowsWebview() async {
    final controller = win.WebviewController();
    try {
      await controller.initialize();
      await controller.loadUrl(testUrl);
      setState(() {
        _windowsController = controller;
        _status = 'Geladen (Windows/WebView2)';
      });
    } catch (error) {
      setState(() => _status = 'Fehler beim Initialisieren: $error');
    }
  }

  @override
  void dispose() {
    _windowsController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isWindows) {
      final controller = _windowsController;
      if (controller == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return win.Webview(controller);
    }

    // Android + Linux: gemeinsamer Pfad über webview_flutter.
    return WebView(
      initialUrl: testUrl,
      javascriptMode: JavascriptMode.unrestricted,
      onPageStarted: (url) => setState(() => _status = 'Lädt: $url'),
      onPageFinished: (url) => setState(() => _status = 'Fertig geladen'),
    );
  }
}
