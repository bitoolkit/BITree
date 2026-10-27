import 'package:flutter/material.dart';

import '../../schedule/model.dart';
import '../../ui/app_dropdown_field.dart';
import '../model.dart';

class ProjectedCourseDialog extends StatefulWidget {
  const ProjectedCourseDialog({
    super.key,
    required this.grades,
    required this.courses,
    this.course,
  });
  final List<CourseGrade> grades;
  final Iterable<Course> courses;
  final ProjectedCourse? course;

  @override
  State<ProjectedCourseDialog> createState() => _ProjectedCourseDialogState();
}

class _ProjectedCourseDialogState extends State<ProjectedCourseDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.course?.name);
  late final _credits = TextEditingController(
    text: widget.course == null ? '' : creditText(widget.course!.credits),
  );
  late final _score = TextEditingController(
    text: creditText(widget.course?.score ?? 85),
  );
  late String? _selection = widget.course?.replaces;

  @override
  void dispose() {
    _name.dispose();
    _credits.dispose();
    _score.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final choices =
        <String, ({String name, double? credits, String? replaces})>{
          for (final grade in highestGrades(widget.grades))
            grade.courseKey: (
              name: grade.name,
              credits: grade.credits,
              replaces: grade.courseKey,
            ),
        };
    for (final course in widget.courses) {
      final key = course.number.isEmpty ? course.name : course.number;
      choices.putIfAbsent(
        key,
        () => (name: course.name, credits: null, replaces: null),
      );
    }
    return AlertDialog(
      scrollable: true,
      title: Text(widget.course == null ? '添加试算课程' : '修改试算课程'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (choices.isNotEmpty) ...[
              AppDropdownField<String?>(
                label: '选择课程（选填）',
                value: choices.containsKey(_selection) ? _selection : null,
                entries: [
                  const DropdownMenuEntry(value: null, label: '手动填写'),
                  for (final choice in choices.entries)
                    DropdownMenuEntry(
                      value: choice.key,
                      label:
                          '${choice.value.name}${choice.value.replaces == null ? '' : '（重修）'}',
                    ),
                ],
                onChanged: (key) {
                  setState(() {
                    final choice = choices[key];
                    _selection = key;
                    if (choice != null) {
                      _name.text = choice.name;
                      _credits.text = choice.credits == null
                          ? ''
                          : creditText(choice.credits!);
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: '课程名称'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入课程名称' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _credits,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '课程学分'),
              validator: (text) {
                final value = double.tryParse(text ?? '');
                return value == null || !value.isFinite || value <= 0
                    ? '请输入大于 0 的学分'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _score,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '预计成绩'),
              validator: (text) {
                final value = double.tryParse(text ?? '');
                return value == null ||
                        !value.isFinite ||
                        value < 0 ||
                        value > 100
                    ? '请输入 0～100 之间的成绩'
                    : null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              ProjectedCourse(
                id:
                    widget.course?.id ??
                    'simulation-${DateTime.now().microsecondsSinceEpoch}',
                name: _name.text.trim(),
                credits: double.parse(_credits.text),
                score: double.parse(_score.text),
                replaces: choices[_selection]?.replaces,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
