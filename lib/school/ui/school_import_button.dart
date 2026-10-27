import 'package:flutter/material.dart';

import '../../agenda/ui/deleted_deadlines.dart';
import '../../app/controller.dart';
import '../../ui/app_menu_anchor.dart';
import 'school_screen.dart';

class SchoolImportButton extends StatelessWidget {
  const SchoolImportButton({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final busy = controller.timetable.busy || controller.school.busy;
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
        AppMenuItemButton(
          leadingIcon: const Icon(Icons.flag_outlined),
          onPressed: busy || !controller.agenda.ready
              ? null
              : () => openSchoolPage(
                  context,
                  controller,
                  action: SchoolAction.importDeadlines,
                ),
          child: Text(SchoolAction.importDeadlines.label),
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
        tooltip: '同步',
        onPressed: busy ? null : () => isOpen ? menu.close() : menu.open(),
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
