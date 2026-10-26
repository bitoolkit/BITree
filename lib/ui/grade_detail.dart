import 'package:flutter/material.dart';

import '../academics/model.dart';
import '../app_controller.dart';
import 'app_dropdown_field.dart';
import 'grade_simulation_screen.dart';
import 'sheet_layout.dart';
import 'design.dart';

Future<void> showGradeDetails(
  BuildContext pageContext,
  AppController controller,
  CourseGrade grade,
) => showModalBottomSheet<void>(
  context: pageContext,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) => ListenableBuilder(
    listenable: controller.academics,
    builder: (context, _) => SafeArea(
      top: false,
      child: SheetLayout(
        header: SheetHeader(
          title: const Text('课程成绩'),
          actions: [
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        content: Padding(
          padding: appSheetContentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                grade.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(grade.term, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 20),
              Text(
                grade.result,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: grade.failed
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              for (final item in [
                ('课程编号', grade.number),
                ('课程学分', '${creditText(grade.credits)} 学分'),
                ('课程属性', grade.attribute),
                ('课程类别', grade.category),
                ('考试性质', grade.examType),
                (
                  '课程绩点',
                  grade.countsForGpa ? grade.points!.toStringAsFixed(1) : '不计入',
                ),
              ])
                if (item.$2.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(
                            item.$1,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Expanded(child: SelectableText(item.$2)),
                      ],
                    ),
                  ),
              const SizedBox(height: 16),
              AppDropdownField<String>(
                label: '学分核对分类',
                value: controller.academics.record.categoryOf(grade),
                entries: [
                  for (final category in {
                    controller.academics.record.categoryOf(grade),
                    ...controller.academics.record.categoryTargets.keys,
                    for (final course in controller.academics.record.grades)
                      controller.academics.record.categoryOf(course),
                  })
                    DropdownMenuEntry(value: category, label: category),
                ],
                onChanged: controller.academics.busy
                    ? null
                    : (category) {
                        final record = controller.academics.record;
                        final overrides = {
                          ...record.categoryOverrides,
                          grade.courseKey: category,
                        };
                        controller.academics.save(
                          record.copyWith(categoryOverrides: overrides),
                        );
                      },
              ),
            ],
          ),
        ),
        actions: Padding(
          padding: appSheetActionPadding,
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  pageContext,
                  MaterialPageRoute<void>(
                    builder: (_) => GradeSimulationScreen(
                      controller: controller,
                      retake: grade,
                    ),
                  ),
                );
              },
              child: const Text('试算重修成绩'),
            ),
          ),
        ),
      ),
    ),
  ),
);
