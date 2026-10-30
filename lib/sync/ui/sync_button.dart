import 'package:flutter/material.dart';

import '../../agenda/ui/deleted_deadlines.dart';
import '../../app/controller.dart';
import '../../ui/app_menu_anchor.dart';
import 'sync.dart';

class SyncButton extends StatelessWidget {
  const SyncButton({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller.sync, controller.agenda]),
    builder: (context, _) => AppMenuAnchor(
      menuChildren: [
        AppMenuItemButton(
          leadingIcon: const Icon(Icons.sync_rounded),
          onPressed: controller.agenda.ready
              ? () => startSync(context, controller)
              : null,
          child: const Text('同步全部'),
        ),
        AppMenuItemButton(
          leadingIcon: const Icon(Icons.tune_rounded),
          onPressed: controller.agenda.ready
              ? () => customizeSync(context, controller)
              : null,
          child: const Text('自定义同步'),
        ),
        const Divider(),
        AppMenuItemButton(
          leadingIcon: const Icon(Icons.restore_from_trash_outlined),
          onPressed:
              !controller.agenda.ready ||
                  controller.agenda.busy ||
                  controller.agenda.deletedDeadlines.isEmpty
              ? null
              : () => showDeletedDeadlines(context, controller.agenda),
          child: const Text('已删除的 DDL'),
        ),
      ],
      builder: (context, menu, isOpen) => IconButton(
        tooltip: controller.sync.busy ? '查看同步进度' : '同步',
        onPressed: () {
          if (controller.sync.busy) {
            if (isOpen) menu.close();
            showSyncProgress(context, controller);
          } else {
            isOpen ? menu.close() : menu.open();
          }
        },
        icon: controller.sync.busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.sync_rounded),
      ),
    ),
  );
}
