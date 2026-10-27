import 'package:flutter/foundation.dart';

import '../core/diagnostics.dart';
import 'model.dart';
import 'store.dart';

/// Owns saved semesters and the week currently being viewed.
class TimetableController extends ChangeNotifier {
  TimetableController(this._store);

  final ScheduleStore _store;
  final _schedules = <String, SemesterSchedule>{};
  String? _selectedTerm;
  List<String> _terms = const [];
  int _week = 1;
  bool _ready = false;
  bool _busy = false;

  bool get ready => _ready;
  bool get busy => _busy;
  int get week => _week;
  List<String> get terms => _terms;
  SemesterSchedule? get schedule => _schedules[_selectedTerm];
  Iterable<SemesterSchedule> get schedules => _schedules.values;
  List<int> get weeks => schedule?.weeks ?? const [];

  Future<void> load() async {
    try {
      final library = await _store.read();
      _schedules
        ..clear()
        ..addAll(library.schedules);
      _selectedTerm = library.selectedTerm;
      _terms = List.unmodifiable(_schedules.keys);
      _ready = true;
      _goToCurrentWeek();
    } catch (failure, stack) {
      AppDiagnostics.instance.report('读取本地课表', failure, stack);
    }
    notifyListeners();
  }

  void _goToCurrentWeek() {
    final current = schedule?.weekAt(campusNow()) ?? 1;
    _week = weeks.contains(current) ? current : weeks.firstOrNull ?? 1;
  }

  void selectWeek(int value) {
    final next = value.clamp(weeks.firstOrNull ?? 1, weeks.lastOrNull ?? 1);
    if (_week == next) return;
    _week = next;
    notifyListeners();
  }

  void showCurrentWeek() {
    _goToCurrentWeek();
    notifyListeners();
  }

  Future<bool> importSchedule(
    SemesterSchedule incoming,
    List<String> availableTerms,
  ) => _save(
    incoming.mergeLocalChanges(_schedules[incoming.term]),
    availableTerms: availableTerms,
    resetWeek: true,
  );

  Future<bool> saveCourse(
    Course course, {
    Course? replacing,
    SemesterSchedule? semester,
  }) async {
    final current = semester ?? schedule;
    if (current == null) return false;
    return _save(
      current.copyWith(
        courses: [
          ...current.courses.where(
            (item) => item.id != course.id && item.id != replacing?.id,
          ),
          course,
        ],
      ),
    );
  }

  Future<bool> deleteCourse(Course course) async {
    final current = schedule;
    if (current == null) return false;
    return _save(
      current.copyWith(
        courses: [...current.courses.where((item) => item.id != course.id)],
      ),
    );
  }

  Future<bool> setWeekRange({required int first, required int last}) async {
    final current = schedule;
    if (current == null) return false;
    return _save(current.copyWith(firstWeek: first, lastWeek: last));
  }

  Future<bool> selectTerm(
    String term, {
    required Future<bool> Function(String term) importTerm,
  }) async {
    if (_busy) return false;
    final saved = _schedules[term];
    return saved == null ? importTerm(term) : _save(saved);
  }

  Future<bool> _save(
    SemesterSchedule next, {
    List<String> availableTerms = const [],
    bool resetWeek = false,
  }) async {
    if (_busy) return false;
    _busy = true;
    notifyListeners();
    try {
      await _store.write(next);
      final changingTerm = _selectedTerm != next.term;
      _schedules[next.term] = next;
      _selectedTerm = next.term;
      _terms = List.unmodifiable({..._terms, ...availableTerms, next.term});
      if (changingTerm || resetWeek) {
        _goToCurrentWeek();
      } else {
        _week = _week.clamp(weeks.first, weeks.last);
      }
      return true;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('保存课表', failure, stack);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> clear() async {
    if (_busy) return false;
    _busy = true;
    notifyListeners();
    try {
      await _store.clear();
      _schedules.clear();
      _selectedTerm = null;
      _terms = const [];
      _week = 1;
      return true;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('删除本地课表', failure, stack);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
