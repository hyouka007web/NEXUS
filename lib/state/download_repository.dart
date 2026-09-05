import 'package:flutter/foundation.dart';

import '../models/download_task.dart';

/// In-memory-Register der in diesem App-Prozess laufenden Downloads, damit
/// der Mediathek-Tab "In Arbeit" pro Video einen Live-Fortschrittsbalken
/// zeigen kann. Downloads laufen nur, solange NEXUS im Vordergrund/am Leben
/// ist (es gibt noch keinen Hintergrund-Download-Dienst) — überlebt daher
/// bewusst keinen vollständigen Prozess-Kill, genau wie im Kotlin-Original.
///
/// Unterschied zum Kotlin-Original: dort war das eine reine
/// Listener-Liste (`addListener`/`removeListener`), weil es kein
/// eingebautes Observable-Konzept gab. Hier ist [ChangeNotifier] die
/// Flutter-idiomatische Entsprechung genau desselben Musters — Widgets
/// hören direkt über `ListenableBuilder`/`AnimatedBuilder` zu, ohne dass
/// wir die Listener-Verwaltung von Hand nachbauen müssen.
class DownloadRepository extends ChangeNotifier {
  DownloadRepository._();
  static final DownloadRepository instance = DownloadRepository._();

  final List<DownloadTask> _tasks = [];

  List<DownloadTask> activeAndRecent() => List.unmodifiable(_tasks);

  DownloadTask start(String title, String sourceUrl) {
    final task = DownloadTask(
      title: title,
      sourceUrl: sourceUrl,
      state: DownloadState.downloading,
    );
    _tasks.add(task);
    notifyListeners();
    return task;
  }

  /// Gibt die aktualisierte Aufgabe zurück — da [DownloadTask] unveränderlich
  /// ist (siehe dortige Erklärung), muss der Aufrufer diese neue Referenz
  /// weiterverwenden statt die alte zu mutieren.
  DownloadTask update(DownloadTask task, int percent) {
    final updated = task.copyWith(
      percent: percent.clamp(0, 100),
      state: DownloadState.downloading,
    );
    _replace(task, updated);
    return updated;
  }

  DownloadTask finish(DownloadTask task) {
    final updated = task.copyWith(percent: 100, state: DownloadState.done);
    _replace(task, updated);
    // Bleibt kurz sichtbar als "fertig" statt sofort zu verschwinden — die
    // Mediathek-UI entfernt DONE-Aufgaben selbst, sobald "Meine Downloads"
    // neu geladen wird (siehe clearFinished()).
    return updated;
  }

  DownloadTask fail(DownloadTask task, String message) {
    final updated =
        task.copyWith(state: DownloadState.failed, errorMessage: message);
    _replace(task, updated);
    return updated;
  }

  void clearFinished() {
    _tasks.removeWhere(
      (t) => t.state == DownloadState.done || t.state == DownloadState.failed,
    );
    notifyListeners();
  }

  void _replace(DownloadTask oldTask, DownloadTask newTask) {
    final index = _tasks.indexWhere((t) => t.id == oldTask.id);
    if (index != -1) _tasks[index] = newTask;
    notifyListeners();
  }
}
