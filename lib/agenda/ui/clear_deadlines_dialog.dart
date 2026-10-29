import 'package:flutter/material.dart';

import '../../ui/app_notice.dart';
import '../controller.dart';
import '../deadline_clear_scope.dart';

Future<void> showClearDeadlines(
  BuildContext context,
  AgendaController agenda,
) async {
  if (!agenda.ready || agenda.busy) {
    showAppNotice(context, '日程尚未加载或正在保存，请稍后重试。');
    return;
  }
  final count = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ClearDeadlinesDialog(agenda: agenda),
  );
  if (!context.mounted || count == null) return;
  showAppNotice(context, '已删除 $count 条 DDL。');
}

class _ClearDeadlinesDialog extends StatefulWidget {
  const _ClearDeadlinesDialog({required this.agenda});

  final AgendaController agenda;

  @override
  State<_ClearDeadlinesDialog> createState() => _ClearDeadlinesDialogState();
}

class _ClearDeadlinesDialogState extends State<_ClearDeadlinesDialog> {
  final _selected = <DeadlineClearScope>{};
  bool _saving = false;

  Future<void> _clear(
    Set<DeadlineClearScope> scopes,
    Set<String> expectedIds,
  ) async {
    if (_saving || scopes.isEmpty || expectedIds.isEmpty) return;
    final agenda = widget.agenda;
    if (!agenda.ready || agenda.busy) {
      showAppNotice(context, '日程尚未加载或正在保存，请稍后重试。');
      return;
    }
    setState(() => _saving = true);
    final cleared = await agenda.clearDeadlines(
      scopes,
      expectedIds: expectedIds,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (cleared) Navigator.pop<int>(context, expectedIds.length);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.agenda,
    builder: (context, _) {
      final agenda = widget.agenda;
      final scheme = Theme.of(context).colorScheme;
      final enabled = !_saving && agenda.ready && !agenda.busy;
      final scopes = Set<DeadlineClearScope>.of(_selected);
      final expectedIds = agenda.deadlineIdsIn(scopes);
      final count = expectedIds.length;
      final allSelected = _selected.length == DeadlineClearScope.values.length;
      return PopScope(
        canPop: !_saving,
        child: AlertDialog(
          title: const Text('删除 DDL'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('勾选要删除的来源，可多选。数量包含所有学期、已完成和已删除的 DDL。'),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('全选'),
                tristate: true,
                value: allSelected ? true : (_selected.isEmpty ? false : null),
                onChanged: enabled
                    ? (_) => setState(() {
                        if (allSelected) {
                          _selected.clear();
                        } else {
                          _selected.addAll(DeadlineClearScope.values);
                        }
                      })
                    : null,
              ),
              const Divider(),
              for (final scope in DeadlineClearScope.values)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    '${scope.label}（${agenda.countDeadlines(scope)} 条）',
                  ),
                  subtitle: Text(scope.description),
                  value: _selected.contains(scope),
                  onChanged: enabled
                      ? (checked) => setState(() {
                          if (checked == true) {
                            _selected.add(scope);
                          } else {
                            _selected.remove(scope);
                          }
                        })
                      : null,
                ),
              const SizedBox(height: 12),
              Text('已选择 ${scopes.length} 类，共 $count 条 DDL。'),
              const SizedBox(height: 12),
              Text(
                '删除后无法撤销，也无法从“已删除的 DDL”中恢复。未勾选的来源、考试和其他日程不受影响。',
                style: TextStyle(color: scheme.error),
              ),
              const SizedBox(height: 8),
              const Text(
                '平台来源的 DDL 之后可重新同步；大物实验 DDL 可根据课表手动重新生成；手动创建的 DDL 无法恢复。',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: enabled && scopes.isNotEmpty && count > 0
                  ? () => _clear(scopes, expectedIds)
                  : null,
              child: Text(_saving ? '正在删除…' : '删除 $count 条 DDL'),
            ),
          ],
        ),
      );
    },
  );
}
