import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../engines/network_sniffer.dart';
import '../engines/video_harvester_engine.dart';
import '../models/harvested_video.dart';
import '../theme/nexus_theme.dart';

class HarvestTestCase {
  final String name;
  final String url;
  final String expected;
  const HarvestTestCase({required this.name, required this.url, required this.expected});
}

/// Fünf öffentliche, bekannte Referenz-Seiten mit dokumentierter erwarteter
/// Struktur — zum gezielten Nachvollziehen, wo genau der Harvester
/// scheitert oder erfolgreich ist, statt an zufälligen (oft obfuskierten)
/// Streaming-Seiten zu raten. Alle fünf sind offizielle Demo-/Test-
/// Ressourcen der jeweiligen Anbieter, keine beliebigen Drittseiten.
const List<HarvestTestCase> kHarvestTestCases = [
  HarvestTestCase(
    name: 'YouTube',
    url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    expected: 'Erwartet: 0 direkte Treffer. YouTube verschlüsselt seine '
        'Stream-URLs mit einer sich ändernden Signatur-Chiffre — das ist '
        'eine dokumentierte Grenze, kein Bug (siehe VideoHarvesterEngine-Doku).',
  ),
  HarvestTestCase(
    name: 'Vimeo',
    url: 'https://vimeo.com/76979871',
    expected: 'Erwartet: meist 0 direkte Treffer, evtl. ein PLAYER-Eintrag '
        '(iframe-Embed). Vimeo lädt die eigentliche Quelle oft per '
        'signierter, kurzlebiger API-Antwort nach.',
  ),
  HarvestTestCase(
    name: 'Einfache HTML5-<video>-Seite',
    url: 'https://www.w3schools.com/html/html5_video.asp',
    expected: 'Erwartet: 1+ direkter MP4-Treffer — die Seite bindet ein '
        'öffentliches Beispielvideo direkt per <video src="..."> ein, ohne '
        'JS-Umweg. Guter Kontrolltest: wenn das hier fehlschlägt, liegt der '
        'Fehler in der Grundfunktion, nicht in Obfuskierung.',
  ),
  HarvestTestCase(
    name: 'HLS-Demo (hls.js)',
    url: 'https://hls-js.netlify.app/demo/',
    expected: 'Erwartet: 1+ M3U8-Treffer über den Netzwerk-Sniffer (hls.js '
        'lädt die Playlist per fetch/XHR) — lädt standardmäßig Apples '
        'öffentlichen bipbop-Teststream.',
  ),
  HarvestTestCase(
    name: 'DASH-Demo (dash.js Reference Player)',
    url: 'https://reference.dashif.org/dash.js/nightly/samples/dash-if-reference-player/index.html',
    expected: 'Erwartet: 1+ DASH-Treffer (.mpd) über den Netzwerk-Sniffer. '
        'Download bleibt bewusst nicht unterstützt (siehe VideoDownloader) — '
        'hier geht es nur um Erkennung, nicht ums Herunterladen.',
  ),
];

class HarvestTestCasesScreen extends StatefulWidget {
  const HarvestTestCasesScreen({super.key});

  @override
  State<HarvestTestCasesScreen> createState() => _HarvestTestCasesScreenState();
}

class _TestRunResult {
  final bool running;
  final String? summary;
  final List<HarvestedVideo> found;
  const _TestRunResult({this.running = false, this.summary, this.found = const []});
}

class _HarvestTestCasesScreenState extends State<HarvestTestCasesScreen> {
  final Map<String, _TestRunResult> _results = {};
  WebViewController? _hiddenController;

  Future<void> _runTest(HarvestTestCase testCase) async {
    setState(() => _results[testCase.name] = const _TestRunResult(running: true));

    final controller = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted);
    setState(() => _hiddenController = controller);

    var pageLoaded = false;
    controller.setNavigationDelegate(NavigationDelegate(
      onPageFinished: (_) => pageLoaded = true,
    ));

    try {
      await controller.loadRequest(Uri.parse(testCase.url));
      // Auf das Laden warten (einfaches Polling statt eigenem Delegate-
      // Completer, um diese Testklasse unabhängig von RedirectShield zu halten).
      for (var i = 0; i < 40 && !pageLoaded; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      await controller.runJavaScript(NetworkSniffer.injectionScript);
      await controller.runJavaScript(NetworkSniffer.discoveryScript);
      await Future<void>.delayed(const Duration(seconds: 8));

      final merged = <String, HarvestedVideo>{};
      final rawCaptures = await controller.runJavaScriptReturningResult(
        'JSON.stringify(window.__nexusMedia || [])',
      );
      for (final v in VideoHarvesterEngine.classifyCaptures(
        NetworkSniffer.parseCaptures(rawCaptures),
        testCase.name,
      )) {
        merged[v.url] = v;
      }

      final rawHtml = await controller.runJavaScriptReturningResult(
        'document.documentElement.outerHTML',
      );
      String renderedHtml;
      try {
        renderedHtml = jsonDecode(rawHtml.toString()) as String;
      } catch (_) {
        renderedHtml = rawHtml.toString();
      }
      for (final v in VideoHarvesterEngine.extractFromRenderedHtml(
        renderedHtml,
        testCase.url,
        titleHint: testCase.name,
      )) {
        merged.putIfAbsent(v.url, () => v);
      }

      setState(() {
        _results[testCase.name] = _TestRunResult(
          summary: merged.isEmpty
              ? 'Keine Treffer'
              : '${merged.length} Treffer: ${merged.values.map((v) => v.type).toSet().join(', ')}',
          found: merged.values.toList(),
        );
      });
    } catch (e) {
      setState(() => _results[testCase.name] = _TestRunResult(summary: 'Fehler: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexusColors.bgBase,
      appBar: AppBar(title: const Text('Harvester-Testfälle')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: kHarvestTestCases.length,
              itemBuilder: (context, i) {
                final tc = kHarvestTestCases[i];
                final result = _results[tc.name];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(tc.name,
                                  style: Theme.of(context).textTheme.titleSmall),
                            ),
                            FilledButton(
                              onPressed: result?.running == true ? null : () => _runTest(tc),
                              child: Text(result?.running == true ? 'Läuft…' : 'Testen'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(tc.url,
                            style: const TextStyle(fontSize: 11, color: NexusColors.textMuted)),
                        const SizedBox(height: 6),
                        Text(tc.expected,
                            style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                        if (result?.summary != null) ...[
                          const Divider(),
                          Text('Ergebnis: ${result!.summary}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Versteckte WebView, in der die Tests tatsächlich laufen — muss
          // gemountet sein, damit JS zuverlässig ausgeführt wird, deshalb
          // nicht komplett unsichtbar, sondern nur sehr klein.
          if (_hiddenController != null)
            SizedBox(height: 1, width: 1, child: WebViewWidget(controller: _hiddenController!)),
        ],
      ),
    );
  }
}
