import 'dart:async';

import 'package:flutter/foundation.dart';

import '../agenda/controller.dart';
import '../core/async/cancelable_request.dart';
import '../core/diagnostics.dart';
import 'api.dart';
import 'credentials.dart';
import 'storage.dart';

class MoocController extends ChangeNotifier {
  MoocController({required this._storage, required this._agenda});

  final MoocStorage _storage;
  final AgendaController _agenda;
  MoocAccount? _account;
  CancellationToken? _request;
  Future<void>? _finished;
  bool _disposed = false;
  bool _expired = false;
  String? _error;
  String _progress = '';

  MoocAccount? get account => _account;
  bool get busy => _request != null;
  bool get needsLogin => _account == null || _expired;
  String? get error => _error;
  String get progress => _progress;
  String get status => _expired
      ? '需要重新登录'
      : _account == null
      ? '未登录'
      : '已连接';

  Future<void> load() async {
    try {
      _account = await _storage.read();
    } catch (error, stack) {
      _error = '无法读取 MOOC 登录信息，请重新登录。';
      AppDiagnostics.instance.error('读取 MOOC 账号', error, stack);
    }
    _notify();
  }

  Future<void> connect(MoocCredentials credentials) =>
      _run('登录 MOOC', credentials, (api, token) async {
        final account = await api.member();
        token.check();
        await _storage.write(account);
        _account = account;
        _expired = false;
      });

  Future<MoocImportResult?> synchronize() async {
    final account = _account;
    if (account == null) throw const MoocLoginRequired();
    return _run('更新 MOOC DDL', account.credentials, (api, token) async {
      final verified = await api.member();
      if (verified.id != account.id) throw const MoocLoginRequired();
      final result = await api.readDeadlines(account.id, (message) {
        _progress = message;
        _notify();
      });
      token.check();
      final next = MoocAccount(
        id: verified.id,
        name: verified.name,
        credentials: await api.credentials(),
      );
      token.check();
      await _storage.write(next);
      token.check();
      if (!await _agenda.mergeDeadlines(result.entries)) return null;
      _account = next;
      _expired = false;
      return result;
    });
  }

  Future<T> _run<T>(
    String label,
    MoocCredentials credentials,
    Future<T> Function(MoocApi, CancellationToken) operation,
  ) async {
    if (busy || _disposed) throw const MoocFailure('MOOC 正在处理请求，请稍后重试。');
    final token = CancellationToken();
    final finished = Completer<void>();
    _request = token;
    _finished = finished.future;
    _error = null;
    _progress = label == '登录 MOOC' ? '正在验证登录…' : '正在读取课程…';
    _notify();
    final api = MoocApi(credentials, token);
    try {
      return await operation(api, token);
    } on RequestCancelled {
      rethrow;
    } catch (error, stack) {
      if (error is MoocLoginRequired) _expired = _account != null;
      _error = switch (error) {
        MoocFailure(:final message) => message,
        FormatException(:final message) => message,
        _ => '$label失败，请重试或查看日志。',
      };
      AppDiagnostics.instance.error(label, error, stack);
      rethrow;
    } finally {
      api.close();
      _request = null;
      _finished = null;
      _progress = '';
      finished.complete();
      _notify();
    }
  }

  void cancel() => _request?.cancel();

  Future<void> disconnect() async {
    final finished = _finished;
    cancel();
    await finished;
    await _storage.clear();
    _account = null;
    _expired = false;
    _error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}
