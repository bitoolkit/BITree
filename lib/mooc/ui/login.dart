import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart' as desktop;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide Cookie;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/async/cancelable_request.dart';
import '../controller.dart';
import '../credentials.dart';

final _loginUrl = Uri.https('www.icourse163.org', '/member/login.htm');

Future<bool> loginToMooc(
  BuildContext context,
  MoocController controller,
) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _MoocLogin(controller: controller)),
    ) ==
    true;

class _MoocLogin extends StatefulWidget {
  const _MoocLogin({required this.controller});
  final MoocController controller;
  @override
  State<_MoocLogin> createState() => _MoocLoginState();
}

class _MoocLoginState extends State<_MoocLogin> {
  desktop.Webview? _desktop;
  InAppWebViewController? _mobile;
  Timer? _poll;
  bool _checking = false;
  bool _finished = false;
  bool _loading = true;
  bool _mobileReady = false;
  String? _message;
  String? _attempted;
  final _popups = <Route<void>>[];

  bool get _isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      unawaited(_openDesktop());
    } else {
      unawaited(_openMobile());
    }
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _capture());
  }

  Future<void> _openMobile() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await CookieManager.instance().deleteAllCookies().timeout(
        const Duration(seconds: 10),
      );
      if (mounted) setState(() => _mobileReady = true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = '无法准备登录页面，请重试。';
        });
      }
    }
  }

  Future<void> _openDesktop() async {
    if (mounted) {
      setState(() {
        _message = null;
        _loading = true;
        _attempted = null;
      });
    }
    try {
      final support = await getApplicationSupportDirectory();
      final options = desktop.WindowsWebviewOptions(
        userDataFolder: '${support.path}/mooc-browser',
      );
      await desktop.WebviewWindow.clearAll(windows: options);
      if (!mounted) return;
      final browser = await desktop.WebviewWindow.create(
        configuration: desktop.CreateConfiguration(
          title: '中国大学MOOC 登录',
          windowWidth: 1024,
          windowHeight: 800,
          windows: options,
        ),
      );
      if (!mounted) {
        await browser.close();
        return;
      }
      _desktop = browser;
      await browser.setOnUrlRequestCallback(
        (url) => _webNavigation(Uri.tryParse(url)),
      );
      browser.navigationState.addListener(_navigationChanged);
      unawaited(
        browser.onClose.then((_) {
          if (mounted && !_finished) {
            widget.controller.cancel();
            setState(() {
              _desktop = null;
              _loading = false;
              _message = '登录窗口已关闭。';
            });
          }
        }),
      );
      await browser.launch('$_loginUrl');
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = Platform.isWindows
              ? '无法打开登录窗口，请确认已安装 Microsoft Edge WebView2，或改用 Cookie。'
              : '无法打开登录窗口，请重试或改用 Cookie。';
        });
      }
    }
  }

  void _navigationChanged() {
    if (!mounted) return;
    setState(
      () => _loading = _desktop?.navigationState.value.isLoading ?? false,
    );
    if (!_loading) unawaited(_capture());
  }

  static bool _webNavigation(Uri? uri) =>
      uri != null && (uri.scheme == 'https' || '$uri' == 'about:blank');

  Future<bool> _mobileNavigation(
    InAppWebViewController browser,
    NavigationAction action,
  ) async {
    final url = action.request.url;
    final uri = url == null ? null : Uri.tryParse('$url');
    if (_webNavigation(uri)) return true;
    if (uri != null &&
        ['weixin', 'mqq', 'mqqapi', 'sinaweibo'].contains(uri.scheme)) {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        setState(() => _message = '无法打开对应应用，可使用官方页面中的其他登录方式。');
      }
    }
    return false;
  }

  Future<Object?> _evaluate(String source) async {
    if (_isDesktop) return _desktop?.evaluateJavaScript(source);
    return _mobile?.evaluateJavascript(source: source);
  }

  Future<List<Cookie>> _cookies() async {
    if (_isDesktop) {
      final values = await _desktop!.getAllCookies();
      return [
        for (final value in values)
          Cookie(value.name, value.value)
            ..domain = value.domain
            ..path = value.path
            ..secure = value.secure
            ..httpOnly = value.httpOnly
            ..expires = value.sessionOnly ? null : value.expires,
      ];
    }
    final values = await CookieManager.instance().getCookies(
      url: WebUri('${MoocCredentials.rpcDirectory}'),
      webViewController: _mobile,
    );
    return [
      for (final value in values)
        Cookie(value.name, '${value.value}')
          ..domain = value.domain
          ..path = value.path ?? '/'
          ..secure = value.isSecure ?? true
          ..httpOnly = value.isHttpOnly ?? false
          ..expires = value.expiresDate == null || value.expiresDate! <= 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  value.expiresDate!,
                  isUtc: true,
                ),
    ];
  }

  Future<void> _capture({bool manual = false}) async {
    if (_checking ||
        _finished ||
        !mounted ||
        (_desktop == null && _mobile == null)) {
      return;
    }
    _checking = true;
    try {
      // Server-rendered webUser is a completion signal, not an authentication
      // decision. The native client still verifies the exported session.
      final ready = await _evaluate(
        'location.origin === "https://www.icourse163.org" && !!(window.webUser && window.webUser.id)',
      ).timeout(const Duration(seconds: 5));
      if (!manual && ready != true) return;
      final agent = await _evaluate('navigator.userAgent')
          .timeout(const Duration(seconds: 5));
      if (agent is! String) throw const FormatException('无法读取浏览器信息，请刷新登录页。');
      final credential = MoocCredentials(
        userAgent: agent,
        cookies: await _cookies().timeout(const Duration(seconds: 5)),
      );
      final candidate = jsonEncode(credential.toJson());
      if (!manual && candidate == _attempted) return;
      _attempted = candidate;
      if (!mounted) return;
      if (mounted) setState(() => _message = '正在验证登录…');
      await widget.controller.connect(credential);
      if (!mounted) return;
      _finished = true;
      _poll?.cancel();
      final navigator = Navigator.of(context);
      for (final route in _popups.toList()) {
        if (route.isActive) navigator.removeRoute(route);
      }
      navigator.pop(true);
    } on RequestCancelled {
      // Closing the page cancels validation without saving an unverified session.
    } on FormatException catch (error) {
      if (mounted && manual) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = widget.controller.error ?? '未能读取登录状态，请完成登录后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<bool> _popup(
    InAppWebViewController browser,
    CreateWindowAction action,
  ) async {
    if (!mounted) return false;
    final route = MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('MOOC 授权登录')),
        body: InAppWebView(
          windowId: action.windowId,
          initialSettings: _settings,
          shouldOverrideUrlLoading: (view, navigation) async =>
              await _mobileNavigation(view, navigation)
              ? NavigationActionPolicy.ALLOW
              : NavigationActionPolicy.CANCEL,
          onCreateWindow: _popup,
          onCloseWindow: (_) => Navigator.of(context).pop(),
        ),
      ),
    );
    _popups.add(route);
    unawaited(
      Navigator.of(context)
          .push(route)
          .whenComplete(() => _popups.remove(route)),
    );
    return true;
  }

  InAppWebViewSettings get _settings => InAppWebViewSettings(
    javaScriptEnabled: true,
    thirdPartyCookiesEnabled: true,
    supportMultipleWindows: true,
    javaScriptCanOpenWindowsAutomatically: true,
    useShouldOverrideUrlLoading: true,
  );

  @override
  void dispose() {
    _poll?.cancel();
    if (!_finished) widget.controller.cancel();
    final browser = _desktop;
    browser?.navigationState.removeListener(_navigationChanged);
    if (browser != null) unawaited(browser.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('登录中国大学MOOC'),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => _capture(manual: true),
          child: const Text('已完成登录'),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_message != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_message!)),
          Expanded(
            child: _isDesktop
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.open_in_browser, size: 40),
                          const SizedBox(height: 16),
                          const Text(
                            '请在登录窗口完成手机号、邮箱、验证码或第三方登录。',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: _desktop == null
                                ? _openDesktop
                                : () => _desktop!.reload(),
                            child: Text(_desktop == null ? '打开登录窗口' : '刷新登录页'),
                          ),
                        ],
                      ),
                    ),
                  )
                : !_mobileReady
                ? Center(
                    child: _loading
                        ? const CircularProgressIndicator()
                        : TextButton(
                            onPressed: _openMobile,
                            child: const Text('重试打开登录页'),
                          ),
                  )
                : InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri('$_loginUrl')),
                    initialSettings: _settings,
                    onWebViewCreated: (browser) => _mobile = browser,
                    onLoadStart: (_, _) {
                      if (mounted) setState(() => _loading = true);
                    },
                    onLoadStop: (_, _) {
                      if (mounted) {
                        setState(() => _loading = false);
                        unawaited(_capture());
                      }
                    },
                    onReceivedError: (_, request, _) {
                      if (mounted && request.isForMainFrame == true) {
                        setState(() => _message = '登录页加载失败，请检查网络或返回后重试。');
                      }
                    },
                    shouldOverrideUrlLoading: (view, action) async =>
                        await _mobileNavigation(view, action)
                        ? NavigationActionPolicy.ALLOW
                        : NavigationActionPolicy.CANCEL,
                    onCreateWindow: _popup,
                  ),
          ),
        ],
      ),
    ),
  );
}
