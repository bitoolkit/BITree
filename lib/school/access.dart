import '../agenda/deadline_source.dart';
import '../core/async/cancelable_request.dart';
import '../core/diagnostics.dart';
import 'errors.dart';
import 'login.dart';
import 'network.dart';
import 'session.dart';
import 'storage.dart';
import 'verification.dart';

/// Owns authentication, network fallback and the active request's lifetime.
class SchoolAccess {
  SchoolAccess(this._storage);

  final SchoolStorage _storage;
  SchoolNetwork _network = SchoolNetwork.campus;
  SchoolSession? _session;

  Future<T> read<T>(
    VerifySchoolLogin verify,
    Future<T> Function(SchoolSession) operation, {
    CancellationToken? cancellation,
    Uri? service,
  }) async {
    cancellation?.check();
    final detach = cancellation?.onCancel(cancel);
    try {
      final result = await _run((session) async {
        if (service != null) {
          await SchoolLogin(session, verify).signInTo(service);
        }
        try {
          return await operation(session);
        } on SessionExpired {
          final login = SchoolLogin(session, verify);
          if (service == null) {
            await login.signIn();
          } else {
            await login.signInTo(service);
          }
          return operation(session);
        }
      });
      cancellation?.check();
      return result;
    } finally {
      detach?.call();
    }
  }

  Future<T> readLearningPlatform<T>(
    DeadlineSource source,
    VerifySchoolLogin verify,
    Future<T> Function(SchoolSession, SchoolResponse) operation,
  ) => _withSession(SchoolNetwork.campus, (session) async {
    final page = await SchoolLogin(
      session,
      verify,
    ).openLearningPlatform(source);
    return operation(session, page);
  });

  Future<void> signIn(
    SchoolCredentials credentials,
    VerifySchoolLogin verify, {
    DeadlineSource? source,
  }) {
    Future<void> authenticate(SchoolSession session) async {
      await _storage.clearSession(session.network);
      session.checkActive();
      final login = SchoolLogin(session, verify);
      if (source == null) {
        await login.signIn(credentials);
      } else {
        await login.openLearningPlatform(source, credentials: credentials);
      }
      session.checkActive();
      await _storage.saveCredentials(credentials);
    }

    return source == null
        ? _run(authenticate)
        : _withSession(SchoolNetwork.campus, authenticate);
  }

  Future<T> _run<T>(Future<T> Function(SchoolSession) operation) async {
    try {
      return await _withSession(_network, operation);
    } on SchoolConnectionError catch (failure) {
      if (_network != SchoolNetwork.campus ||
          SchoolNetwork.webvpn.route(failure.url) == failure.url) {
        rethrow;
      }

      // Retry once through WebVPN; don't repeat the failed campus route.
      AppDiagnostics.instance.info('教学中心直连失败，切换 WebVPN（${failure.url.host}）');
      _network = SchoolNetwork.webvpn;
      return _withSession(_network, operation);
    }
  }

  Future<T> _withSession<T>(
    SchoolNetwork network,
    Future<T> Function(SchoolSession) operation,
  ) async {
    final session = SchoolSession(network: network, storage: _storage);
    _session = session;
    try {
      final result = await operation(session);
      session.checkActive();
      return result;
    } catch (_) {
      session.checkActive();
      rethrow;
    } finally {
      session.close();
      _session = null;
    }
  }

  void cancel() => _session?.close();
}
