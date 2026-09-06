import 'package:flutter/material.dart';

import '../theme/nexus_theme.dart';

class StartPage extends StatefulWidget {
  final void Function(String query) onSubmit;
  const StartPage({super.key, required this.onSubmit});

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
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/nexus_logo.png', width: 140, height: 140),
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
            const SizedBox(height: 32),
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
            const SizedBox(height: 12),
            const Text(
              'DuckDuckGo',
              style: TextStyle(color: NexusColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
