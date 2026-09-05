import 'dart:math';

enum DownloadState { queued, downloading, done, failed }

/// Ein einzelner, gerade laufender oder kürzlich abgeschlossener Download —
/// Pendant zu Kotlins `DownloadTask`. Anders als in Kotlin sind die Felder
/// hier final; Statusänderungen laufen über [DownloadRepository], das ein
/// neues Objekt einsetzt statt Felder mutable zu machen — passt besser zu
/// Flutters `ChangeNotifier`-Modell (siehe dortige Erklärung).
class DownloadTask {
  final String id;
  final String title;
  final String sourceUrl;
  final int percent;
  final DownloadState state;
  final String? errorMessage;

  DownloadTask({
    String? id,
    required this.title,
    required this.sourceUrl,
    this.percent = 0,
    this.state = DownloadState.queued,
    this.errorMessage,
  }) : id = id ?? _randomId();

  DownloadTask copyWith({
    int? percent,
    DownloadState? state,
    String? errorMessage,
  }) =>
      DownloadTask(
        id: id,
        title: title,
        sourceUrl: sourceUrl,
        percent: percent ?? this.percent,
        state: state ?? this.state,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  static String _randomId() {
    final rnd = Random.secure();
    return List.generate(12, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }
}
