import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../engines/network_sniffer.dart';
import '../models/tab_model.dart';
import '../state/dev_settings.dart';
import '../theme/nexus_theme.dart';

/// Power-User-Werkzeuge für den aktiven Tab. Alles hier arbeitet auf
/// öffentlichen, dokumentierten `webview_flutter`-APIs (`setUserAgent`,
/// `WebViewCookieManager`, `runJavaScript`) — keine versteckten Tricks.
class DevToolsScreen extends StatefulWidget {
  final NexusTab tab;
  const DevToolsScreen({super.key, required this.tab});

  @override
  State<DevToolsScreen> createState() => _DevToolsScreenState();
}

class _DevToolsScreenState extends State<DevToolsScreen> {
  List<String> _sniffed = [];
  bool _loadingSniffed = false;
  final _scriptController = TextEditingController();
  String? _currentHost;

  @override
  void initState() {
    super.initState();
    _currentHost = Uri.tryParse(widget.tab.url)?.host;
    if (_currentHost != null) {
      _scriptController.text =
          DevSettings.instance.domainScripts[_currentHost] ?? '';
    }
    _refreshSniffed();
  }

  @override
  void dispose() {
    _scriptController.dispose();
    super.dispose();
  }

  Future<void> _refreshSniffed() async {
    setState(() => _loadingSniffed = true);
    try {
      final raw = await widget.tab.controller.runJavaScriptReturningResult(
        'JSON.stringify(window.__nexusSniffed || [])',
      );
      setState(() => _sniffed = NetworkSniffer.parseResult(raw));
    } catch (_) {
      setState(() => _sniffed = []);
    } finally {
      setState(() => _loadingSniffed = false);
    }
  }

  Future<void> _clearCookies() async {
    await WebViewCookieManager().clearCookies();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alle Cookies gelöscht')),
      );
    }
  }

  void _saveScript() {
    if (_currentHost == null) return;
    DevSettings.instance.setDomainScript(_currentHost!, _scriptController.text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Skript für $_currentHost gespeichert')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexusColors.bgBase,
      appBar: AppBar(title: const Text('DevTools')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            'Netzwerk-Sniffer (aktueller Tab)',
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshSniffed,
            ),
            child: _loadingSniffed
                ? const Center(child: CircularProgressIndicator())
                : _sniffed.isEmpty
                    ? const Text('Noch nichts protokolliert.',
                        style: TextStyle(color: NexusColors.textMuted))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _sniffed
                            .map((u) => SelectableText(u,
                                style: const TextStyle(fontSize: 12)))
                            .toList(),
                      ),
          ),
          const SizedBox(height: 20),
          _section(
            'User-Agent',
            child: ListenableBuilder(
              listenable: DevSettings.instance,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: kUserAgentPresets.entries.map((entry) {
                  final active = (DevSettings.instance.userAgentOverride ?? '') ==
                      entry.value;
                  return RadioListTile<String>(
                    dense: true,
                    value: entry.value,
                    groupValue:
                        DevSettings.instance.userAgentOverride ?? '',
                    onChanged: (v) => DevSettings.instance.setUserAgent(v),
                    title: Text(entry.key,
                        style: const TextStyle(fontSize: 13)),
                    activeColor: NexusColors.accentPrimary,
                    selected: active,
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Gilt ab dem nächsten neuen Tab bzw. Neuladen.',
            style: TextStyle(color: NexusColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 20),
          _section(
            'Cookies',
            child: FilledButton.tonal(
              onPressed: _clearCookies,
              child: const Text('Alle Cookies löschen'),
            ),
          ),
          const SizedBox(height: 20),
          _section(
            'Eigenes Skript für ${_currentHost ?? "diese Domain"}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Läuft automatisch nach jedem Laden dieser Domain. Nur '
                  'was du selbst hier einträgst — NEXUS liefert keine '
                  'vorgefertigten Skripte für bestimmte Seiten.',
                  style: TextStyle(color: NexusColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _scriptController,
                  maxLines: 6,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: NexusColors.bgPill,
                    hintText: 'z.B. console.log("hallo")',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(NexusRadii.button),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _currentHost == null ? null : _saveScript,
                  child: const Text('Speichern'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, {required Widget child, Widget? trailing}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: NexusColors.accentPrimary)),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
