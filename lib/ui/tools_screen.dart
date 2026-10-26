import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'app_page.dart';
import 'classroom_screen.dart';
import 'grades_screen.dart';
import 'grade_simulation_screen.dart';
import 'credit_progress_screen.dart';
import 'exams_screen.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => AppPage(
    title: const Text('工具'),
    child: ListView(
      children: [
        for (final tool in [
          (
            title: '成绩与学业',
            icon: Icons.school_outlined,
            page: GradesScreen(controller: controller),
          ),
          (
            title: '成绩试算',
            icon: Icons.calculate_outlined,
            page: GradeSimulationScreen(controller: controller),
          ),
          (
            title: '毕业学分进度',
            icon: Icons.checklist_rounded,
            page: CreditProgressScreen(controller: controller),
          ),
          (
            title: '考试安排与冲突检查',
            icon: Icons.event_available_outlined,
            page: ExamsScreen(controller: controller),
          ),
        ])
          ListTile(
            leading: Icon(tool.icon),
            title: Text(tool.title),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () =>
                Navigator.of(context)
                    .push<void>(MaterialPageRoute(builder: (_) => tool.page)),
          ),
        ListTile(
          leading: const Icon(Icons.meeting_room_outlined),
          title: const Text('空教室查询'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => ClassroomScreen(controller: controller),
            ),
          ),
        ),
      ],
    ),
  );
}
