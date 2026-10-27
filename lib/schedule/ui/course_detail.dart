import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/controller.dart';
import '../../ui/app_notice.dart';
import '../../ui/design.dart';
import '../../ui/sheet_layout.dart';
import '../../ui/theme.dart';
import '../../wencui/place.dart';
import '../../wencui/ui/location_card.dart';
import '../../wencui/ui/wencui_map_screen.dart';
import '../model.dart';
import 'course_editor.dart';

Future<void> showCourse(
  BuildContext context,
  AppController controller,
  Course course,
) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (sheetContext) => ListenableBuilder(
    listenable: Listenable.merge([controller.timetable]),
    builder: (_, _) => _CourseDetails(
      controller: controller,
      course: course,
      onMap: WencuiPlace.parse(course.room, campus: course.campus) == null
          ? null
          : () {
              Navigator.pop(sheetContext);
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => WencuiMapScreen(
                    controller: controller,
                    initialCourse: course,
                  ),
                ),
              );
            },
      onEdit: () {
        Navigator.pop(sheetContext);
        editCourse(context, controller, course: course);
      },
    ),
  ),
);

class _CourseDetails extends StatelessWidget {
  const _CourseDetails({
    required this.controller,
    required this.course,
    required this.onEdit,
    required this.onMap,
  });

  final AppController controller;
  final Course course;
  final VoidCallback onEdit;
  final VoidCallback? onMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = courseColors(context, course);
    final location = [
      course.campus,
      course.room,
    ].where((part) => part.isNotEmpty).join(' ');

    Widget detail(IconData icon, String text, {String? secondary}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(text, style: theme.textTheme.bodyLarge),
                if (secondary != null) ...[
                  const SizedBox(height: 2),
                  SelectableText(
                    secondary,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return SafeArea(
      top: false,
      child: SheetLayout(
        header: SheetHeader(
          title: Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _CopyableCourseName(name: course.name)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '关闭',
              onPressed: controller.timetable.busy
                  ? null
                  : () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ],
        ),
        content: Padding(
          padding: appSheetContentPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              detail(
                Icons.schedule_outlined,
                '${course.weekday == null ? '' : '${weekdays[course.weekday! - 1]} '}${course.sectionLabel}',
                secondary: course.timeLabel,
              ),
              detail(Icons.date_range_outlined, weeksLabel(course.weeks)),
              if (onMap case final openMap?)
                WencuiLocationCard(
                  place: WencuiPlace.parse(course.room, campus: course.campus)!,
                  onTap: openMap,
                )
              else
                detail(
                  Icons.place_outlined,
                  location.isEmpty ? '教室待定' : location,
                ),
              if (course.teacher.isNotEmpty)
                detail(Icons.person_outline, course.teacher),
              if (course.number.isNotEmpty) detail(Icons.tag, course.number),
              if (course.description.isNotEmpty)
                detail(Icons.notes_rounded, course.description),
            ],
          ),
        ),
        actions: Padding(
          padding: appSheetActionPadding,
          child: Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: controller.timetable.busy ? null : onEdit,
                  child: const Text('编辑课程'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(
                    color: theme.colorScheme.error.withValues(alpha: 0.4),
                  ),
                ),
                onPressed: controller.timetable.busy
                    ? null
                    : () => _deleteCourse(context, controller, course),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('删除'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CopyableCourseName extends StatelessWidget {
  const _CopyableCourseName({required this.name});

  final String name;

  Future<void> _copy(BuildContext context) async {
    String message;
    try {
      await Clipboard.setData(ClipboardData(text: name));
      message = '已复制课程名称';
    } on PlatformException {
      message = '复制失败，请重试';
    }
    if (context.mounted) showAppNotice(context, message);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onLongPress: () => _copy(context),
    child: Text(name, style: Theme.of(context).textTheme.titleLarge),
  );
}

Future<void> _deleteCourse(
  BuildContext context,
  AppController controller,
  Course course,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除这门课程？'),
      content: Text('将从本地课表中删除“${course.name}”。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除课程'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final success = await controller.timetable.deleteCourse(course);
  if (!context.mounted) return;

  if (success) {
    Navigator.pop(context);
  }
}
