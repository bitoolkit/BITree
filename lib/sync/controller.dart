import 'dart:async';

import 'package:flutter/foundation.dart';

import '../agenda/deadline_source.dart';
import '../core/async/cancelable_request.dart';
import '../mooc/controller.dart';
import '../school/controller.dart';

enum SyncTarget {
  schedule('课表', '同步课表'),
  exams('考试安排', '同步考试安排'),
  grades('成绩', '同步成绩'),
  studyPlan('学分进度', '同步学分进度'),
  lexue('乐学 DDL', '更新乐学 DDL', DeadlineSource.lexue),
  eclass('新延河课堂 DDL', '更新新延河课堂 DDL', DeadlineSource.eclass),
  mooc('中国大学MOOC DDL', '同步中国大学MOOC DDL', DeadlineSource.mooc);

  const SyncTarget(this.title, this.label, [this.source]);
  final String title;
  final String label;
  final DeadlineSource? source;
  bool get isSchool => this != mooc;
}

enum SyncPhase {
  queued,
  running,
  cancelling,
  attention,
  completed,
  failed,
  cancelled,
}

class SyncTask {
  SyncTask._(this.target, this.term);
  final SyncTarget target;
  final String? term;
  SyncPhase _phase = SyncPhase.queued;
  String _message = '';
  final _finished = Completer<bool>();

  SyncPhase get phase => _phase;
  String get message => _message;
  Future<bool> get finished => _finished.future;
  bool get active => switch (_phase) {
    SyncPhase.queued ||
    SyncPhase.running ||
    SyncPhase.cancelling ||
    SyncPhase.attention => true,
    _ => false,
  };
}

/// Keeps school reads sequential because they share one authenticated session.
/// MOOC uses a separate account and can run alongside them.
class SyncController extends ChangeNotifier {
  SyncController({required this._school, required this._mooc}) {
    _school.addListener(_changed);
    _mooc.addListener(_changed);
  }
  final SchoolController _school;
  final MoocController _mooc;
  final _tasks = <SyncTask>[];
  bool _disposed = false;
  bool _scheduled = false;

  List<SyncTask> get tasks => List.unmodifiable(_tasks);
  int get activeCount => _tasks.where((task) => task.active).length;
  bool get running => _tasks.any(
    (task) =>
        task.phase == SyncPhase.running || task.phase == SyncPhase.cancelling,
  );
  bool contains(SyncTarget target, {String? term}) => _tasks.any(
    (task) => task.target == target && task.term == term && task.active,
  );

  String progress(SyncTask task) => switch (task.phase) {
    SyncPhase.queued =>
      !task.target.isSchool
          ? '等待同步'
          : _school.verificationRequired
          ? '等待学校账号验证'
          : _school.loginExpired
          ? '等待学校账号登录'
          : '等待学校请求完成',
    SyncPhase.running =>
      task.target == SyncTarget.mooc ? _mooc.progress : '正在同步…',
    SyncPhase.cancelling => '正在取消…',
    _ => task.message,
  };

  SyncTask enqueue(SyncTarget target, {String? term}) {
    assert(!_disposed);
    final existing = _tasks
        .where((task) => task.target == target && task.term == term)
        .firstOrNull;
    if (existing?.active == true) return existing!;
    final task = SyncTask._(target, term);
    if (existing != null) _tasks.remove(existing);
    _tasks.add(task);
    notifyListeners();
    _schedule();
    return task;
  }

  void cancel(SyncTask task) {
    if (!task.active || task.phase == SyncPhase.cancelling) return;
    if (task.phase == SyncPhase.running) {
      task._phase = SyncPhase.cancelling;
      if (task.target.isSchool) {
        _school.cancel();
      } else {
        _mooc.cancel();
      }
    } else {
      _finish(task, SyncPhase.cancelled, '已取消');
    }
    if (!_disposed) notifyListeners();
    _schedule();
  }

  void cancelAll() {
    for (final task in _tasks) {
      cancel(task);
    }
  }

  void _changed() {
    if (_disposed) return;
    notifyListeners();
    _schedule();
  }

  void _schedule() {
    if (_disposed || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_disposed) return;
      for (final school in [true, false]) {
        final lane = _tasks.where((task) => task.target.isSchool == school);
        if (lane.any(
          (task) =>
              task.phase == SyncPhase.running ||
              task.phase == SyncPhase.cancelling,
        )) {
          continue;
        }
        if (school ? _school.busy : _mooc.busy) continue;
        final blocked = lane
            .where((task) => task.phase == SyncPhase.attention)
            .firstOrNull;
        if (blocked != null) continue;
        final task = lane
            .where((task) => task.phase == SyncPhase.queued)
            .firstOrNull;
        if (task == null) continue;
        final needsLogin = school
            ? _school.username == null || _school.loginExpired
            : _mooc.needsLogin;
        if (needsLogin || (school && _school.verificationRequired)) {
          _finish(
            task,
            SyncPhase.attention,
            school && _school.verificationRequired
                ? _school.accountStatus.label
                : '需要登录',
          );
          notifyListeners();
          continue;
        }
        unawaited(_run(task));
      }
    });
  }

  Future<void> _run(SyncTask task) async {
    task._phase = SyncPhase.running;
    notifyListeners();
    try {
      if (task.target == SyncTarget.mooc) {
        final result = await _mooc.synchronize();
        if (task.phase != SyncPhase.cancelling) {
          final summary = result == null
              ? _mooc.error ?? '未能保存同步结果'
              : [
                  '已同步 ${result.entries.length} 条 DDL',
                  for (final failure in result.failures)
                    '${failure.course}：${failure.message}',
                ].join('\n');
          _finish(
            task,
            result != null && result.failures.isEmpty
                ? SyncPhase.completed
                : SyncPhase.failed,
            summary,
          );
        }
      } else {
        final success = await switch (task.target) {
          SyncTarget.schedule => _school.synchronize(term: task.term),
          SyncTarget.exams => _school.importExams(term: task.term),
          SyncTarget.grades => _school.importGrades(),
          SyncTarget.studyPlan => _school.importStudyPlan(),
          SyncTarget.lexue || SyncTarget.eclass => _school.importDeadlines(
            source: task.target.source,
          ),
          SyncTarget.mooc => throw StateError('MOOC 使用独立账号'),
        };
        if (task.phase != SyncPhase.cancelling) {
          final needsAction =
              _school.verificationRequired ||
              _school.loginExpired ||
              _school.username == null;
          _finish(
            task,
            success
                ? SyncPhase.completed
                : needsAction
                ? SyncPhase.attention
                : SyncPhase.failed,
            success ? '已同步' : _school.error ?? '同步未完成，请重试',
          );
        }
      }
    } on RequestCancelled {
      _finish(task, SyncPhase.cancelled, '已取消');
    } on Exception {
      if (task.phase != SyncPhase.cancelling) {
        _finish(
          task,
          _mooc.needsLogin && !task.target.isSchool
              ? SyncPhase.attention
              : SyncPhase.failed,
          task.target.isSchool
              ? _school.error ?? '同步失败，请重试'
              : _mooc.error ?? '同步失败，请重试',
        );
      }
    } finally {
      if (task.phase == SyncPhase.cancelling) {
        _finish(task, SyncPhase.cancelled, '已取消');
      }
      if (!_disposed) {
        notifyListeners();
        _schedule();
      }
    }
  }

  void _finish(SyncTask task, SyncPhase phase, String message) {
    task._phase = phase;
    task._message = message;
    if (!task._finished.isCompleted) {
      task._finished.complete(phase == SyncPhase.completed);
    }
  }

  /// Retry an attention item after explicit authentication, without duplicating it.
  SyncTask retry(SyncTask task) {
    assert(
      task.phase != SyncPhase.running && task.phase != SyncPhase.cancelling,
    );
    _tasks.remove(task);
    return enqueue(task.target, term: task.term);
  }

  @override
  void dispose() {
    _disposed = true;
    _school.removeListener(_changed);
    _mooc.removeListener(_changed);
    cancelAll();
    super.dispose();
  }
}
