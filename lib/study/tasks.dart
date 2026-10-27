import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/async/cancelable_request.dart';
import '../core/diagnostics.dart';

enum StudyTaskStatus { queued, running, paused, completed, failed, cancelled }

class StudyTask {
  StudyTask({
    required this.key,
    required this.title,
    required this.course,
    required this.lecture,
    required this.operation,
    this.pausable = true,
  });
  final String key;
  final String title;
  final String course;
  final String lecture;
  final bool pausable;
  String output = '';
  final Future<void> Function(CancellationToken, void Function(double?, String))
  operation;
  StudyTaskStatus status = StudyTaskStatus.queued;
  double? progress;
  String detail = '';
  CancellationToken? _cancellation;
}

/// Two jobs at a time; state lives outside routes so navigation never cancels work.
class StudyTasks extends ChangeNotifier {
  final List<StudyTask> _items = [];
  bool _disposed = false;
  List<StudyTask> get items => List.unmodifiable(_items);
  int get activeCount => _items
      .where(
        (item) =>
            item.status == StudyTaskStatus.queued ||
            item.status == StudyTaskStatus.running,
      )
      .length;

  void add(StudyTask task) {
    if (_items.any(
      (item) =>
          item.key == task.key &&
          (item.status == StudyTaskStatus.running ||
              item.status == StudyTaskStatus.queued ||
              item.status == StudyTaskStatus.paused),
    )) {
      return;
    }
    _items.insert(0, task);
    notifyListeners();
    _pump();
  }

  void pause(StudyTask task) {
    if (!task.pausable ||
        (task.status != StudyTaskStatus.running &&
            task.status != StudyTaskStatus.queued)) {
      return;
    }
    task.status = StudyTaskStatus.paused;
    task._cancellation?.cancel();
    notifyListeners();
  }

  void resume(StudyTask task) {
    if (task._cancellation != null ||
        ![
          StudyTaskStatus.paused,
          StudyTaskStatus.failed,
          StudyTaskStatus.cancelled,
        ].contains(task.status)) {
      return;
    }
    task.status = StudyTaskStatus.queued;
    notifyListeners();
    _pump();
  }

  void cancel(StudyTask task) {
    task.status = StudyTaskStatus.cancelled;
    task._cancellation?.cancel();
    notifyListeners();
    _pump();
  }

  void _pump() {
    if (_disposed) return;
    var running = _items.where((item) => item._cancellation != null).length;
    for (final task in _items.reversed.where(
      (item) => item.status == StudyTaskStatus.queued,
    )) {
      if (running++ >= 2) break;
      unawaited(_run(task));
    }
  }

  Future<void> _run(StudyTask task) async {
    final cancellation = CancellationToken();
    task._cancellation = cancellation;
    task.status = StudyTaskStatus.running;
    notifyListeners();
    var lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await task.operation(cancellation, (progress, detail) {
        if (_disposed || cancellation.isCancelled) return;
        task.progress = progress;
        task.detail = detail;
        final now = DateTime.now();
        if (now.difference(lastUpdate).inMilliseconds >= 100) {
          lastUpdate = now;
          notifyListeners();
        }
      });
      cancellation.check();
      task.status = StudyTaskStatus.completed;
      task.progress = 1;
      task.detail = '已完成';
    } on RequestCancelled {
      // Pausing preserves downloaded parts and the user's chosen task state.
    } catch (failure, stack) {
      if (!cancellation.isCancelled) {
        task.status = StudyTaskStatus.failed;
        task.detail = '处理失败，可重试';
        AppDiagnostics.instance.report(task.title, failure, stack);
      }
    } finally {
      task._cancellation = null;
      if (!_disposed) {
        notifyListeners();
        _pump();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final task in _items) {
      task._cancellation?.cancel();
    }
    super.dispose();
  }
}
