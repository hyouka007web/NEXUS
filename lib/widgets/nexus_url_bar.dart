import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:nexus/services/browser_controller.dart';
import 'package:nexus/theme/nexus_theme.dart';

class NexusUrlBar extends StatefulWidget {
  const NexusUrlBar({super.key});

  @override
  State<NexusUrlBar> createState() => _NexusUrlBarState();
}

class _NexusUrlBarState extends State<NexusUrlBar> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  String? _syncedForTabId;

  String _normalize(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'nexus://home';
    final looksLikeUrl = trimmed.contains('.') && !trimmed.contains(' ');
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://') || trimmed.startsWith('nexus://')) {
      return trimmed;
    }
    if (looksLikeUrl) return 'https://$trimmed';
    return 'https://duckduckgo.com/?q=${Uri.encodeComponent(trimmed)}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BrowserController>();
    final tab = controller.activeTab;

    if (tab != null && !_focus.hasFocus && _syncedForTabId != '${tab.id}:${tab.url}') {
      _text.text = tab.isHome ? '' : tab.url;
      _syncedForTabId = '${tab.id}:${tab.url}';
    }

    return Container(
      color: NexusColors.surface,
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu_rounded, size: 20),
            tooltip: 'Sidebar',
            onPressed: () => controller.toggleSidebar(),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            onPressed: (tab?.canGoBack ?? false) ? () => tab!.controller?.goBack() : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            onPressed: (tab?.canGoForward ?? false) ? () => tab!.controller?.goForward() : null,
          ),
          IconButton(
            icon: Icon((tab?.isLoading ?? false) ? Icons.close_rounded : Icons.refresh_rounded, size: 20),
            onPressed: () {
              if (tab == null) return;
              if (tab.isLoading) {
                tab.controller?.stopLoading();
              } else {
                tab.controller?.reload();
              }
            },
          ),
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: NexusColors.surfaceRaised,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Icon(
                    (tab?.url ?? '').startsWith('https://') ? Icons.lock_rounded : Icons.public,
                    size: 14,
                    color: NexusColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      style: const TextStyle(fontSize: 13, color: NexusColors.textPrimary),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Suchen oder URL eingeben',
                      ),
                      onSubmitted: (value) {
                        if (tab == null) return;
                        final target = _normalize(value);
                        if (target == 'nexus://home') {
                          tab.update(isHome: true, url: target, title: 'Neuer Tab');
                        } else {
                          tab.update(isHome: false);
                          tab.controller?.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
                        }
                        _focus.unfocus();
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

