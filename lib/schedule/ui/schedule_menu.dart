import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/controller.dart';
import '../../app/ui/widget_guide.dart';
import '../../core/diagnostics.dart';
import '../../ui/app_menu_anchor.dart';
import '../ics.dart';
import '../model.dart';
import 'week_range_dialog.dart';

class ScheduleMenu extends StatefulWidget {
  const ScheduleMenu({super.key, required this.controller});

  final AppController controller;

  @override
  State<ScheduleMenu> createState() => _ScheduleMenuState();
}

class _ScheduleMenuState extends State<ScheduleMenu> {
  bool _exporting = false;

  Future<void> _export(SemesterSchedule schedule) async {
    if (_exporting) return;
    final skipped = schedule.courses
        .where((course) => !course.isScheduled)
        .length;
    final messenger = ScaffoldMessenger.of(context);
    if (skipped == schedule.courses.length) {
      messenger.showSnackBar(
        const SnackBar(content: Text('没有可导出的课程，请先添加课程或设置上课时间。')),
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      final term = schedule.term.replaceAll(
        RegExp(r'[<>:"/\\|?*\x00-\x1f]'),
        '_',
      );
      final saved = await FilePicker.saveFile(
        fileName: 'BITree-$term.ics',
        bytes: Uint8List.fromList(utf8.encode(scheduleToIcs(schedule))),
        mimeType: 'text/calendar',
        dialogTitle: '导出课表',
      );
      if (!mounted || saved == null) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(skipped == 0 ? '已导出课表' : '已导出课表，跳过 $skipped 门时间待定的课程'),
        ),
      );
    } catch (failure, stack) {
      AppDiagnostics.instance.report('导出课表', failure, stack);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final schedule = widget.controller.timetable.schedule;
    final enabled = !widget.controller.timetable.busy;
    return AppMenuAnchor(
      menuChildren: [
        AppMenuItemButton(
          leadingIcon: const Icon(Icons.date_range_outlined),
          onPressed: schedule == null || !enabled
              ? null
              : () => manageTermWeeks(context, widget.controller),
          child: const Text('周数管理'),
        ),
        if (Platform.isAndroid)
          AppMenuItemButton(
            onPressed: () => showWidgetGuide(context),
            leadingIcon: const Icon(Icons.widgets_outlined),
            child: const Text('桌面日程表'),
          ),
        AppMenuItemButton(
          onPressed: schedule == null || !enabled || _exporting
              ? null
              : () => _export(schedule),
          leadingIcon: const Icon(Icons.file_download_outlined),
          child: const Text('导出 ICS'),
        ),
      ],
      builder: (context, menu, isOpen) => IconButton(
        tooltip: '更多',
        onPressed: _exporting
            ? null
            : () => isOpen ? menu.close() : menu.open(),
        icon: const Icon(Icons.more_horiz_rounded),
      ),
    );
  }
}
