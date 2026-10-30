import 'package:flutter/material.dart';

import '../../core/async/cancelable_request.dart';
import '../../core/error_message.dart';
import '../../ui/app_notice.dart';
import '../../ui/design.dart';
import '../../ui/editor_sheet.dart';
import '../../ui/external_link.dart';
import '../../ui/sheet_layout.dart';
import '../api.dart';
import '../controller.dart';
import '../credentials.dart';
import 'login.dart';

Future<void> showMoocAccount(
  BuildContext context,
  MoocController controller, {
  bool synchronize = false,
}) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (_) => _MoocSheet(controller: controller, synchronize: synchronize),
);

class MoocAccountTile extends StatelessWidget {
  const MoocAccountTile({super.key, required this.controller});
  final MoocController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: const Icon(Icons.school_outlined, size: 36),
      title: const Text('中国大学MOOC'),
      subtitle: Text(
        [
          controller.account?.name,
          if (controller.needsLogin) controller.status,
        ].whereType<String>().join(' · '),
      ),
      trailing: const SizedBox.square(
        dimension: 48,
        child: Center(child: Icon(Icons.chevron_right_rounded, size: 20)),
      ),
      onTap: () => showMoocAccount(context, controller),
    ),
  );
}

class _MoocSheet extends StatefulWidget {
  const _MoocSheet({required this.controller, this.synchronize = false});
  final MoocController controller;
  final bool synchronize;
  @override
  State<_MoocSheet> createState() => _MoocSheetState();
}

class _MoocSheetState extends State<_MoocSheet> {
  MoocImportResult? _result;
  String? _error;
  bool _loginOpen = false;

  @override
  void initState() {
    super.initState();
    if (widget.synchronize && !widget.controller.needsLogin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sync();
      });
    }
  }

  Future<void> _login() async {
    if (_loginOpen) return;
    setState(() {
      _loginOpen = true;
      _error = null;
    });
    try {
      final success = await loginToMooc(context, widget.controller);
      if (success && mounted && widget.synchronize) await _sync();
    } finally {
      if (mounted) setState(() => _loginOpen = false);
    }
  }

  Future<void> _cookie() async {
    final success = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _CookieSheet(controller: widget.controller),
    );
    if (success == true && mounted && widget.synchronize) await _sync();
  }

  Future<void> _sync() async {
    setState(() {
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.controller.synchronize();
      if (mounted) setState(() => _result = result);
    } on RequestCancelled {
      if (mounted) showAppNotice(context, '已取消 MOOC 同步');
    } catch (error) {
      if (mounted) {
        setState(() => _error = widget.controller.error ?? errorMessage(error));
      }
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出中国大学MOOC？'),
        content: const Text('删除本机保存的登录会话，已导入的 DDL 会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.disconnect();
      if (mounted) setState(() => _result = null);
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    }
  }

  @override
  void dispose() {
    if (!_loginOpen) widget.controller.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final model = widget.controller;
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final enabled = !model.busy && !_loginOpen;
      return SafeArea(
        top: false,
        child: SheetLayout(
          header: SheetHeader(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('中国大学MOOC'),
                if (model.account case final account?) ...[
                  const SizedBox(height: 6),
                  Text(
                    account.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (model.needsLogin)
                    Text(
                      model.status,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                ],
              ],
            ),
            actions: [
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
          content: Padding(
            padding: appSheetContentPadding,
            child: ListTileTheme(
              data: theme.listTileTheme.copyWith(
                contentPadding: EdgeInsets.zero,
                minTileHeight: 48,
                minVerticalPadding: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!model.needsLogin) ...[
                    ListTile(
                      leading: model.busy
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.sync_rounded, color: scheme.primary),
                      title: Text(
                        '同步 DDL',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                      subtitle: Text(
                        model.busy ? model.progress : '作业、测验、考试与互评',
                      ),
                      trailing: model.busy
                          ? TextButton(
                              onPressed: model.cancel,
                              child: const Text('取消'),
                            )
                          : const Icon(Icons.chevron_right_rounded, size: 20),
                      onTap: enabled ? _sync : null,
                    ),
                    const Divider(height: 24),
                  ],
                  ListTile(
                    leading: const Icon(Icons.login_rounded),
                    title: Text(model.needsLogin ? '网页登录' : '重新登录'),
                    subtitle: model.needsLogin
                        ? const Text('手机号、邮箱、验证码或扫码')
                        : null,
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                    enabled: enabled,
                    onTap: enabled ? _login : null,
                  ),
                  ListTile(
                    leading: const Icon(Icons.key_outlined),
                    title: const Text('使用 Cookie'),
                    subtitle: model.needsLogin ? const Text('备用登录方式') : null,
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                    enabled: enabled,
                    onTap: enabled ? _cookie : null,
                  ),
                  if (model.account != null) ...[
                    const Divider(height: 24),
                    ListTile(
                      leading: Icon(Icons.logout_rounded, color: scheme.error),
                      title: Text(
                        '退出账号',
                        style: TextStyle(color: scheme.error),
                      ),
                      enabled: enabled,
                      onTap: enabled ? _disconnect : null,
                    ),
                  ],
                  if (_error ?? model.error case final error?)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        error,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  if (_result case final result?) ...[
                    const SizedBox(height: 24),
                    Text(
                      '已同步 ${result.entries.length} 条 DDL',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text('读取了 ${result.courseCount} 门课程'),
                    if (result.failures.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        '以下课程未能同步，可重新尝试',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      for (final failure in result.failures)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(failure.course),
                          subtitle: Text(failure.message),
                        ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CookieSheet extends StatefulWidget {
  const _CookieSheet({required this.controller});
  final MoocController controller;
  @override
  State<_CookieSheet> createState() => _CookieSheetState();
}

class _CookieSheetState extends State<_CookieSheet> {
  final _form = GlobalKey<FormState>();
  final _text = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final cookies = MoocCredentials.cookiesFromHeader(_text.text);
      final success = await loginToMooc(
        context,
        widget.controller,
        initialCookies: cookies,
      );
      if (success && mounted) Navigator.pop(context, true);
    } on RequestCancelled {
      if (mounted) setState(() => _error = '已取消连接');
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : widget.controller.error ?? errorMessage(error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EditorSheet(
    title: '使用 Cookie',
    formKey: _form,
    saving: _saving,
    onSave: _save,
    saveLabel: Text(_saving ? '登录中…' : '连接'),
    error: _error,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('在已登录的 MOOC 网页中，从开发者工具的网络面板复制请求 Cookie。此方式仅作为网页登录的备用。'),
        const SizedBox(height: 16),
        TextFormField(
          controller: _text,
          enabled: !_saving,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Cookie',
            alignLabelWithHint: true,
          ),
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          validator: (value) =>
              value == null || value.trim().isEmpty ? '请粘贴 Cookie' : null,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => openExternalLink(
            context,
            MoocCredentials.origin.resolve('/member/login.htm'),
            failureTitle: '无法打开 MOOC',
          ),
          child: const Text('打开官方登录页'),
        ),
      ],
    ),
  );
}
