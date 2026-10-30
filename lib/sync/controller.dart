import 'dart:async';

import 'package:flutter/foundation.dart';

import '../agenda/controller.dart';
import '../agenda/deadline_source.dart';
import '../core/async/cancelable_request.dart';
import '../mooc/controller.dart';
import '../schedule/controller.dart';
import '../school/controller.dart';

enum SyncTarget {
  schedule('课表', '同步课表'),
  exams('考试安排', '同步考试安排'),
  grades('成绩', '同步成绩'),
  studyPlan('学分进度', '同步学分进度'),
  lexue('乐学 DDL', '同步乐学 DDL', DeadlineSource.lexue),
  eclass('新延河课堂 DDL', '同步新延河课堂 DDL', DeadlineSource.eclass),
  mooc('中国大学MOOC DDL', '同步中国大学MOOC DDL', DeadlineSource.mooc),
  physicsLab('大物实验 DDL', '更新大物实验 DDL');

  const SyncTarget(this.title, this.label, [this.source]);
  final String title;
  final String label;
  final DeadlineSource? source;
  bool get isSchool => this != mooc && this != physicsLab;
}

enum SyncStatus { synced, failed, needsAuthentication, cancelled }

typedef SyncResult = ({SyncStatus status, String message});

/// Owns one synchronization round. School reads share a session and run in
/// sequence; MOOC runs alongside them. There is no persistent task queue.
class SyncController extends ChangeNotifier {
  SyncController({
    required this._school,
    required this._mooc,
    required this._timetable,
    required this._agenda,
  }) {
    _school.addListener(_notify);
    _mooc.addListener(_notify);
  }
  final SchoolController _school;
  final MoocController _mooc;
  final TimetableController _timetable;
  final AgendaController _agenda;
  Future<bool>? _operation;
  Completer<void>? _cancelledSignal;
  bool _disposed = false;
  bool _cancelled = false;
  String? _term;
  List<SyncTarget> _targets = const [];
  final _results = <SyncTarget, SyncResult>{};
  final _running = <SyncTarget>{};

  bool get busy => _operation != null;
  bool get cancelled => _cancelled;
  String? get term => _term;
  List<SyncTarget> get targets => _targets;
  Map<SyncTarget, SyncResult> get results => Map.unmodifiable(_results);
  Set<SyncTarget> get defaultTargets => {
    for (final target in SyncTarget.values)
      if (target != SyncTarget.mooc || !_mooc.needsLogin) target,
  };
  Set<SyncTarget> get incompleteTargets => {
    for (final target in _targets)
      if (_results[target]?.status != SyncStatus.synced) target,
  };
  bool isRunning(SyncTarget target) => _running.contains(target);

  String progress(SyncTarget target) {
    if (_results[target] case final result?) return result.message;
    if (_running.contains(target)) {
      if (_cancelled) return '正在取消…';
      return target == SyncTarget.mooc ? _mooc.progress : '正在同步…';
    }
    return target.isSchool && _school.busy ? '等待学校请求完成' : '等待同步';
  }

  Future<bool> synchronize(Set<SyncTarget> selected, {String? term}) {
    if (_operation case final current?) return current;
    assert(!_disposed && selected.isNotEmpty);
    final finished = Completer<bool>();
    _operation = finished.future;
    _cancelledSignal = Completer<void>();
    _cancelled = false;
    _term = term;
    _targets = List.unmodifiable(SyncTarget.values.where(selected.contains));
    _results.clear();
    _notify();
    unawaited(_run().then(finished.complete, onError: finished.completeError));
    return finished.future;
  }

  Future<bool> _run() async {
    try {
      await Future.wait([
        _syncSchoolAndLab(_term),
        if (_targets.contains(SyncTarget.mooc)) _syncMooc(),
      ]);
      return !_cancelled && incompleteTargets.isEmpty;
    } finally {
      if (_cancelled) {
        for (final target in _targets) {
          _results.putIfAbsent(
            target,
            () => (status: SyncStatus.cancelled, message: '已取消'),
          );
        }
      }
      _operation = null;
      _cancelledSignal = null;
      _notify();
    }
  }

  Future<void> _syncSchoolAndLab(String? term) async {
    for (final target in _targets.where((target) => target.isSchool)) {
      while (_school.busy && !_cancelled) {
        await Future.any([_school.idle, _cancelledSignal!.future]);
      }
      if (_cancelled) break;
      if (_school.verificationRequired ||
          _school.loginExpired ||
          _school.username == null) {
        _results[target] = (
          status: SyncStatus.needsAuthentication,
          message: _school.verificationRequired
              ? _school.accountStatus.label
              : '需要登录学校账号',
        );
        _notify();
        continue;
      }
      _running.add(target);
      _notify();
      try {
        final success = await switch (target) {
          SyncTarget.schedule => _school.synchronize(term: term),
          SyncTarget.exams => _school.importExams(term: term),
          SyncTarget.grades => _school.importGrades(),
          SyncTarget.studyPlan => _school.importStudyPlan(),
          SyncTarget.lexue ||
          SyncTarget.eclass => _school.importDeadlines(source: target.source),
          _ => throw StateError('不是学校同步内容'),
        };
        final status = _cancelled
            ? SyncStatus.cancelled
            : success
            ? SyncStatus.synced
            : _school.verificationRequired || _school.loginExpired
            ? SyncStatus.needsAuthentication
            : SyncStatus.failed;
        _results[target] = (
          status: status,
          message: _cancelled
              ? '已取消'
              : success
              ? '已同步'
              : _school.error ?? '同步未完成，请重试',
        );
      } finally {
        _running.remove(target);
        _notify();
      }
    }
    if (!_cancelled && _targets.contains(SyncTarget.physicsLab)) {
      _running.add(SyncTarget.physicsLab);
      _notify();
      try {
        final schedule = _timetable.schedule;
        final count = schedule == null
            ? null
            : await _agenda.updatePhysicsLabDeadlines(
                schedule,
                checkActive: _checkActive,
              );
        _results[SyncTarget.physicsLab] = (
          status: count == null ? SyncStatus.failed : SyncStatus.synced,
          message: schedule == null
              ? '暂无可用课表'
              : count == null
              ? '未能保存大物实验 DDL'
              : '已更新 $count 条 DDL',
        );
      } on RequestCancelled {
        // The round records cancelled content after all running reads stop.
      } finally {
        _running.remove(SyncTarget.physicsLab);
        _notify();
      }
    }
  }

  Future<void> _syncMooc() async {
    _running.add(SyncTarget.mooc);
    _notify();
    try {
      final result = await _mooc.synchronize();
      if (!_cancelled) {
        _results[SyncTarget.mooc] = (
          status: result != null && result.failures.isEmpty
              ? SyncStatus.synced
              : SyncStatus.failed,
          message: result == null
              ? _mooc.error ?? '未能保存同步结果'
              : [
                  '已同步 ${result.entries.length} 条 DDL',
                  for (final failure in result.failures)
                    '${failure.course}：${failure.message}',
                ].join('\n'),
        );
      }
    } on RequestCancelled {
      cancel();
    } on Exception {
      if (!_cancelled) {
        _results[SyncTarget.mooc] = (
          status: _mooc.needsLogin
              ? SyncStatus.needsAuthentication
              : SyncStatus.failed,
          message: _mooc.error ?? '同步失败，请重试',
        );
      }
    } finally {
      _running.remove(SyncTarget.mooc);
      _notify();
    }
  }

  void _checkActive() {
    if (_cancelled) throw const RequestCancelled();
  }

  void cancel() {
    if (!busy || _cancelled) return;
    _cancelled = true;
    _cancelledSignal!.complete();
    if (_running.any((target) => target.isSchool)) _school.cancel();
    if (_running.contains(SyncTarget.mooc)) _mooc.cancel();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _school.removeListener(_notify);
    _mooc.removeListener(_notify);
    cancel();
    super.dispose();
  }
}
