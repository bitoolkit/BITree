import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bitree/mooc/ui/login.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

// Keep I/O in memory for the widget test's fake clock. mooc_test covers the
// same production API through real HTTP sockets, including failed sessions.
class _AccountPage extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _PageClient();
}

class _PageClient extends Fake implements HttpClient {
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    expect('$url', 'https://www.icourse163.org/home.htm');
    return _PageRequest();
  }

  @override
  void close({bool force = false}) {}
}

class _PageHeaders extends Fake implements HttpHeaders {
  final _values = <String, Object>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values[name.toLowerCase()] = value;
  @override
  String? value(String name) => _values[name.toLowerCase()]?.toString();
}

class _PageRequest extends Fake implements HttpClientRequest {
  @override
  final headers = _PageHeaders();
  @override
  final cookies = <Cookie>[];
  @override
  set followRedirects(bool value) {}
  @override
  Future<HttpClientResponse> close() async {
    expect(headers.value(HttpHeaders.userAgentHeader), 'MOOC login browser');
    expect(
      cookies.where((c) => c.name == 'STUDY_SESS').single.httpOnly,
      isTrue,
    );
    return _PageResponse();
  }
}

class _PageResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  List<Cookie> get cookies => [];
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream.value(
        utf8.encode(
          '<html><script>window.webUser = '
          '${jsonEncode({
            'id': 8,
            'nickName': '回调测试同学',
            'profile': {'text': '} ; "'},
          })};'
          '</script></html>',
        ),
      ).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const browserChannel = MethodChannel('desktop_webview_window');
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('mooc-browser-');
    messenger.setMockMethodCallHandler(
      pathChannel,
      (_) async => directory.path,
    );
  });
  tearDownAll(() async {
    messenger.setMockMethodCallHandler(browserChannel, null);
    messenger.setMockMethodCallHandler(pathChannel, null);
    await directory.delete(recursive: true);
  });

  testWidgets(
    'A verified browser session closes the window and returns to the app',
    (tester) async {
      var closed = false;
      final launched = Completer<void>();
      void event(String name, Map<String, Object> values) =>
          tester.binding.channelBuffers.push(
            browserChannel.name,
            codec.encodeMethodCall(MethodCall(name, {'id': 8, ...values})),
            (_) {},
          );
      messenger.setMockMethodCallHandler(browserChannel, (call) async {
        switch (call.method) {
          case 'clearAll':
          case 'setUrlRequestEnabled':
            return null;
          case 'launch':
            launched.complete();
            event('onNavigationStateChanged', {
              'canGoBack': false,
              'canGoForward': false,
              'isLoading': false,
              'url': 'https://www.icourse163.org/',
            });
            return null;
          case 'create':
            return {'id': 8, 'windowHandle': 0};
          case 'evaluateJavaScript':
            return jsonEncode(switch ((call.arguments
                as Map)['javaScriptString']) {
              'location.origin' => 'https://www.icourse163.org',
              'navigator.userAgent' => 'MOOC login browser',
              _ => false,
            });
          case 'getAllCookies':
            return [
              for (final name in ['NTESSTUDYSI', 'STUDY_SESS'])
                {
                  'name': name,
                  'value': 'test-session',
                  'domain': '.icourse163.org',
                  'path': '/',
                  'httpOnly': name == 'STUDY_SESS',
                  'secure': true,
                  'sessionOnly': true,
                },
            ];
          case 'close':
            closed = true;
            event('onWindowClose', {});
            return null;
          default:
            throw StateError('Unexpected browser operation: ${call.method}');
        }
      });
      final storage = MemoryMoocStorage();
      final model = TestAppController(moocStorage: storage);
      await model.initialize();
      bool? result;
      await HttpOverrides.runWithHttpOverrides(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: bitreeTheme(Brightness.light),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async =>
                      result = await loginToMooc(context, model.mooc),
                  child: const Text('登录'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('登录'));
        await tester.pump();
        await tester.runAsync(
          () => launched.future.timeout(const Duration(seconds: 10)),
        );
        await tester.pumpAndSettle();
      }, _AccountPage());
      expect(result, isTrue);
      expect(closed, isTrue);
      expect(storage.account!.id, '8');
      expect(storage.account!.name, '回调测试同学');
      expect(
        storage.account!.credentials.cookies.join(';'),
        contains('HttpOnly'),
      );
      expect(model.agenda.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
