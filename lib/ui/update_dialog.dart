import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../data/app_release.dart';
import 'external_link.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.releases,
    required this.preferDevelopment,
  });

  final List<AppRelease> releases;
  final bool preferDevelopment;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  int _selected = 0;

  AppRelease get _release => widget.releases[_selected];

  @override
  void initState() {
    super.initState();
    final preferred = widget.releases.indexWhere(
      (release) => release.isDevelopment == widget.preferDevelopment,
    );
    if (preferred != -1) _selected = preferred;
  }

  Future<void> _download() async {
    final opened = await openExternalLink(
      context,
      _release.downloadUrl,
      failureTitle: '无法打开下载链接',
    );
    if (opened && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      textStyle: WidgetStatePropertyAll(
        theme.textTheme.labelMedium!.copyWith(fontSize: 13),
      ),
    );

    return AlertDialog(
      title: const Text('发现可用更新'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.releases.length > 1) ...[
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final (index, release) in widget.releases.indexed)
                  ButtonSegment(
                    value: index,
                    label: Text(release.isDevelopment ? '测试版' : '正式版'),
                  ),
              ],
              selected: {_selected},
              onSelectionChanged: (selection) =>
                  setState(() => _selected = selection.single),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            '${_release.isDevelopment ? '测试版' : '正式版'} ${_release.version}',
            style: theme.textTheme.titleMedium,
          ),
          if (_release.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            MarkdownBody(
              data: _release.notes,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(theme)
                  .copyWith(h2: theme.textTheme.titleSmall),
              onTapLink: (_, href, _) async {
                if (href == null) return;
                await openExternalLink(
                  context,
                  Uri.parse(href),
                  failureTitle: '无法打开链接',
                );
              },
            ),
          ],
        ],
      ),
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
          style: actionStyle,
          onPressed: () => Navigator.pop(context),
          child: const Text('稍后'),
        ),
        TextButton(
          style: actionStyle,
          onPressed: () =>
              openExternalLink(context, _release.url, failureTitle: '无法打开发布页'),
          child: const Text('发布页'),
        ),
        FilledButton(
          style: actionStyle,
          onPressed: _download,
          child: Text(_release.isDevelopment ? '下载测试版' : '下载正式版'),
        ),
      ],
    );
  }
}
