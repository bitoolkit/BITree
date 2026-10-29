import 'package:flutter/foundation.dart';

import '../core/diagnostics.dart';
import '../schedule/model.dart';
import 'deadline_clear_scope.dart';
import 'model.dart';
import 'physics_lab_deadlines.dart';
import 'store.dart';

class AgendaController extends ChangeNotifier {
  AgendaController(this._store);

  final AgendaStore _store;
  List<AgendaEntry> _entries = const [];
  bool _ready = false;
  bool _busy = false;

  bool get ready => _ready;
  bool get busy => _busy;

  Iterable<AgendaEntry> get entries =>
      _entries.where((entry) => !entry.deleted);

  Iterable<AgendaEntry> get deletedDeadlines =>
      _entries.where((entry) => entry.deleted);

  List<AgendaEntry> pendingOn(DateTime date, {required DateTime now}) =>
      entries
          .where((entry) => !entry.isFinished(now) && entry.occursOn(date))
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  Future<void> load() async {
    if (_busy) return;
    _busy = true;
    _ready = false;
    notifyListeners();
    try {
      _entries = List.unmodifiable(await _store.read());
      _ready = true;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('读取日程', failure, stack);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> save(AgendaEntry entry) =>
      _write([..._entries.where((item) => item.id != entry.id), entry]);

  Future<bool> restore(AgendaEntry entry) {
    final current =
        _entries.where((item) => item.id == entry.id).firstOrNull ?? entry;
    return save(current.copyWith(deleted: false));
  }

  Future<bool> delete(AgendaEntry entry) => _write([
    for (final item in _entries)
      if (item.id != entry.id)
        item
      else if (item.isDeadline)
        item.copyWith(deleted: true),
  ]);

  Future<bool> restoreDeletedDeadlines() =>
      _write([for (final entry in _entries) entry.copyWith(deleted: false)]);

  Future<bool> replaceExams(String term, List<AgendaEntry> exams) {
    final edited = {
      for (final entry in _entries)
        if (entry.kind == AgendaKind.exam && entry.term == term && entry.local)
          entry.id,
    };
    return _write([
      ..._entries.where(
        (entry) =>
            entry.kind != AgendaKind.exam || entry.term != term || entry.local,
      ),
      ...exams.where((entry) => !edited.contains(entry.id)),
    ]);
  }

  Future<bool> mergeDeadlines(List<AgendaEntry> incoming) {
    final entries = {for (final entry in _entries) entry.id: entry};
    for (final entry in incoming) {
      final saved = entries[entry.id];
      final next = saved?.local == true ? saved! : entry;
      entries[entry.id] = next.copyWith(
        done: entry.done || saved?.done == true,
        deleted: saved?.deleted ?? false,
      );
    }
    return _write(entries.values.toList());
  }

  int countDeadlines(DeadlineClearScope scope) =>
      _entries.where(scope.includes).length;

  Set<String> deadlineIdsIn(Iterable<DeadlineClearScope> scopes) {
    final selected = scopes.toSet();
    return {
      for (final entry in _entries)
        if (selected.any((scope) => scope.includes(entry))) entry.id,
    };
  }

  int countDeadlinesIn(Iterable<DeadlineClearScope> scopes) =>
      deadlineIdsIn(scopes).length;

  /// Delete selected origins in one write, never partially one group at a time.
  /// The dialog supplies the exact set it displayed before the final click.
  Future<bool> clearDeadlines(
    Iterable<DeadlineClearScope> scopes, {
    Set<String>? expectedIds,
  }) async {
    final ids = deadlineIdsIn(scopes);
    if (expectedIds != null && !setEquals(ids, expectedIds)) {
      AppDiagnostics.instance.notice('待删除的 DDL 已变化，请检查后重新确认。');
      return false;
    }
    if (ids.isEmpty) {
      return false;
    }
    return _write(
      _entries
          .where((entry) => !entry.isDeadline || !ids.contains(entry.id))
          .toList(),
    );
  }

  /// Refresh this semester's generated records, keeping edits and tombstones.
  /// Only new entries are auto-completed when already past due at import time.
  /// Returns the matched generated count, or null when persistence fails.
  Future<int?> updatePhysicsLabDeadlines(
    SemesterSchedule schedule, {
    DateTime? now,
  }) async {
    final importedAt = now ?? campusNow();
    final incoming = physicsLabDeadlines(schedule);
    final savedById = {for (final entry in _entries) entry.id: entry};
    final next = <String, AgendaEntry>{
      for (final entry in _entries)
        if (!isPhysicsLabDeadline(entry) ||
            entry.term != schedule.term ||
            entry.local ||
            entry.done ||
            entry.deleted)
          entry.id: entry,
    };
    for (final entry in incoming) {
      final saved = savedById[entry.id];
      next[entry.id] = saved?.local == true
          ? saved!
          : entry.copyWith(
              done: saved?.done ?? entry.dueAt.isBefore(importedAt),
              deleted: saved?.deleted ?? false,
            );
    }
    return await _write(next.values.toList()) ? incoming.length : null;
  }

  Future<bool> _write(List<AgendaEntry> next) async {
    if (!_ready || _busy) {
      AppDiagnostics.instance.notice(
        _busy ? '日程正在保存，请稍后重试。' : '日程尚未加载，请先重新加载日程。',
      );
      return false;
    }
    _busy = true;
    notifyListeners();
    try {
      await _store.write(next);
      _entries = List.unmodifiable(next);
      return true;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('保存日程', failure, stack);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
