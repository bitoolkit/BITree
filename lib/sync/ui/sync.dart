import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../mooc/ui/mooc_sheet.dart';
import '../../school/ui/school_screen.dart';
import '../../school/ui/school_verification_dialog.dart';
import '../../ui/app_notice.dart';
import '../../ui/design.dart';
import '../../ui/sheet_layout.dart';
import '../controller.dart';
import 'sync_text.dart';

final _progressSheets = <SyncController, Future<void>>{};

/// Starts one round silently. Only account authentication requires a page.
Future<bool> startSync(
  BuildContext context,
  AppController app, {
  Set<SyncTarget>? targets,
  String? term,
}) async {
  if (app.sync.busy) {
    await showSyncProgress(context, app);
    return false;
  }
  final selected = targets ?? app.sync.defaultTargets;
  if (selected.isEmpty) return false;
  final school = selected.where((target) => target.isSchool).firstOrNull;
  if (school != null &&
      (app.school.username == null || app.school.loginExpired)) {
    if (await openSchoolLogin(context, app, source: school.source) != true ||
        !context.mounted) {
      return false;
    }
  }
  if (!context.mounted) return false;
  if (selected.contains(SyncTarget.mooc) && app.mooc.needsLogin) {
    if (!await showMoocAccount(context, app.mooc) || !context.mounted) {
      return false;
    }
  }
  if (!context.mounted) return false;
  final overlay = Overlay.of(context, rootOverlay: true);
  final success = await app.sync.synchronize(selected, term: term);
  if (!overlay.mounted ||
      app.sync.cancelled ||
      _progressSheets.containsKey(app.sync)) {
    return success;
  }
  showOverlayNotice(
    overlay,
    success ? '同步完成' : '部分内容未同步',
    action: success
        ? null
        : (
            label: '查看',
            onPressed: () {
              if (overlay.mounted) {
                unawaited(showSyncProgress(overlay.context, app));
              }
            },
          ),
  );
  return success;
}

Future<void> customizeSync(BuildContext context, AppController app) async {
  final selected = await showModalBottomSheet<Set<SyncTarget>>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _CustomSyncSheet(app: app),
  );
  if (selected == null || !context.mounted) return;
  await startSync(context, app, targets: selected);
}

Future<void> showSyncProgress(BuildContext context, AppController app) {
  final existing = _progressSheets[app.sync];
  if (existing != null) return existing;
  dismissAppNotice();
  final sheet = showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _SyncProgressSheet(app: app),
  );
  _progressSheets[app.sync] = sheet;
  return sheet.whenComplete(() => _progressSheets.remove(app.sync));
}

class _CustomSyncSheet extends StatefulWidget {
  const _CustomSyncSheet({required this.app});
  final AppController app;
  @override
  State<_CustomSyncSheet> createState() => _CustomSyncSheetState();
}

class _CustomSyncSheetState extends State<_CustomSyncSheet> {
  late final _selected = widget.app.sync.defaultTargets;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SheetLayout(
        header: SheetHeader(
          title: const Text('自定义同步'),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '已选 ${_selected.length} 项',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _selected.addAll(SyncTarget.values)),
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text('清空'),
                  ),
                ],
              ),
              for (final target in SyncTarget.values) ...[
                if (target == SyncTarget.lexue) const Divider(),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(target.title),
                  subtitle:
                      target == SyncTarget.mooc && widget.app.mooc.needsLogin
                      ? const Text('未登录，选择后登录')
                      : null,
                  value: _selected.contains(target),
                  onChanged: (checked) => setState(() {
                    if (checked == true) {
                      _selected.add(target);
                    } else {
                      _selected.remove(target);
                    }
                  }),
                ),
              ],
            ],
          ),
        ),
        actions: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: FilledButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(context, _selected),
            child: const Text('同步所选内容'),
          ),
        ),
      ),
    );
  }
}

class _SyncProgressSheet extends StatefulWidget {
  const _SyncProgressSheet({required this.app});
  final AppController app;
  @override
  State<_SyncProgressSheet> createState() => _SyncProgressSheetState();
}

class _SyncProgressSheetState extends State<_SyncProgressSheet> {
  bool _authenticating = false;

  Future<void> _retry() async {
    if (_authenticating || widget.app.sync.busy) return;
    final app = widget.app;
    final selected = app.sync.incompleteTargets;
    final term = app.sync.term;
    setState(() => _authenticating = true);
    try {
      if (selected.any((target) => target.isSchool) &&
          app.school.verificationRequired) {
        final verified = await app.school.restoreAccount(
          verify: (request) => verifySchoolLogin(context, request),
        );
        if (!verified || !mounted) return;
      }
      if (!mounted) return;
      await startSync(context, app, targets: selected, term: term);
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.app.sync,
    builder: (context, _) {
      final model = widget.app.sync;
      final theme = Theme.of(context);
      final results = model.results;
      return SafeArea(
        top: false,
        child: SheetLayout(
          header: SheetHeader(
            title: const Text('同步进度'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('收起'),
              ),
            ],
          ),
          content: Padding(
            padding: appSheetContentPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (model.term case final term?) ...[
                  Text(term, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 6),
                ],
                Text(
                  model.busy
                      ? '已处理 ${results.length} / ${model.targets.length} 项'
                      : model.cancelled
                      ? '同步已取消'
                      : model.incompleteTargets.isEmpty
                      ? '同步完成'
                      : '部分内容未同步',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: model.targets.isEmpty
                      ? 0
                      : results.length / model.targets.length,
                  minHeight: 3,
                ),
                const SizedBox(height: 16),
                for (final target in model.targets)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 14),
                          child: model.isRunning(target)
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  switch (results[target]?.outcome) {
                                    SyncOutcome.synced =>
                                      Icons.check_circle_outline_rounded,
                                    SyncOutcome.failed ||
                                    SyncOutcome.needsLogin ||
                                    SyncOutcome.needsVerification ||
                                    SyncOutcome.saveFailed =>
                                      Icons.error_outline_rounded,
                                    SyncOutcome.cancelled =>
                                      Icons.close_rounded,
                                    SyncOutcome.noSchedule =>
                                      Icons.event_busy_rounded,
                                    null => Icons.schedule_rounded,
                                  },
                                  size: 20,
                                  color:
                                      results[target]?.outcome ==
                                              SyncOutcome.failed ||
                                          results[target]?.outcome ==
                                              SyncOutcome.needsLogin ||
                                          results[target]?.outcome ==
                                              SyncOutcome.needsVerification ||
                                          results[target]?.outcome ==
                                              SyncOutcome.saveFailed
                                      ? theme.colorScheme.error
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                target.title,
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                syncProgressText(model, target),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: model.busy
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '收起后继续同步',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: model.cancelled ? null : model.cancel,
                        child: Text(model.cancelled ? '正在取消…' : '取消同步'),
                      ),
                    ],
                  ),
                )
              : model.incompleteTargets.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: FilledButton(
                    onPressed: _authenticating ? null : _retry,
                    child: Text(_authenticating ? '正在验证…' : '重试未完成的内容'),
                  ),
                )
              : null,
        ),
      );
    },
  );
}
