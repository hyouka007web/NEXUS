import 'package:flutter/material.dart';

import '../models/quick_link.dart';
import '../state/dev_settings.dart';
import '../theme/nexus_theme.dart';

class StartPage extends StatefulWidget {
  final void Function(String query) onSubmit;
  final int tabCount;
  final int blockedCount;
  const StartPage({
    super.key,
    required this.onSubmit,
    this.tabCount = 1,
    this.blockedCount = 0,
  });

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NexusColors.bgBase,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/nexus_logo.png', width: 120, height: 120),
            const SizedBox(height: 12),
            const Text(
              'NEXUS',
              style: TextStyle(
                color: NexusColors.accentPrimary,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 20),
            _StatusRow(tabCount: tabCount, blockedCount: blockedCount),
            const SizedBox(height: 24),
            Container(
              height: 54,
              decoration: BoxDecoration(
                color: NexusColors.bgPill,
                borderRadius: BorderRadius.circular(NexusRadii.pill),
                border: Border.all(color: NexusColors.border),
              ),
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: NexusColors.textPrimary),
                textInputAction: TextInputAction.go,
                onSubmitted: widget.onSubmit,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  hintText: 'Suchen oder Adresse eingeben',
                  hintStyle: TextStyle(color: NexusColors.textMuted),
                  prefixIcon: Icon(Icons.search, color: NexusColors.textMuted),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('QUICK-LINKS',
                  style: TextStyle(
                      color: NexusColors.textMuted,
                      fontSize: 11,
                      letterSpacing: 2)),
            ),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: DevSettings.instance,
              builder: (context, _) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ...DevSettings.instance.quickLinks.map(
                    (link) => _QuickLinkTile(
                      link: link,
                      onTap: () => widget.onSubmit(link.url),
                      onLongPress: () =>
                          DevSettings.instance.removeQuickLink(link),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int get tabCount => widget.tabCount;
  int get blockedCount => widget.blockedCount;
}

/// Kleine "Terminal-Look"-Statuszeile — Teil des Dark-Industrial-Dashboards.
class _StatusRow extends StatelessWidget {
  final int tabCount;
  final int blockedCount;
  const _StatusRow({required this.tabCount, required this.blockedCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: NexusColors.bgSurfaceRaised,
        borderRadius: BorderRadius.circular(NexusRadii.button),
        border: Border.all(color: NexusColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stat('TABS', '$tabCount'),
          const SizedBox(width: 16),
          _stat('BLOCKIERT', '$blockedCount', color: NexusColors.accentSuccess),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ',
            style: const TextStyle(
                color: NexusColors.textMuted,
                fontSize: 11,
                fontFamily: 'monospace')),
        Text(value,
            style: TextStyle(
                color: color ?? NexusColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace')),
      ],
    );
  }
}

class _QuickLinkTile extends StatelessWidget {
  final QuickLink link;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _QuickLinkTile({
    required this.link,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(NexusRadii.button),
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: NexusColors.bgSurface,
          borderRadius: BorderRadius.circular(NexusRadii.button),
          border: Border.all(color: NexusColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.public, color: NexusColors.accentPrimary, size: 20),
            const SizedBox(height: 6),
            Text(
              link.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: NexusColors.textPrimary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
