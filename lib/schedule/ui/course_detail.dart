import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/controller.dart';
import '../../study/ui/study_schedule.dart';
import '../../ui/app_notice.dart';
import '../../ui/campus_time_builder.dart';
import '../../ui/design.dart';
import '../../ui/sheet_layout.dart';
import '../../ui/theme.dart';
import '../../wencui/place.dart';
import '../../wencui/ui/location_card.dart';
import '../../wencui/ui/wencui_map_screen.dart';
import '../building_palette.dart';
import '../model.dart';
import '../selection.dart';
import 'course_editor.dart';

Future<void> showCourse(
  BuildContext context,
  AppController controller,
  Course course, {
  DateTime? date,
}) {
  var selected = course;
  final schedule = controller.timetable.schedule;
  final occurrence =
      date ??
      (schedule != null && course.weekday != null
          ? schedule
                .mondayAt(controller.timetable.week)
                .add(Duration(days: course.weekday! - 1))
          : null);
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (_, selectCourse) => CampusTimeBuilder(
        active: true,
        builder: (_, now) => ListenableBuilder(
          listenable: controller.timetable,
          builder: (_, _) => _CourseDetails(
            controller: controller,
            course: selected,
            date: occurrence,
            now: now,
            onNext: (next) => selectCourse(() => selected = next),
            onMap:
                WencuiPlace.parse(selected.room, campus: selected.campus) ==
                    null
                ? null
                : () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => WencuiMapScreen(
                          controller: controller,
                          initialCourse: selected,
                        ),
                      ),
                    );
                  },
            onEdit: () {
              Navigator.pop(sheetContext);
              editCourse(context, controller, course: selected);
            },
            onStudy: () {
              Navigator.pop(sheetContext);
              openScheduledStudy(
                context,
                controller,
                selected,
                date: occurrence,
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _CourseDetails extends StatelessWidget {
  const _CourseDetails({
    required this.controller,
    required this.course,
    required this.onEdit,
    required this.onStudy,
    required this.onMap,
    required this.date,
    required this.now,
    required this.onNext,
  });

  final AppController controller;
  final Course course;
  final VoidCallback onEdit;
  final VoidCallback onStudy;
  final VoidCallback? onMap;
  final DateTime? date;
  final DateTime now;
  final ValueChanged<Course> onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = courseColors(context, course);
    final occurrence = date != null && course.startSection != null
        ? TimetableSelection(
            date: date!,
            startSection: course.startSection!,
            endSection: course.endSection!,
          )
        : null;
    final progress = occurrence?.progressAt(now);
    final status = progress != null
        ? '上课中 · ${sectionTimes[course.endSection! - 1].$2} 下课'
        : occurrence != null && !now.isBefore(occurrence.endsAt)
        ? '已结束'
        : '课程';
    final schedule = controller.timetable.schedule;
    final next = date == null || course.endSection == null || schedule == null
        ? null
        : schedule
              .coursesAt(schedule.weekAt(date!), weekday: date!.weekday)
              .where((item) => item.startSection! > course.endSection!)
              .firstOrNull;
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
        key: ValueKey(course.id),
        header: SheetHeader(
          title: Row(
            children: [
              Icon(
                Icons.school_outlined,
                size: 18,
                color: progress != null
                    ? colors.accent
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: progress != null
                        ? colors.accent
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
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
              _CopyableCourseName(name: course.name),
              const SizedBox(height: 10),
              detail(
                Icons.schedule_outlined,
                course.timeLabel,
                secondary:
                    '${course.weekday == null ? '' : '${weekdays[course.weekday! - 1]} · '}${course.sectionLabel} · ${weeksLabel(course.weeks)}',
              ),
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
              if (progress != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                  color: colors.accent,
                  backgroundColor: colors.fill,
                ),
                const SizedBox(height: 6),
                Text(
                  '还有 ${(occurrence!.endsAt.difference(now).inSeconds / 60).ceil()} 分钟下课',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (next != null)
                _NextCourse(
                  course: course,
                  next: next,
                  onTap: () => onNext(next),
                ),
            ],
          ),
        ),
        actions: Padding(
          padding: appSheetActionPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: controller.timetable.busy ? null : onStudy,
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                label: const Text('课程学习'),
              ),
              const SizedBox(height: 8),
              Row(
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
            ],
          ),
        ),
      ),
    );
  }
}

class _NextCourse extends StatelessWidget {
  const _NextCourse({
    required this.course,
    required this.next,
    required this.onTap,
  });

  final Course course;
  final Course next;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = matchCampusBuilding(course.room, campus: course.campus);
    final to = matchCampusBuilding(next.room, campus: next.campus);
    final relation = from == null || to == null
        ? null
        : from == to
        ? '同一栋楼'
        : from.area == to.area
        ? '同一片区换楼'
        : '跨片区换楼';
    Widget building(Course course, BuildingPalette place) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: courseColors(context, course).accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(child: Text(place.name)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text('下一门课', style: theme.textTheme.bodySmall),
              if (relation != null)
                Text(relation, style: theme.textTheme.labelMedium),
            ],
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: AppCorners.control,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(next.name, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            '${next.timeLabel}${next.room.isEmpty ? '' : ' · ${next.room}'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ),
          if (from != null && to != null && from != to)
            DefaultTextStyle.merge(
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  building(course, from),
                  const Icon(Icons.arrow_forward_rounded, size: 14),
                  building(next, to),
                ],
              ),
            ),
        ],
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
