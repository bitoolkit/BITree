import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_android/webview_all_android.dart';

import '../../core/async/cancelable_request.dart';
import '../../core/diagnostics.dart';
import '../controller.dart';
import '../cookie.dart';
import '../credentials.dart';
import '../tasks.dart';

final _loginUrl = MoocCredentials.origin.resolve('/member/login.htm');

Future<bool> loginToMooc(
  BuildContext context,
  MoocController controller, {
  List<Cookie>? initialCookies,
}) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            _MoocLogin(controller: controller, initialCookies: initialCookies),
      ),
    ) ==
    true;

class _MoocLogin extends StatefulWidget {
  const _MoocLogin({required this.controller, this.initialCookies});
  final MoocController controller;
  final List<Cookie>? initialCookies;
  @override
  State<_MoocLogin> createState() => _MoocLoginState();
}

class _MoocLoginState extends State<_MoocLogin> {
  WebViewController? _browser;
  WebViewCookieManager? _cookies;
  Timer? _poll;
  bool _ready = false;
  bool _checking = false;
  bool _finished = false;
  int _progress = 0;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    setState(() {
      _ready = false;
      _message = null;
      _progress = 0;
    });
    try {
      final browser = WebViewController();
      _browser = browser;
      await browser.setJavaScriptMode(JavaScriptMode.unrestricted);
      await browser.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _navigate,
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _progress = 100);
            _startChecking();
            unawaited(_capture());
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() {
                _progress = 100;
                _message = '登录页加载失败，请检查网络后刷新。';
              });
            }
          },
        ),
      );
      final cookies = WebViewCookieManager();
      _cookies = cookies;
      if (cookies.platform case final AndroidWebViewCookieManager manager) {
        // NetEase sign-in runs in a cross-origin iframe on the MOOC page.
        await manager.setAcceptThirdPartyCookies(
          browser.platform as AndroidWebViewController,
          true,
        );
      }
      await cookies.clearCookies().timeout(const Duration(seconds: 10));
      for (final cookie in widget.initialCookies ?? <Cookie>[]) {
        await cookies
            .setCookie(
              WebViewCookie(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain ?? MoocCredentials.origin.host,
                path: cookie.path ?? '/',
              ),
            )
            .timeout(const Duration(seconds: 10));
      }
      if (!mounted) return;
      setState(() => _ready = true);
      await browser.loadRequest(
        widget.initialCookies == null
            ? _loginUrl
            : MoocCredentials.origin.resolve('/home.htm'),
      );
      _startChecking();
    } catch (error, stack) {
      AppDiagnostics.instance.error('打开 MOOC 登录页', error, stack);
      if (mounted) {
        setState(() {
          _progress = 100;
          _message = '无法打开登录页，请重试。';
        });
      }
    }
  }

  void _startChecking() {
    if (!mounted || _finished || (_poll?.isActive ?? false)) return;
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _capture());
  }

  Future<NavigationDecision> _navigate(NavigationRequest request) async {
    final uri = Uri.tryParse(request.url);
    if (uri != null && (uri.scheme == 'https' || '$uri' == 'about:blank')) {
      return NavigationDecision.navigate;
    }
    if (uri != null &&
        ['weixin', 'mqq', 'mqqapi', 'sinaweibo'].contains(uri.scheme)) {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        setState(() => _message = '无法打开对应应用，请选择页面中的其他登录方式。');
      }
    }
    return NavigationDecision.prevent;
  }

  Future<void> _capture({bool manual = false}) async {
    final browser = _browser;
    if (!_ready || browser == null || _checking || _finished || !mounted) {
      return;
    }
    _checking = true;
    try {
      // JavaScript is evaluated by the website's browser. Transfer only plain
      // account fields; server scripts are never parsed or evaluated in Dart.
      final value = await browser.callAsyncJavaScript('''
        if (location.origin !== 'https://www.icourse163.org') return false;
        const user = window.webUser;
        if (!user || !user.id) return false;
        return {id: String(user.id), name: String(user.nickName || 'MOOC 用户'),
          userAgent: navigator.userAgent};
      ''', timeout: const Duration(seconds: 8));
      final data = moocMap(value);
      final id = moocId(data?['id']);
      if (id == null) {
        if (manual && mounted) setState(() => _message = '请先在页面中完成登录。');
        return;
      }
      final agent = data!['userAgent'];
      final name = data['name'];
      if (agent is! String || name is! String) {
        throw const FormatException('无法读取 MOOC 账号信息，请刷新登录页。');
      }
      final exported = await _cookies!
          .getCookies(domain: MoocCredentials.rpcDirectory)
          .timeout(const Duration(seconds: 8));
      if (!exported.any((cookie) => cookie.name == 'NTESSTUDYSI')) {
        if (manual && mounted) {
          setState(() => _message = '登录会话尚未就绪，请稍后重试。');
        }
        return;
      }
      final credentials = MoocCredentials(
        userAgent: agent,
        cookies: [
          for (final cookie in exported)
            MoocCookie(cookie.name, cookie.value)
              ..domain = cookie.domain
              ..path = cookie.path
              ..secure = true,
        ],
      );
      if (!mounted) return;
      setState(() => _message = '正在保存登录…');
      await widget.controller.connect(
        MoocAccount(id: id, name: name, credentials: credentials),
      );
      if (!mounted) return;
      _finished = true;
      _poll?.cancel();
      Navigator.pop(context, true);
    } on RequestCancelled {
      // Leaving the login page cancels unfinished work.
    } catch (error, stack) {
      _poll?.cancel();
      if (widget.controller.error == null) {
        AppDiagnostics.instance.error('读取 MOOC 网页登录', error, stack);
      }
      if (mounted) {
        setState(
          () =>
              _message = widget.controller.error ?? '无法读取登录状态，请刷新或点击“完成登录”重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (!_finished) widget.controller.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('登录中国大学MOOC'),
        actions: [
          IconButton(
            tooltip: '刷新登录页',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: widget.controller.busy || (!_ready && _progress < 100)
                ? null
                : () {
                    if (_ready) {
                      _browser!.reload();
                    } else {
                      _prepare();
                    }
                  },
          ),
          TextButton(
            onPressed: !_ready || widget.controller.busy
                ? null
                : () => _capture(manual: true),
            child: Text(widget.controller.busy ? '保存中…' : '完成登录'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_progress < 100)
              LinearProgressIndicator(value: _progress / 100),
            if (_message case final message?)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(message),
              ),
            Expanded(
              child: _ready
                  ? WebViewWidget(controller: _browser!)
                  : const SizedBox(),
            ),
          ],
        ),
      ),
    ),
  );
}
