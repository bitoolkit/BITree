import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart';

import '../agenda/deadline_source.dart';
import 'cancelable_request.dart';
import 'school_crypto.dart';
import 'school_errors.dart';
import 'school_network.dart';
import 'school_session.dart';
import 'school_storage.dart';
import 'school_verification.dart';

/// The school's CAS protocol, also implemented by BIT101-dev/BIT-Login.
class SchoolLogin {
  SchoolLogin(this.session, this.verify);

  final SchoolSession session;
  final VerifySchoolLogin verify;
  static final _sso = Uri.https('sso.bit.edu.cn');
  Uri _referer = _sso.resolve('/cas/login');

  Future<SchoolCredentials> _credentials(SchoolCredentials? provided) async {
    final account = provided ?? await session.storage.readCredentials();
    if (account == null) throw const SchoolCredentialsRequired();
    return account;
  }

  Future<SchoolResponse> openLearningPlatform(
    DeadlineSource source, {
    SchoolCredentials? credentials,
  }) async {
    var service = source.loginPage;
    if (source == DeadlineSource.eclass) {
      final response = await session.request(service);
      if (!isSchoolLogin(response.url)) return response;
      service = Uri.parse(response.url.queryParameters['service']!);
    }
    final account = await _credentials(credentials);
    final callback = await _authenticate(account, service);
    return _openCallback(callback);
  }

  Future<void> signIn([SchoolCredentials? credentials]) async {
    final account = await _credentials(credentials);
    if (session.network == SchoolNetwork.webvpn) {
      await _prepareWebVpn();
      final vpnCallback = await _authenticate(account, SchoolNetwork.vpnLogin);
      await _openCallback(vpnCallback);
    }

    // The public entry supplies the CAS service; the VPN proxy rewrites it.
    final preflight = await session.request(
      SchoolNetwork.teachingLogin,
      followRedirects: false,
      anonymous: true,
    );
    final service = preflight.location!.queryParameters['service']!;
    final callback = await _authenticate(account, Uri.parse(service));
    await _openCallback(callback);
    try {
      await session.checkLogin();
    } on SessionExpired {
      throw SchoolConnectionError(
        session.network.accountPage,
        const SchoolRequestError('未能建立学校登录会话，请重试。'),
      );
    }
  }

  Future<void> _prepareWebVpn() async {
    final response = await session.request(SchoolNetwork.vpnLogin);
    if (response.url.path != '/fingerprint') return;

    // The gateway binds its session cookie to a stable client identifier.
    final fingerprint = schoolSha256(await _device()).substring(0, 32);
    await session.request(
      response.url
          .resolve('/set-fingerprint')
          .replace(
            queryParameters: {
              ...response.url.queryParameters,
              'fingerprint': fingerprint,
            },
          ),
      headers: {'Referer': response.url.toString()},
    );
  }

  Future<SchoolResponse> _openCallback(Uri callback) => session.request(
    session.network.route(callback),
    headers: {'Referer': _referer.toString()},
  );

  Future<Uri> _authenticate(SchoolCredentials credentials, Uri service) async {
    final pageResponse = await _request(
      _sso
          .resolve('/cas/login')
          .replace(queryParameters: {'service': service.toString()}),
      followRedirects: false,
    );
    if (pageResponse.location != null) return _callback(pageResponse);
    final page = _LoginPage(pageResponse);
    _referer = pageResponse.url;

    final captchaInfo = await _json(
      '/cas/api/protected/user/findCaptchaCount/${Uri.encodeComponent(credentials.username)}',
    );
    var captcha = captchaInfo['data'] as Map<String, dynamic>;
    Future<Uint8List> loadCaptcha() async {
      final result = await _json(
        '/cas/api/protected/user/findCaptchaCount/${Uri.encodeComponent(credentials.username)}',
      );
      captcha = result['data'] as Map<String, dynamic>;
      return _captchaImage(captcha);
    }

    final captchaRequired = captcha['captchaInvisible'] == true;
    final captchaCode = captchaRequired
        ? await verify(
            SchoolImageVerification(
              image: await _captchaImage(captcha),
              reload: loadCaptcha,
            ),
          )
        : '';
    if (captchaCode == null) throw const RequestCancelled();
    session.checkActive();

    final key = base64Decode(page.cryptoKey);
    final form = {
      'type': 'UsernamePassword',
      '_eventId': 'submit',
      'geolocation': '',
      'execution': page.execution,
      'username': credentials.username,
      'croypto': page.cryptoKey,
      'password': encryptSchoolValue(credentials.password, key),
      'captcha_code': captchaCode,
      'captcha_payload': encryptSchoolValue(
        jsonEncode(captcha['captchaPayload'] ?? {}),
        key,
      ),
    };
    if (page.field('riskSystemSwitch').toUpperCase() == 'USTC') {
      form.addAll({
        'risk_payload': encryptSchoolValue(
          jsonEncode(await _riskPayload()),
          key,
        ),
        'targetSystem': page.field('targetSystem').isEmpty
            ? 'sso'
            : page.field('targetSystem'),
        'siteId': page.field('siteId').isEmpty
            ? 'sourceId'
            : page.field('siteId'),
        'riskEngine': 'true',
      });
    }
    final response = await _request(
      page.action,
      form: form,
      followRedirects: false,
      checkStatus: false,
    );
    final secondFactor = _LoginPage(response);
    if (secondFactor.field('user-object-id').isNotEmpty &&
        (response.text.contains('secondSmsLoginForm') ||
            response.text.contains('cas-gateway'))) {
      return _secondFactor(credentials.username, secondFactor);
    }
    return _callback(response);
  }

  Future<Uri> _secondFactor(String username, _LoginPage page) async {
    _referer = _sso.resolve('/cas/');
    final key = schoolRandomBytes(16);
    final encrypted = await _request(
      _sso.resolve('/cas/api/protected/sms/getPhoneNumberByUserId'),
      body: encryptSchoolValue(
        jsonEncode({'userId': page.field('user-object-id')}),
        key,
      ),
      headers: {'hasCrypto': 'true', 'privateKey': encryptSchoolKey(key)},
    );
    final data =
        (jsonDecode(decryptSchoolValue(encrypted.text, key)) as Map)['data']
            as Map;
    final phoneId = data['tel'] as String;
    final maskedPhone = data['maskTel'] as String;
    final code = await verify(
      SchoolSmsVerification(
        phone: maskedPhone,
        sendCode: () async {
          final result = await _json(
            '/cas/api/protected/sms/publicNoToken/sendSmsCode',
            body: {'phone': phoneId, 'businessNo': '0008'},
          );
          final message = _message(result);
          if (result['code'] != 200 &&
              !(message.contains('验证码') &&
                  message.contains('有效期内') &&
                  message.contains('重复发送'))) {
            throw SchoolRequestError(
              message.isEmpty ? '验证码发送失败，请重试。' : message,
            );
          }
        },
        checkCode: (code) async {
          final result = await _json(
            '/cas/api/protected/sms/checkToken',
            body: {
              'phone': phoneId,
              'token': code,
              'delete': false,
              'trustDevice': true,
            },
          );
          if (result['code'] != 200) {
            throw SchoolRequestError(
              _message(result).isEmpty ? '验证码错误或已失效。' : _message(result),
            );
          }
        },
      ),
    );
    if (code == null) throw const RequestCancelled();
    session.checkActive();
    return _callback(
      await _request(
        page.action,
        form: {
          'username': username,
          'password': code,
          'type': 'smsLogin',
          '_eventId': 'submit',
          'geolocation': '',
          'execution': page.execution,
          'captcha_code': '',
          'trustDevice': 'true',
        },
        followRedirects: false,
        checkStatus: false,
      ),
    );
  }

  Uri _callback(SchoolResponse response) {
    if (response.location != null &&
        response.status >= 300 &&
        response.status < 400) {
      return response.location!;
    }
    final page = _LoginPage(response);
    final code = page.field('login-error-code');
    final message = switch (code) {
      '1030027' || '1030031' => '账号或密码错误',
      '1030028' => '账号已被锁定，请先在学校统一身份认证平台解锁。',
      '1320007' || '1320010' => '验证码错误或已失效，请重试。',
      '1330001' => '学校要求进一步验证，请稍后重试。',
      '1410040' || '1410041' => '学校账号状态异常，请联系学校处理。',
      '3910001' => '账号已休眠，请先在学校统一身份认证平台激活。',
      _ => page.field('login-error-msg'),
    };
    if (code == '1030027' || code == '1030031') {
      throw SchoolCredentialsRequired(message);
    }
    if (response.status == 429) throw const SchoolRequestError('登录过于频繁，请稍后重试。');
    if (response.status >= 500) {
      throw SchoolRequestError(
        '认证请求失败（${response.status}）：'
        '${response.url.host}${response.url.path}',
      );
    }
    throw SchoolRequestError(message.isEmpty ? '学校未完成登录，请重试。' : message);
  }

  Future<Uint8List> _captchaImage(Map<String, dynamic> captcha) async {
    final url = captcha['captchaUrl'] as String;
    if (url.startsWith('data:')) return UriData.parse(url).contentAsBytes();
    return (await _request(_sso.resolve('/cas/').resolve(url))).bytes;
  }

  Future<String> _device() async {
    final cookies = await session.storage.cookiesFor(session.network, _sso);
    var device = cookies
        .where((cookie) => cookie.name == 'device')
        .firstOrNull
        ?.value;
    if (device == null) {
      device = schoolSha256(base64Encode(schoolRandomBytes(32)));
      await session.storage.saveCookies(session.network, _sso, [
        Cookie('device', device)
          ..path = '/'
          ..secure = true,
      ]);
    }
    return device;
  }

  Future<Map<String, dynamic>> _riskPayload() async {
    final device = await _device();
    final cookies = await session.storage.cookiesFor(session.network, _sso);
    final group =
        cookies
            .where((cookie) => cookie.name == 'riskSystemGroupId')
            .firstOrNull
            ?.value ??
        '';
    final values = {
      'fonts': jsonEncode([
        'Arial',
        'Helvetica Neue',
        'PingFang SC',
        'Times New Roman',
      ]),
      'deviceMemory': '16',
      'hardwareConcurrency': '10',
      'timezone': jsonEncode('Asia/Shanghai'),
      'cpuClass': jsonEncode('not available'),
      'platform': jsonEncode('MacIntel'),
      'language': jsonEncode('zh-CN'),
      'screenResolution': '[956,1470]',
    };
    final result = await _json(
      '/ustc-rba-front/fp',
      body: {
        for (final entry in values.entries)
          entry.key:
              [
                'fonts',
                'deviceMemory',
                'hardwareConcurrency',
                'cpuClass',
              ].contains(entry.key)
              ? schoolSha256(entry.value)
              : entry.value,
        'localgroupId': group,
        'fingerprint': schoolSha256(values.values.join()),
        'cookieValue': device,
        'userAgent': SchoolSession.userAgent,
        'platformAuthenticator': 'support',
      },
    );
    final token = result['responsetoken'] as String;
    return {'token': token, 'groupId': group};
  }

  Future<Map<String, dynamic>> _json(String path, {Object? body}) async =>
      (await _request(_sso.resolve(path), jsonBody: body)).json;

  Future<SchoolResponse> _request(
    Uri url, {
    Map<String, String>? form,
    Object? jsonBody,
    String? body,
    Map<String, String> headers = const {},
    bool followRedirects = true,
    bool checkStatus = true,
  }) => session.request(
    url,
    form: form,
    jsonBody: jsonBody,
    body: body,
    followRedirects: followRedirects,
    checkStatus: checkStatus,
    headers: {
      'Referer': _referer.toString(),
      if (form != null || jsonBody != null || body != null)
        'Origin': _sso.origin,
      if (url.path.contains('/protected/')) ...{
        ...schoolCsrfHeaders(),
        'Sid-Language': 'zh_CN',
      },
      ...headers,
    },
  );

  String _message(Map<String, dynamic> result) =>
      (result['message'] ?? result['msg'] ?? result['errorMessage'] ?? '')
          .toString();
}

class _LoginPage {
  _LoginPage(SchoolResponse response)
    : document = parse(response.text),
      url = response.url;

  final Document document;
  final Uri url;

  String field(String id) {
    final element = document.getElementById(id);
    return (element?.attributes['value'] ?? element?.text ?? '').trim();
  }

  String get execution =>
      document.getElementById('login-page-flowkey')!.text.trim();
  String get cryptoKey => document.getElementById('login-croypto')!.text.trim();
  Uri get action {
    final action = url.resolve(
      document.querySelector('form')!.attributes['action'] ?? 'login',
    );
    if (action.origin != 'https://sso.bit.edu.cn') {
      throw const SchoolRequestError('学校登录表单的地址异常。');
    }
    return action;
  }
}
