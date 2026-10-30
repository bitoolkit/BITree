import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../ui/app_notice.dart';
import 'account_status.dart';
import 'school_screen.dart';
import 'school_verification_dialog.dart';

class SchoolAccount extends StatefulWidget {
  const SchoolAccount({super.key, required this.controller});

  final AppController controller;

  @override
  State<SchoolAccount> createState() => _SchoolAccountState();
}

class _SchoolAccountState extends State<SchoolAccount> {
  bool _handlingAction = false;

  Future<void> _perform(Future<void> Function() action) async {
    if (_handlingAction || widget.controller.timetable.busy) return;
    setState(() => _handlingAction = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _handlingAction = false);
    }
  }

  Future<void> _login() async {
    await openSchoolLogin(context, widget.controller);
  }

  Future<void> _verify() async {
    final success = await widget.controller.school.restoreAccount(
      verify: (request) => verifySchoolLogin(context, request),
    );
    if (success && mounted) showAppNotice(context, '学校账号验证完成');
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出学校账号？'),
        content: const Text('将移除此设备上的登录信息，保留本地课表和日程。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.school.signOut();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller.school,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final controller = widget.controller;
    final hasAccount = controller.school.username != null;
    final needsVerification = controller.school.verificationRequired;
    final needsLogin = !hasAccount || controller.school.loginExpired;
    final enabled = !_handlingAction && !controller.timetable.busy;
    final canLogin = enabled && !controller.school.busy;
    final onTap = needsLogin
        ? _login
        : needsVerification
        ? _verify
        : _signOut;
    final canTap = needsLogin || needsVerification ? canLogin : enabled;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Icon(
        Icons.account_circle_outlined,
        size: 36,
        color: hasAccount ? scheme.primary : null,
      ),
      title: Text(controller.school.username ?? '登录学校账号'),
      subtitle: hasAccount || needsVerification
          ? Text(controller.school.accountStatus.label)
          : null,
      trailing: hasAccount
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (needsVerification || controller.school.loginExpired)
                  TextButton(
                    onPressed: canLogin
                        ? () => _perform(needsVerification ? _verify : _login)
                        : null,
                    child: Text(needsVerification ? '验证' : '登录'),
                  ),
                IconButton(
                  tooltip: '退出学校账号',
                  onPressed: enabled ? () => _perform(_signOut) : null,
                  icon: const Icon(Icons.logout_rounded, size: 20),
                ),
              ],
            )
          : const SizedBox.square(
              dimension: 48,
              child: Center(child: Icon(Icons.chevron_right_rounded, size: 20)),
            ),
      onTap: canTap ? () => _perform(onTap) : null,
    );
  }
}
