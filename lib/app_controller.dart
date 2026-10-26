import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'agenda/controller.dart';
import 'agenda/deadline_source.dart';
import 'classrooms/model.dart';
import 'data/desktop_widget.dart';
import 'data/read_cache.dart';
import 'data/schedule_store.dart';
import 'data/school_access.dart';
import 'data/school_errors.dart';
import 'data/school_classrooms.dart';
import 'data/lexue_deadlines.dart';
import 'data/eclass_deadlines.dart';
import 'data/school_service.dart';
import 'data/school_session.dart';
import 'data/school_storage.dart';
import 'data/school_verification.dart';
import 'diagnostics.dart';
import 'schedule/model.dart';

enum AccountStatus { unverified, signedIn, signedOut, expired }

class AppController extends ChangeNotifier {
  AppController({
    required this._store,
    required this._school,
    required this._schoolStorage,
    required this._preferences,
    required this.agenda,
  }) {
    agenda.addListener(_agendaChanged);
  }

  final ScheduleStore _store;
  final SchoolService _school;
  final SchoolStorage _schoolStorage;
  late final _schoolAccess = SchoolAccess(_schoolStorage);
  final SharedPreferencesAsync _preferences;
  final AgendaController agenda;
  final _classroomDirectory = ReadCache<String, ClassroomDirectory?>(
    maxAge: const Duration(days: 1),
  );
  final _classroomOccupancy =
      ReadCache<
        ({String account, DateTime date, String buildings}),
        List<BuildingOccupancy>?
      >(maxAge: const Duration(minutes: 5));

  SemesterSchedule? _schedule;
  bool ready = false;
  bool busy = false;
  AccountStatus accountStatus = AccountStatus.unverified;
  String? username;
  Future<void>? _schoolFinished;

  int week = 1;
  ThemeMode themeMode = ThemeMode.system;
  bool confirmDelete = true;
  List<String> terms = [];

  SemesterSchedule? get schedule => _schedule;

  List<int> get weeks => schedule?.weeks ?? const [];

  bool get loginExpired => accountStatus == AccountStatus.expired;

  bool get schoolBusy => _schoolFinished != null;

  Future<void> initialize() async {
    try {
      _schedule = await _store.read();
      terms = await _store.terms();

      final theme = await _preferences.getString('theme');
      confirmDelete = await _preferences.getBool('confirmDelete') ?? true;
      themeMode =
          ThemeMode.values.where((value) => value.name == theme).firstOrNull ??
          ThemeMode.system;
      username = (await _schoolStorage.readCredentials())?.username;
      if (username == null) accountStatus = AccountStatus.signedOut;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('读取本地数据', failure, stack);
    }

    await agenda.load();
    _goToCurrentWeek();
    ready = true;
    notifyListeners();
  }

  @override
  void dispose() {
    agenda.removeListener(_agendaChanged);
    agenda.dispose();
    super.dispose();
  }

  void _agendaChanged() {
    final available = weeks;
    if (available.isNotEmpty) {
      week = week.clamp(available.first, available.last);
    }
    notifyListeners();
    if (agenda.ready && !agenda.busy) unawaited(_updateWidget());
  }

  void _goToCurrentWeek() {
    final available = weeks;
    final current = schedule?.weekAt(campusNow()) ?? 1;
    week = available.contains(current) ? current : 1;
  }

  void selectWeek(int value) {
    final available = weeks;
    week = value.clamp(available.firstOrNull ?? 1, available.lastOrNull ?? 20);
    notifyListeners();
  }

  void showCurrentWeek() {
    _goToCurrentWeek();
    notifyListeners();
  }

  void requireLogin() {
    final next = username == null
        ? AccountStatus.signedOut
        : AccountStatus.expired;
    if (next == accountStatus) return;

    accountStatus = next;
    notifyListeners();
  }

  void _handleSchoolError(String operation, Object failure, StackTrace stack) {
    if (failure is SessionExpired || failure is SchoolCredentialsRequired) {
      requireLogin();
    }
    AppDiagnostics.instance.report(operation, failure, stack);
  }

  Future<bool> _runSchool(
    String label,
    Future<bool> Function() operation,
  ) async {
    if (busy || schoolBusy) return false;

    final finished = Completer<void>();
    _schoolFinished = finished.future;
    notifyListeners();
    AppDiagnostics.instance.info('开始$label');

    try {
      final success = await operation();
      accountStatus = AccountStatus.signedIn;
      if (success) AppDiagnostics.instance.info('$label完成');
      return success;
    } on SchoolCancelled {
      return false;
    } catch (failure, stack) {
      _handleSchoolError(label, failure, stack);
      return false;
    } finally {
      _schoolFinished = null;
      finished.complete();
      notifyListeners();
    }
  }

  void cancelSchoolRequest() => _schoolAccess.cancel();

  Future<ClassroomDirectory?> classroomDirectory({
    required VerifySchoolLogin verify,
    bool refresh = false,
  }) async {
    Future<ClassroomDirectory?> load() =>
        _readSchool('加载教学楼', fetchClassroomDirectory, verify);

    final account = username;
    final result = account == null
        ? await load()
        : await _classroomDirectory.read(account, load, refresh: refresh);
    if (refresh && result != null) _classroomOccupancy.clear();
    return result;
  }

  Future<List<BuildingOccupancy>?> classroomOccupancy({
    required List<SchoolBuilding> buildings,
    required DateTime date,
    required VerifySchoolLogin verify,
    bool refresh = false,
  }) {
    final day = calendarDate(date);
    Future<List<BuildingOccupancy>?> load() => _readSchool(
      '查询空教室',
      (session) =>
          fetchClassroomOccupancy(session, buildings: buildings, date: day),
      verify,
    );

    final account = username;
    if (account == null) return load();
    final codes = buildings.map((building) => building.code).toList()..sort();
    return _classroomOccupancy.read(
      (account: account, date: day, buildings: jsonEncode(codes)),
      load,
      refresh: refresh,
    );
  }

  void _clearSchoolCache() {
    _classroomDirectory.clear();
    _classroomOccupancy.clear();
    _school.clearCache();
  }

  Future<T?> _readSchool<T>(
    String label,
    Future<T> Function(SchoolSession) read,
    VerifySchoolLogin verify,
  ) async {
    T? result;
    final success = await _runSchool(label, () async {
      result = await _schoolAccess.read(verify, read);
      return true;
    });
    return success ? result : null;
  }

  Future<bool> signIn(
    SchoolCredentials credentials,
    VerifySchoolLogin verify, {
    DeadlineSource? source,
  }) => _runSchool('登录学校账号', () async {
    await _schoolAccess.signIn(credentials, verify, source: source);
    if (username != credentials.username) _clearSchoolCache();
    username = credentials.username;
    return true;
  });

  Future<bool> restoreAccount(VerifySchoolLogin verify) async {
    if (username == null) return true;
    return _runSchool('恢复学校登录', () async {
      await _schoolAccess.read(verify, (session) => session.checkLogin());
      return true;
    });
  }

  Future<bool> synchronize({String? term, required VerifySchoolLogin verify}) =>
      _runSchool(
        '导入课表',
        () => _schoolAccess.read(verify, (session) async {
          final result = await _school.synchronize(
            session,
            account: username!,
            term: term,
          );

          if (busy) throw const SchoolRequestError('课程正在保存，请稍后重新导入。');
          busy = true;
          notifyListeners();
          try {
            final previous = await _store.readTerm(result.schedule.term);
            session.checkActive();
            final next = result.schedule.mergeLocalChanges(previous);
            await _store.write(next);
            _schedule = next;
            terms = {...await _store.terms(), ...result.terms}.toList();
            _goToCurrentWeek();
            await _updateWidget();
            return true;
          } finally {
            busy = false;
            notifyListeners();
          }
        }),
      );

  Future<bool> importExams({required VerifySchoolLogin verify}) => _runSchool(
    '获取考试安排',
    () => _schoolAccess.read(verify, (session) async {
      final result = await _school.exams(
        session,
        account: username!,
        term: schedule?.term,
      );
      session.checkActive();
      return agenda.replaceExams(result.term, result.exams);
    }),
  );

  Future<bool> importDeadlines(
    DeadlineSource source, {
    required VerifySchoolLogin verify,
  }) => _runSchool(
    '更新${source.label} DDL',
    () => _schoolAccess.readLearningPlatform(source, verify, (
      session,
      page,
    ) async {
      final deadlines = await switch (source) {
        DeadlineSource.lexue => fetchLexueDeadlines(session, page),
        DeadlineSource.eclass => fetchEclassDeadlines(session),
      };
      session.checkActive();
      return agenda.mergeDeadlines(deadlines);
    }),
  );

  Future<bool> saveCourse(
    Course course, {
    Course? replacing,
    SemesterSchedule? semester,
  }) async {
    final current = semester ?? _schedule;
    if (current == null || busy) return false;

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

  Future<bool> setWeekRange({required int first, required int last}) async {
    final current = schedule;
    if (current == null || busy) return false;
    return _save(current.copyWith(firstWeek: first, lastWeek: last));
  }

  Future<bool> selectTerm(
    String term, {
    required Future<bool> Function(String term) importTerm,
  }) async {
    if (busy) return false;

    try {
      final saved = await _store.readTerm(term);
      if (busy) return false;
      if (saved == null) return await importTerm(term);

      return await _save(saved);
    } catch (failure, stack) {
      AppDiagnostics.instance.report('切换学期', failure, stack);
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteCourse(Course course) async {
    if (_schedule == null || busy) return false;

    return _save(
      _schedule!.copyWith(
        courses: [..._schedule!.courses.where((item) => item.id != course.id)],
      ),
    );
  }

  Future<bool> _save(SemesterSchedule next) async {
    busy = true;
    notifyListeners();

    try {
      await _store.write(next);
      final changingTerm = _schedule?.term != next.term;
      _schedule = next;
      if (changingTerm) {
        _goToCurrentWeek();
      } else {
        final available = weeks;
        week = week.clamp(available.first, available.last);
      }
      terms = {...terms, next.term}.toList();
      await _updateWidget();
      return true;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('保存课表', failure, stack);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setTheme(ThemeMode value) async {
    try {
      await _preferences.setString('theme', value.name);
      themeMode = value;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('保存外观设置', failure, stack);
    }
    notifyListeners();
  }

  Future<void> setConfirmDelete(bool value) async {
    try {
      await _preferences.setBool('confirmDelete', value);
      confirmDelete = value;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('保存删除设置', failure, stack);
    }
    notifyListeners();
  }

  Future<bool> signOut() async {
    if (busy) return false;

    final finished = _schoolFinished;
    cancelSchoolRequest();
    await finished;
    busy = true;
    notifyListeners();

    try {
      await _schoolStorage.clear();
      _clearSchoolCache();
      username = null;
      accountStatus = AccountStatus.signedOut;
      return true;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('退出学校账号', failure, stack);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> clearSchedule() async {
    if (busy) return false;

    busy = true;
    notifyListeners();

    try {
      await _store.clear();
      _schedule = null;
      terms = [];
      _goToCurrentWeek();
      await _updateWidget();
      return true;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('删除本地课表', failure, stack);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _updateWidget() async {
    try {
      await updateDesktopWidget();
    } catch (failure, stack) {
      AppDiagnostics.instance.report('更新桌面组件', failure, stack);
    }
  }
}
