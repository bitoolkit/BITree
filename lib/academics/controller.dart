import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/academic_store.dart';
import '../diagnostics.dart';
import 'model.dart';

class AcademicController extends ChangeNotifier {
  AcademicController(this._store);

  final AcademicStore _store;
  String? _account;
  AcademicRecord _record = const AcademicRecord();
  bool ready = false;
  bool busy = false;
  Completer<void>? _writeFinished;

  AcademicRecord get record => _record;

  Future<void> load(String? account) async {
    await _writeFinished?.future;
    _account = account;
    _record = const AcademicRecord();
    ready = false;
    try {
      if (account != null) _record = await _store.read(account);
      ready = true;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('读取学业数据', failure, stack);
    }
    notifyListeners();
  }

  Future<bool> save(AcademicRecord next) async {
    if (busy || !ready || _account == null) {
      AppDiagnostics.instance.notice(
        busy ? '学业数据正在保存，请稍后重试。' : '请先登录并重新读取学业数据。',
      );
      return false;
    }
    final finished = Completer<void>();
    _writeFinished = finished;
    busy = true;
    notifyListeners();
    try {
      await _store.write(_account!, next);
      _record = next;
      return true;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('保存学业数据', failure, stack);
      return false;
    } finally {
      busy = false;
      _writeFinished = null;
      finished.complete();
      notifyListeners();
    }
  }
}
