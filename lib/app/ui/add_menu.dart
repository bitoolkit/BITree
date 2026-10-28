import 'package:flutter/material.dart';

import '../../agenda/model.dart';
import '../../agenda/ui/agenda_editor.dart';
import '../../schedule/selection.dart';
import '../../schedule/ui/course_editor.dart';
import '../../ui/app_menu_anchor.dart';
import '../controller.dart';

class AddMenu extends StatelessWidget {
  const AddMenu({
    super.key,
    required this.controller,
    this.menuController,
    this.selection,
    this.date,
    this.includeCourse = true,
    this.onClose,
    this.builder,
    this.child,
  });

  final AppController controller;
  final MenuController? menuController;
  final TimetableSelection? selection;
  final DateTime? date;
  final bool includeCourse;
  final VoidCallback? onClose;
  final AppMenuAnchorBuilder? builder;
  final Widget? child;

  Future<void> _addAgenda(BuildContext context, AgendaKind kind) => editAgenda(
    context,
    controller,
    selection: selection,
    date: date,
    term: includeCourse ? controller.timetable.schedule?.term : null,
    kind: kind,
  );

  @override
  Widget build(BuildContext context) {
    final agendaEnabled = controller.agenda.ready && !controller.agenda.busy;
    return AppMenuAnchor(
      controller: menuController,
      onClose: onClose,
      menuChildren: [
        if (includeCourse)
          AppMenuItemButton(
            onPressed: controller.timetable.busy
                ? null
                : () => editCourse(context, controller, selection: selection),
            leadingIcon: const Icon(Icons.school_outlined),
            child: const Text('添加课程'),
          ),
        AppMenuItemButton(
          onPressed: agendaEnabled
              ? () => _addAgenda(context, AgendaKind.event)
              : null,
          leadingIcon: const Icon(Icons.event_outlined),
          child: const Text('添加日程'),
        ),
        if (selection == null)
          AppMenuItemButton(
            onPressed: agendaEnabled
                ? () => _addAgenda(context, AgendaKind.deadline)
                : null,
            leadingIcon: const Icon(Icons.flag_outlined),
            child: const Text('添加 DDL'),
          ),
      ],
      builder: builder,
      child: child,
    );
  }
}

class AddButton extends StatelessWidget {
  const AddButton({
    super.key,
    required this.controller,
    this.date,
    this.includeCourse = true,
  });

  final AppController controller;
  final DateTime? date;
  final bool includeCourse;

  @override
  Widget build(BuildContext context) => AddMenu(
    controller: controller,
    date: date,
    includeCourse: includeCourse,
    builder: (context, menu, isOpen) => IconButton(
      tooltip: '添加',
      onPressed: controller.timetable.busy || controller.agenda.busy
          ? null
          : () => isOpen ? menu.close() : menu.open(),
      icon: const Icon(Icons.add_rounded),
    ),
  );
}
