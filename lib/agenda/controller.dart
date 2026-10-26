import 'package:flutter/foundation.dart';

import '../data/agenda_store.dart';
import '../diagnostics.dart';
import 'model.dart';

class AgendaController extends ChangeNotifier {
  AgendaController(this._store);

  final AgendaStore _store;
  List<AgendaEntry> _entries = const [];
  bool ready = false;
  bool busy = false;

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
    if (busy) return;
    busy = true;
    ready = false;
    notifyListeners();
    try {
      _entries = List.unmodifiable(await _store.read());
      ready = true;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('读取日程', failure, stack);
    } finally {
      busy = false;
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

  Future<bool> _write(List<AgendaEntry> next) async {
    if (!ready || busy) {
      AppDiagnostics.instance.notice(
        busy ? '日程正在保存，请稍后重试。' : '日程尚未加载，请先重新加载日程。',
      );
      return false;
    }
    busy = true;
    notifyListeners();
    try {
      await _store.write(next);
      _entries = List.unmodifiable(next);
      return true;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('保存日程', failure, stack);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
