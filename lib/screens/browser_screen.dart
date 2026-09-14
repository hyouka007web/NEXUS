import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nexus/services/adblock_service.dart';
import 'package:nexus/widgets/nexus_web_view.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final AdblockService _adblock = AdblockService();
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _adblock.loadFilters();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NEXUS Browser'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shield),
            onPressed: () => _adblock.toggle(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _urlController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'URL eingeben',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  _loadUrl(value);
                }
              },
            ),
          ),
          Expanded(
            child: NexusWebView(
              url: _urlController.text.isNotEmpty
                  ? _urlController.text
                  : 'https://duckduckgo.com',
              adblock: _adblock,
            ),
          ),
        ],
      ),
    );
  }

  void _loadUrl(String url) {
    setState(() {
      _urlController.text = url;
    });
  }
}
