import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bitree/agenda/deadline_source.dart';
import 'package:bitree/school/crypto.dart';
import 'package:bitree/school/errors.dart';
import 'package:bitree/school/login.dart';
import 'package:bitree/school/network.dart';
import 'package:bitree/school/session.dart';
import 'package:bitree/school/storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/school_network.dart';
import 'support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final lexue = DeadlineSource.lexue;
  final sso = Uri.https('sso.bit.edu.cn', '/cas/login', {
    'service': '${lexue.loginPage}',
  });
  const cryptoKey = 'AAECAwQFBgcICQoLDA0ODw==';
  late HttpServer server;
  late StreamIterator<HttpRequest> incoming;
  late LocalSchoolNetwork network;
  late MemorySchoolStorage storage;
  late SchoolSession session;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    incoming = StreamIterator(server);
    network = LocalSchoolNetwork(server.port);
    storage = MemorySchoolStorage(
      credentials: const SchoolCredentials(
        username: 'student',
        password: 'test',
      ),
    );
  });

  tearDown(() async {
    session.close();
    await incoming.cancel();
    await server.close(force: true);
  });

  SchoolLogin login() {
    session = SchoolSession(network: SchoolNetwork.campus, storage: storage);
    return SchoolLogin(
      session,
      (_) async => throw StateError('No verification should open in this test'),
    );
  }

  Future<HttpRequest> nextRequest() async {
    expect(await incoming.moveNext(), isTrue);
    return incoming.current;
  }

  Future<void> reply(
    HttpRequest request, {
    int status = 200,
    String body = '',
    Uri? location,
  }) async {
    request.response.statusCode = status;
    if (location != null) {
      request.response.headers.set(HttpHeaders.locationHeader, '$location');
    }
    request.response.write(body);
    await request.response.close();
  }

  Future<HttpRequest> passwordPost({String action = ''}) async {
    final entry = await nextRequest();
    expect(entry.uri.path, '/lexue.bit.edu.cn/login/index.php');
    entry.response.cookies.add(
      Cookie('MoodleSession', 'bootstrap')..path = '/',
    );
    await reply(
      entry,
      status: 302,
      location: Uri.https('login.bit.edu.cn', '/authserver/login', {
        'service': '${lexue.loginPage}',
      }),
    );
    final legacyEntry = await nextRequest();
    expect(legacyEntry.uri.path, '/login.bit.edu.cn/authserver/login');
    await reply(legacyEntry, status: 302, location: sso);
    final page = await nextRequest();
    expect(page.uri.path, '/sso.bit.edu.cn/cas/login');
    await reply(
      page,
      body:
          '''
      <p id="login-page-flowkey">password-flow</p>
      <p id="login-croypto">$cryptoKey</p>
      <p id="riskSystemSwitch">USTC</p>
      <p id="targetSystem">sso</p>
      <p id="siteId">sourceId</p>
      <form method="post" $action></form>
    ''',
    );
    final captcha = await nextRequest();
    expect(captcha.uri.path, endsWith('/findCaptchaCount/student'));
    await reply(captcha, body: '{"data":{"captchaInvisible":false}}');
    final risk = await nextRequest();
    expect(risk.uri.path, '/sso.bit.edu.cn/ustc-rba-front/fp');
    await reply(risk, body: '{"responsetoken":"risk-token"}');
    final password = await nextRequest();
    expect(password.method, 'POST');
    expect(password.uri.path, '/sso.bit.edu.cn/cas/login');
    return password;
  }

  for (final action in ['', 'action=""']) {
    test(
      'A login form with ${action.isEmpty ? 'no' : 'an empty'} action keeps its service',
      () => HttpOverrides.runWithHttpOverrides(() async {
        final result = login().openLearningPlatform(lexue);
        final expectation = expectLater(
          result,
          completion(
            isA<SchoolResponse>().having(
              (page) => page.url.host,
              'host',
              lexue.host,
            ),
          ),
        );
        final password = await passwordPost(action: action);
        expect(password.uri.queryParameters['service'], '${lexue.loginPage}');
        final form = Uri.splitQueryString(
          await utf8.decoder.bind(password).join(),
        );
        expect(form['execution'], 'password-flow');
        expect(form['username'], 'student');
        expect(
          decryptSchoolValue(form['password']!, base64Decode(cryptoKey)),
          'test',
        );
        await reply(
          password,
          status: 302,
          location: lexue.loginPage.replace(
            queryParameters: {'ticket': 'test'},
          ),
        );
        final callback = await nextRequest();
        expect(callback.uri.path, '/lexue.bit.edu.cn/login/index.php');
        expect(
          callback.headers.value(HttpHeaders.cookieHeader),
          contains('MoodleSession=bootstrap'),
        );
        await reply(
          callback,
          body: '<script>M.cfg={"sesskey":"signed-in"};</script>',
        );
        await expectation;
      }, network),
    );
  }

  for (final source in [DeadlineSource.lexue, DeadlineSource.eclass]) {
    test(
      '${source.label} reuses its authenticated session without asking for credentials',
      () => HttpOverrides.runWithHttpOverrides(() async {
        storage.credentials = null;
        await storage.saveCookies(SchoolNetwork.campus, source.origin, [
          Cookie('session', 'signed-in')..path = '/',
        ]);
        final result = login().openLearningPlatform(source);
        final expectation = expectLater(result, completes);
        final request = await nextRequest();
        expect(request.uri.path, '/${source.host}${source.loginPage.path}');
        expect(
          request.headers.value(HttpHeaders.cookieHeader),
          contains('session=signed-in'),
        );
        await reply(
          request,
          body: '<script>M.cfg={"sesskey":"signed-in"};</script>',
        );
        await expectation;
      }, network),
    );
  }

  for (final marker in [
    '<div id="second-auth-tip">请验证绑定手机</div>',
    '<form id="secondSmsLoginForm"></form>',
    '<div class="cas-gateway"></div>',
  ]) {
    test(
      'A secondary verification page starts its phone lookup: $marker',
      () => HttpOverrides.runWithHttpOverrides(() async {
        final result = login().openLearningPlatform(lexue);
        final expectation = expectLater(
          result,
          throwsA(
            isA<SchoolConnectionError>().having(
              (failure) => failure.url.path,
              'failed endpoint',
              '/cas/api/protected/sms/getPhoneNumberByUserId',
            ),
          ),
        );
        final password = await passwordPost();
        await reply(
          password,
          body:
              '''
            <p id="login-page-flowkey">sms-flow</p>
            <p id="user-object-id">test-user-object</p>
            $marker
          ''',
        );
        final phone = await nextRequest();
        expect(phone.method, 'POST');
        expect(
          phone.uri.path,
          '/sso.bit.edu.cn/cas/api/protected/sms/getPhoneNumberByUserId',
        );
        // Keep this test at the secondary-auth boundary; no real SMS is sent.
        await reply(phone, status: 503);
        await expectation;
      }, network),
    );
  }

  test(
    'Rejected credentials keep the school login error',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final result = login().openLearningPlatform(lexue);
      final expectation = expectLater(
        result,
        throwsA(
          isA<SchoolCredentialsRequired>().having(
            (failure) => failure.message,
            'message',
            '账号或密码错误',
          ),
        ),
      );
      final password = await passwordPost();
      await reply(
        password,
        status: 401,
        body: '''
          <p id="login-error-code">1030027</p>
          <p id="login-error-msg">认证信息无效</p>
        ''',
      );
      await expectation;
    }, network),
  );
}
