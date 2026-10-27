import 'dart:async';

import 'package:flutter/foundation.dart';

import '../academics/controller.dart';
import '../agenda/controller.dart';
import '../agenda/deadline_source.dart';
import '../core/async/cancelable_request.dart';
import '../core/diagnostics.dart';
import '../schedule/controller.dart';
import 'academics.dart';
import 'access.dart';
import 'errors.dart';
import 'learning/eclass_deadlines.dart';
import 'learning/lexue_deadlines.dart';
import 'network.dart';
import 'service.dart';
import 'session.dart';
import 'storage.dart';
import 'verification.dart';

enum AccountStatus { unverified, signedIn, signedOut, expired }

/// Runs school operations through one authenticated, cancellable session owner.
class SchoolController extends ChangeNotifier {
  SchoolController({
    required this._service,
    required SchoolStorage storage,
    required this._timetable,
    required this._agenda,
    required this._academics,
  }) : _storage = storage,
       _access = SchoolAccess(storage);

  final SchoolService _service;
  final SchoolStorage _storage;
  final SchoolAccess _access;
  final TimetableController _timetable;
  final AgendaController _agenda;
  final AcademicController _academics;
  AccountStatus _status = AccountStatus.unverified;
  String? _username;
  Future<void>? _finished;
  bool _disposed = false;

  AccountStatus get accountStatus => _status;
  String? get username => _username;
  bool get loginExpired => _status == AccountStatus.expired;
  bool get busy => _finished != null;

  Future<void> loadAccount() async {
    try {
      _username = (await _storage.readCredentials())?.username;
      if (_username == null) _status = AccountStatus.signedOut;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('读取学校账号', failure, stack);
    }
    if (!_disposed) notifyListeners();
  }

  void requireLogin() {
    final next = _username == null
        ? AccountStatus.signedOut
        : AccountStatus.expired;
    if (next == _status) return;
    _status = next;
    notifyListeners();
  }

  Future<bool> _run(String label, Future<bool> Function() operation) async {
    if (busy) {
      AppDiagnostics.instance.notice('正在处理学校请求，请稍后再试。');
      return false;
    }
    final finished = Completer<void>();
    _finished = finished.future;
    notifyListeners();
    AppDiagnostics.instance.info('开始$label');
    try {
      final success = await operation();
      if (success) {
        _status = _username == null
            ? AccountStatus.signedOut
            : AccountStatus.signedIn;
        AppDiagnostics.instance.info('$label完成');
      }
      return success;
    } on RequestCancelled {
      return false;
    } catch (failure, stack) {
      if (failure is SessionExpired || failure is SchoolCredentialsRequired) {
        requireLogin();
      }
      AppDiagnostics.instance.report(label, failure, stack);
      return false;
    } finally {
      _finished = null;
      finished.complete();
      if (!_disposed) notifyListeners();
    }
  }

  /// Failed or cancelled reads return null; diagnostics are reported once here.
  Future<T?> read<T>(
    String label,
    Future<T> Function(SchoolSession) operation, {
    required VerifySchoolLogin verify,
    CancellationToken? cancellation,
  }) async {
    T? result;
    final success = await _run(label, () async {
      result = await _access.read(
        verify,
        operation,
        cancellation: cancellation,
      );
      return true;
    });
    return success ? result : null;
  }

  Future<bool> signIn(
    SchoolCredentials credentials,
    VerifySchoolLogin verify, {
    DeadlineSource? source,
  }) => _run('登录学校账号', () async {
    await _access.signIn(credentials, verify, source: source);
    if (_username != credentials.username) _service.clearCache();
    _username = credentials.username;
    await _academics.load(_username);
    return true;
  });

  Future<bool> restoreAccount(VerifySchoolLogin verify) async {
    if (_username == null) return true;
    return _run('恢复学校登录', () async {
      await _access.read(verify, (session) => session.checkLogin());
      return true;
    });
  }

  Future<bool> synchronize({String? term, required VerifySchoolLogin verify}) =>
      _run(
        '同步课表',
        () => _access.read(verify, (session) async {
          final result = await _service.synchronize(
            session,
            account: _username!,
            term: term,
          );
          session.checkActive();
          return _timetable.importSchedule(result.schedule, result.terms);
        }),
      );

  Future<bool> importExams({String? term, required VerifySchoolLogin verify}) =>
      _run(
        '同步考试安排',
        () => _access.read(verify, (session) async {
          final result = await _service.exams(
            session,
            account: _username!,
            term: term ?? _timetable.schedule?.term,
          );
          session.checkActive();
          return _agenda.replaceExams(result.term, result.exams);
        }),
      );

  Future<bool> importGrades({required VerifySchoolLogin verify}) =>
      _run('同步成绩', () async {
        final grades = await _access.read(
          verify,
          fetchSchoolGrades,
          service: SchoolNetwork.recordsService,
        );
        return _academics.save(
          _academics.record.copyWith(
            grades: grades,
            gradesUpdatedAt: DateTime.now(),
          ),
        );
      });

  Future<bool> importStudyPlan({required VerifySchoolLogin verify}) =>
      _run('同步学分进度', () async {
        final plan = await _access.read(verify, fetchStudyPlan);
        return _academics.save(
          _academics.record.copyWith(plan: plan, planUpdatedAt: DateTime.now()),
        );
      });

  Future<bool> importDeadlines({required VerifySchoolLogin verify}) =>
      _run('同步 DDL', () async {
        var success = true;
        for (final source in DeadlineSource.values) {
          try {
            final saved = await _access.readLearningPlatform(source, verify, (
              session,
              page,
            ) async {
              final deadlines = await switch (source) {
                DeadlineSource.lexue => fetchLexueDeadlines(session, page),
                DeadlineSource.eclass => fetchEclassDeadlines(session),
              };
              session.checkActive();
              return _agenda.mergeDeadlines(deadlines);
            });
            success = saved && success;
          } on RequestCancelled {
            rethrow;
          } catch (failure, stack) {
            success = false;
            if (failure is SessionExpired ||
                failure is SchoolCredentialsRequired) {
              requireLogin();
            }
            AppDiagnostics.instance.report(
              '同步${source.label} DDL',
              failure,
              stack,
              message: '${source.label} DDL 同步失败，可稍后重试。',
            );
          }
        }
        return success;
      });

  void cancel() => _access.cancel();

  Future<bool> signOut() async {
    final finished = _finished;
    cancel();
    await finished;
    return _run('退出学校账号', () async {
      await _storage.clear();
      _service.clearCache();
      _username = null;
      await _academics.load(null);
      return true;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}
