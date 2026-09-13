// Platform-spezifische WebView-Bridge
// Wählt die Implementierung basierend auf der Plattform.
// Auf Mobile (dart.io) wird webview_flutter verwendet,
// auf Web (dart.library.html) ein Stub.

export 'src/webview_interface.dart'
    if (dart.library.io) 'src/webview_mobile.dart'
    if (dart.library.html) 'src/webview_stub.dart';
