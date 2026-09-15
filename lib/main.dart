import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nexus/screens/browser_screen.dart';
import 'package:nexus/services/browser_controller.dart';
import 'package:nexus/theme/nexus_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NexusApp());
}

class NexusApp extends StatefulWidget {
  const NexusApp({super.key});

  @override
  State<NexusApp> createState() => _NexusAppState();
}

class _NexusAppState extends State<NexusApp> {
  late final BrowserController _controller;
  bool _adblockReady = false;

  @override
  void initState() {
    super.initState();
    _controller = BrowserController();
    // Adblocker muss initialisiert werden, sonst blockt er nichts
    // (siehe AdBlockEngine.initialize) — läuft parallel zum ersten Tab-Aufbau.
    _controller.adblock.initialize(assetPath: 'assets/filters/easylist_sample.txt').then((_) {
      if (mounted) setState(() => _adblockReady = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<BrowserController>.value(
      value: _controller,
      child: MaterialApp(
        title: 'NEXUS Browser',
        debugShowCheckedModeBanner: false,
        theme: NexusTheme.dark,
        home: const BrowserScreen(),
      ),
    );
  }
}
