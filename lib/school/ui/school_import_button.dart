import 'package:flutter/material.dart';

import '../../agenda/ui/deleted_deadlines.dart';
import '../../agenda/ui/physics_lab_import.dart';
import '../../app/controller.dart';
import '../../sync/controller.dart';
import '../../sync/ui/sync_tasks.dart';
import '../../ui/app_menu_anchor.dart';

class SchoolImportButton extends StatelessWidget {
  const SchoolImportButton({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      controller.timetable,
      controller.agenda,
      controller.school,
      controller.mooc,
      controller.sync,
    ]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final physicsEnabled =
        controller.timetable.ready &&
        !controller.timetable.busy &&
        controller.timetable.schedule != null &&
        controller.agenda.ready &&
        !controller.agenda.busy;
    return AppMenuAnchor(
      menuChildren: [
        for (final target in [
          SyncTarget.schedule,
          SyncTarget.exams,
          SyncTarget.lexue,
          SyncTarget.eclass,
        ])
          AppMenuItemButton(
            leadingIcon: Icon(switch (target) {
              SyncTarget.schedule => Icons.input_rounded,
              SyncTarget.exams => Icons.edit_note_rounded,
              _ => Icons.flag_outlined,
            }),
            onPressed:
                !controller.agenda.ready || controller.sync.contains(target)
                ? null
                : () => startSync(context, controller, target: target),
            child: Text(target.label),
          ),
        AppMenuItemButton(
          leadingIcon: const Icon(Icons.flag_outlined),
          onPressed: physicsEnabled
              ? () => updatePhysicsLabDeadlines(context, controller)
              : null,
          child: const Text('更新大物实验 DDL'),
        ),
        const Divider(),
        AppMenuItemButton(
          leadingIcon: const Icon(Icons.menu_book_outlined),
          onPressed:
              !controller.agenda.ready ||
                  controller.sync.contains(SyncTarget.mooc)
              ? null
              : () => startSync(context, controller, target: SyncTarget.mooc),
          child: Text(SyncTarget.mooc.label),
        ),
        AppMenuItemButton(
          leadingIcon: const Icon(Icons.sync_rounded),
          onPressed: () => showSyncTasks(context, controller),
          child: const Text('同步任务'),
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
        tooltip: controller.sync.activeCount > 0 ? '查看同步进度' : '导入',
        onPressed: () {
          if (controller.sync.activeCount > 0) {
            if (isOpen) menu.close();
            showSyncTasks(context, controller);
          } else {
            isOpen ? menu.close() : menu.open();
          }
        },
        icon: Badge.count(
          count: controller.sync.activeCount,
          isLabelVisible: controller.sync.activeCount > 0,
          child: controller.sync.running
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.input_rounded),
        ),
      ),
    );
  }
}
