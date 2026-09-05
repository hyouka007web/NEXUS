import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as win;

import 'screens/tools_test_screen.dart';

const String testUrl = 'https://example.com';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  // Android: neue webview_flutter-4.x-API, ein Controller pro Seite.
  WebViewController? _androidController;
  // Windows: eigenständiges Paket mit eigenem Controller-Typ.
  win.WebviewController? _windowsController;

  String _status = 'Lädt…';

  bool get _isWindows => !kIsWeb && Platform.isWindows;
  bool get _isLinux => !kIsWeb && Platform.isLinux;
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    if (_isWindows) {
      _initWindowsWebview();
    } else if (_isAndroid) {
      _initAndroidWebview();
    }
    // Linux: bewusst keine Initialisierung, siehe _buildBody().
  }

  void _initAndroidWebview() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => setState(() => _status = 'Lädt: $url'),
          onPageFinished: (_) => setState(() => _status = 'Fertig geladen'),
        ),
      )
      ..loadRequest(Uri.parse(testUrl));
    setState(() => _androidController = controller);
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
    if (_isLinux) {
      // Ehrlich sichtbar statt stillschweigend kaputt: flutter_linux_webview
      // war an die alte webview_flutter-3.0.4-API gekettet und wurde beim
      // Upgrade auf 4.x (siehe pubspec.yaml) inkompatibel. Eine gepflegte
      // Linux+CEF-Alternative für die aktuelle API gibt es derzeit nicht —
      // siehe README, Abschnitt "Linux pausiert".
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'WebView unter Linux ist aktuell pausiert.\n\n'
            'Grund: das einzige verfügbare Linux-Paket '
            '(flutter_linux_webview, CEF-basiert) ist an eine veraltete '
            'webview_flutter-API gekettet, die mit der aktuellen, für '
            'Android nötigen Version nicht mehr zusammenpasst. '
            'Scraper/Video-Harvester/Downloader (Werkzeug-Button oben) '
            'funktionieren hier trotzdem — die hängen an keiner WebView.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_isWindows) {
      final controller = _windowsController;
      if (controller == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return win.Webview(controller);
    }

    final controller = _androidController;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return WebViewWidget(controller: controller);
  }
}
