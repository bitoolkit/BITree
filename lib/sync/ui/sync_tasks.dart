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

final _taskSheets = <SyncController, Future<void>>{};

Future<bool> _authenticate(
  BuildContext context,
  AppController app,
  SyncTarget target,
) async {
  if (target == SyncTarget.mooc) {
    return !app.mooc.needsLogin || await showMoocAccount(context, app.mooc);
  }
  if (app.school.busy) {
    return app.school.username != null &&
        !app.school.loginExpired &&
        !app.school.verificationRequired;
  }
  if (app.school.username == null || app.school.loginExpired) {
    return await openSchoolLogin(context, app, source: target.source) == true;
  }
  if (app.school.verificationRequired) {
    return app.school.restoreAccount(
      verify: (request) => verifySchoolLogin(context, request),
    );
  }
  return true;
}

/// Starts work without presenting progress or tying its lifetime to this route.
Future<bool> startSync(
  BuildContext context,
  AppController app, {
  required SyncTarget target,
  String? term,
}) async {
  if (!app.sync.contains(target, term: term) &&
      (target == SyncTarget.mooc
          ? app.mooc.needsLogin
          : app.school.username == null || app.school.loginExpired)) {
    if (!await _authenticate(context, app, target) || !context.mounted) {
      return false;
    }
  }
  if (!context.mounted) return false;
  final overlay = Overlay.of(context, rootOverlay: true);
  final task = app.sync.enqueue(target, term: term);
  return _feedback(overlay, app, task);
}

Future<bool> _feedback(
  OverlayState overlay,
  AppController app,
  SyncTask task,
) async {
  final success = await task.finished;
  if (!overlay.mounted ||
      task.phase == SyncPhase.cancelled ||
      _taskSheets.containsKey(app.sync)) {
    return success;
  }
  showOverlayNotice(
    overlay,
    success
        ? '${task.target.title}同步完成'
        : '${task.target.title}：${task.message}',
    action: success
        ? null
        : (
            label: '查看',
            onPressed: () {
              if (overlay.mounted) {
                unawaited(showSyncTasks(overlay.context, app));
              }
            },
          ),
  );
  return success;
}

Future<void> showSyncTasks(BuildContext context, AppController app) {
  final existing = _taskSheets[app.sync];
  if (existing != null) return existing;
  dismissAppNotice();
  final sheet = showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _SyncTasksSheet(app: app),
  );
  _taskSheets[app.sync] = sheet;
  return sheet.whenComplete(() => _taskSheets.remove(app.sync));
}

class _SyncTasksSheet extends StatefulWidget {
  const _SyncTasksSheet({required this.app});
  final AppController app;
  @override
  State<_SyncTasksSheet> createState() => _SyncTasksSheetState();
}

class _SyncTasksSheetState extends State<_SyncTasksSheet> {
  final _selected = <SyncTarget>{};
  bool _adding = false;
  bool _authenticating = false;

  Future<void> _add() async {
    if (_authenticating || _selected.isEmpty) return;
    final selected = _selected.toList();
    final app = widget.app;
    final overlay = Overlay.of(context, rootOverlay: true);
    setState(() => _authenticating = true);
    try {
      final school = selected.where((target) => target.isSchool).firstOrNull;
      // Existing school work already owns a valid session; append to its queue.
      final schoolReady =
          school == null ||
          (app.school.username != null && !app.school.loginExpired) ||
          await _authenticate(context, app, school);
      if (!mounted) return;
      if (schoolReady) {
        for (final target in selected.where((target) => target.isSchool)) {
          unawaited(_feedback(overlay, app, app.sync.enqueue(target)));
        }
      }
      if (selected.contains(SyncTarget.mooc) &&
          await _authenticate(context, app, SyncTarget.mooc)) {
        if (!mounted) return;
        unawaited(_feedback(overlay, app, app.sync.enqueue(SyncTarget.mooc)));
      }
      if (mounted) {
        setState(() {
          _adding = false;
          _selected.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  Future<void> _retry(SyncTask task) async {
    if (_authenticating) return;
    final app = widget.app;
    final overlay = Overlay.of(context, rootOverlay: true);
    setState(() => _authenticating = true);
    try {
      if (!await _authenticate(context, app, task.target) || !mounted) return;
      unawaited(_feedback(overlay, app, app.sync.retry(task)));
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  String _retryLabel(SyncTask task) {
    if (task.phase != SyncPhase.attention) return '重试';
    final app = widget.app;
    if (task.target.isSchool && app.school.verificationRequired) {
      return '完成验证并继续';
    }
    final needsLogin = task.target.isSchool
        ? app.school.username == null || app.school.loginExpired
        : app.mooc.needsLogin;
    return needsLogin ? '登录并继续' : '继续同步';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.app.sync,
    builder: (context, _) {
      final model = widget.app.sync;
      final theme = Theme.of(context);
      return SafeArea(
        top: false,
        child: SheetLayout(
          header: SheetHeader(
            title: const Text('同步任务'),
            actions: [
              IconButton(
                tooltip: _adding ? '返回任务列表' : '添加同步任务',
                onPressed: _authenticating
                    ? null
                    : () => setState(() => _adding = !_adding),
                icon: Icon(_adding ? Icons.list_rounded : Icons.add_rounded),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('收起'),
              ),
            ],
          ),
          actions: _adding || model.activeCount > 0
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: _adding
                      ? FilledButton(
                          onPressed: _selected.isEmpty || _authenticating
                              ? null
                              : _add,
                          child: Text(
                            _authenticating
                                ? '正在登录…'
                                : '添加 ${_selected.length} 项同步',
                          ),
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Text(
                                '收起后继续同步',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: model.cancelAll,
                              child: const Text('取消全部'),
                            ),
                          ],
                        ),
                )
              : null,
          content: Padding(
            padding: appSheetContentPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_adding) ...[
                  for (final target in SyncTarget.values)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(target.title),
                      subtitle: model.contains(target)
                          ? const Text('已在任务中')
                          : null,
                      value: _selected.contains(target),
                      onChanged: _authenticating || model.contains(target)
                          ? null
                          : (value) => setState(() {
                              if (value == true) {
                                _selected.add(target);
                              } else {
                                _selected.remove(target);
                              }
                            }),
                    ),
                ] else ...[
                  if (model.tasks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('暂无同步任务，点右上角添加'),
                    ),
                  for (final task in model.tasks) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2, right: 14),
                            child:
                                task.phase == SyncPhase.running ||
                                    task.phase == SyncPhase.cancelling
                                ? const SizedBox.square(
                                    dimension: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    switch (task.phase) {
                                      SyncPhase.completed =>
                                        Icons.check_circle_outline_rounded,
                                      SyncPhase.failed || SyncPhase.attention =>
                                        Icons.error_outline_rounded,
                                      SyncPhase.cancelled =>
                                        Icons.close_rounded,
                                      _ => Icons.schedule_rounded,
                                    },
                                    size: 22,
                                    color:
                                        task.phase == SyncPhase.failed ||
                                            task.phase == SyncPhase.attention
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.target.title,
                                  style: theme.textTheme.titleSmall,
                                ),
                                if (task.term != null)
                                  Text(
                                    task.term!,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  model.progress(task),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if ([
                                  SyncPhase.attention,
                                  SyncPhase.failed,
                                  SyncPhase.cancelled,
                                ].contains(task.phase))
                                  TextButton(
                                    onPressed: _authenticating
                                        ? null
                                        : () => _retry(task),
                                    child: Text(_retryLabel(task)),
                                  ),
                              ],
                            ),
                          ),
                          if (task.active)
                            IconButton(
                              tooltip: '取消${task.target.title}同步',
                              onPressed: task.phase == SyncPhase.cancelling
                                  ? null
                                  : () => model.cancel(task),
                              icon: const Icon(Icons.close_rounded, size: 20),
                            ),
                        ],
                      ),
                    ),
                    if (task != model.tasks.last) const Divider(height: 1),
                  ],
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
