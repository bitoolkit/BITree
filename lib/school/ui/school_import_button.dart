import 'package:flutter/material.dart';

import '../../agenda/ui/deleted_deadlines.dart';
import '../../agenda/ui/physics_lab_import.dart';
import '../../app/controller.dart';
import '../../ui/app_menu_anchor.dart';
import 'school_screen.dart';

class SchoolImportButton extends StatelessWidget {
  const SchoolImportButton({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      controller.timetable,
      controller.agenda,
      controller.school,
    ]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final busy = controller.timetable.busy || controller.school.busy;
    final physicsEnabled =
        controller.timetable.ready &&
        !controller.timetable.busy &&
        controller.timetable.schedule != null &&
        controller.agenda.ready &&
        !controller.agenda.busy;
    return AppMenuAnchor(
      menuChildren: [
        AppMenuItemButton(
          leadingIcon: const Icon(Icons.input_rounded),
          onPressed: busy
              ? null
              : () => openSchoolPage(
                  context,
                  controller,
                  action: SchoolAction.importSchedule,
                ),
          child: Text(SchoolAction.importSchedule.label),
        ),
        AppMenuItemButton(
          leadingIcon: const Icon(Icons.edit_note_rounded),
          onPressed: busy || !controller.agenda.ready
              ? null
              : () => openSchoolPage(
                  context,
                  controller,
                  action: SchoolAction.importExams,
                ),
          child: Text(SchoolAction.importExams.label),
        ),
        const Divider(),
        for (final action in [
          SchoolAction.importLexueDeadlines,
          SchoolAction.importEclassDeadlines,
        ])
          AppMenuItemButton(
            leadingIcon: const Icon(Icons.flag_outlined),
            onPressed: busy || !controller.agenda.ready
                ? null
                : () => openSchoolPage(context, controller, action: action),
            child: Text(action.label),
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
        tooltip: '导入',
        onPressed: () => isOpen ? menu.close() : menu.open(),
        icon: controller.school.busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.input_rounded),
      ),
    );
  }
}
