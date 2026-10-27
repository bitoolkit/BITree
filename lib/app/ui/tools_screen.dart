import 'package:flutter/material.dart';

import '../../academics/ui/credit_progress_screen.dart';
import '../../academics/ui/exams_screen.dart';
import '../../academics/ui/grade_simulation_screen.dart';
import '../../academics/ui/grades_screen.dart';
import '../../classrooms/ui/classroom_screen.dart';
import '../../ui/app_page.dart';
import '../../wencui/ui/wencui_map_screen.dart';
import '../controller.dart';

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
        ListTile(
          leading: const Icon(Icons.map_outlined),
          title: const Text('文萃导航'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => WencuiMapScreen(controller: controller),
            ),
          ),
        ),
      ],
    ),
  );
}
