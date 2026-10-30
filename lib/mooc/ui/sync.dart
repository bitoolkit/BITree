import 'package:flutter/material.dart';

import '../../core/async/cancelable_request.dart';
import '../../core/error_message.dart';
import '../../ui/design.dart';
import '../../ui/sheet_layout.dart';
import '../api.dart';
import '../controller.dart';
import 'mooc_sheet.dart';

Future<void> synchronizeMoocDeadlines(
  BuildContext context,
  MoocController controller,
) async {
  if (controller.needsLogin) {
    final signedIn = await showMoocAccount(context, controller);
    if (!signedIn || !context.mounted) return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _MoocSyncSheet(controller: controller),
  );
}

class _MoocSyncSheet extends StatefulWidget {
  const _MoocSyncSheet({required this.controller});
  final MoocController controller;
  @override
  State<_MoocSyncSheet> createState() => _MoocSyncSheetState();
}

class _MoocSyncSheetState extends State<_MoocSyncSheet> {
  MoocImportResult? _result;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _synchronize();
    });
  }

  Future<void> _synchronize() async {
    setState(() {
      _result = null;
      _message = null;
    });
    try {
      final result = await widget.controller.synchronize();
      if (!mounted) return;
      setState(() {
        _result = result;
        if (result == null) _message = '未能保存同步结果，请稍后重试。';
      });
    } on RequestCancelled {
      if (mounted) setState(() => _message = '已取消同步');
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = widget.controller.error ?? errorMessage(error),
        );
      }
    }
  }

  Future<void> _retry() async {
    if (widget.controller.needsLogin) {
      final signedIn = await showMoocAccount(context, widget.controller);
      if (!signedIn || !mounted) return;
    }
    await _synchronize();
  }

  @override
  void dispose() {
    widget.controller.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final model = widget.controller;
      final theme = Theme.of(context);
      final pending = _result == null && _message == null;
      return SafeArea(
        top: false,
        child: SheetLayout(
          header: SheetHeader(
            title: const Text('同步中国大学MOOC DDL'),
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pending)
                  Row(
                    children: [
                      const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          model.progress.isEmpty ? '正在读取课程…' : model.progress,
                        ),
                      ),
                      TextButton(
                        onPressed: model.cancel,
                        child: const Text('取消'),
                      ),
                    ],
                  ),
                if (_message case final message?) Text(message),
                if (_result case final result?) ...[
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
                if (_message != null || (_result?.failures.isNotEmpty ?? false))
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: model.busy ? null : _retry,
                      child: Text(model.needsLogin ? '重新登录' : '重试'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
