import 'package:flutter/material.dart';

import '../../agenda/ui/deleted_deadlines.dart';
import '../../app/controller.dart';
import '../../l10n/l10n.dart';
import '../../ui/app_menu_anchor.dart';
import 'sync.dart';

class SyncButton extends StatelessWidget {
  const SyncButton({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller.sync, controller.agenda]),
    builder: (context, _) {
      final l10n = context.l10n;
      return AppMenuAnchor(
        menuChildren: [
          AppMenuItemButton(
            leadingIcon: const Icon(Icons.sync_rounded),
            onPressed: controller.agenda.ready
                ? () => startSync(context, controller)
                : null,
            child: Text(l10n.syncAll),
          ),
          AppMenuItemButton(
            leadingIcon: const Icon(Icons.tune_rounded),
            onPressed: controller.agenda.ready
                ? () => customizeSync(context, controller)
                : null,
            child: Text(l10n.customSync),
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
            child: Text(l10n.deletedDdlMenu),
          ),
        ],
        builder: (context, menu, isOpen) => IconButton(
          tooltip: controller.sync.busy
              ? l10n.viewSyncProgress
              : l10n.syncTooltip,
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
      );
    },
  );
}
