import 'package:flutter/material.dart';

import '../agenda/model.dart';
import '../app_controller.dart';
import '../schedule/model.dart';
import 'agenda_editor.dart';
import 'agenda_operations.dart';
import 'completion_text.dart';
import 'external_link.dart';
import 'sheet_layout.dart';
import 'design.dart';

Future<void> showAgendaEntry(
  BuildContext pageContext,
  AppController controller,
  AgendaEntry entry,
) => showModalBottomSheet<void>(
  context: pageContext,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (sheetContext) => ListenableBuilder(
    listenable: controller.agenda,
    builder: (context, _) {
      // Keep the closing sheet readable after its entry has been deleted.
      final current =
          controller.agenda.entries
              .where((value) => value.id == entry.id)
              .firstOrNull ??
          entry;
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final now = campusNow();
      final overdue = current.overdue(now);
      final status = current.done
          ? '已完成'
          : overdue
          ? '已逾期'
          : current.isFinished(now)
          ? '已结束'
          : null;
      final statusColor = overdue ? scheme.error : scheme.onSurfaceVariant;
      void edit() {
        Navigator.pop(sheetContext);
        editAgenda(pageContext, controller, entry: current);
      }

      Widget metadata(IconData icon, Widget content) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: content),
          ],
        ),
      );

      return SafeArea(
        top: false,
        child: SheetLayout(
          header: SheetHeader(
            title: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  current.kind.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (status != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        current.done
                            ? Icons.check_circle_outline_rounded
                            : Icons.schedule_rounded,
                        size: 15,
                        color: statusColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        status,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: '删除',
                onPressed: controller.agenda.busy
                    ? null
                    : () async {
                        if (await deleteAgendaEntry(
                              context,
                              controller,
                              current,
                            ) &&
                            sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
          content: Padding(
            padding: appSheetContentPadding,
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  CompletionText(
                    current.title,
                    completed: current.done,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 26,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (current.course.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      current.course,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _EntryTime(entry: current, now: now),
                  if (current.location.isNotEmpty ||
                      current.source != null ||
                      current.notes.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                  ],
                  if (current.location.isNotEmpty)
                    metadata(
                      Icons.location_on_outlined,
                      Text(current.location, style: theme.textTheme.bodyMedium),
                    ),
                  if (current.source case final source?)
                    metadata(
                      Icons.link_rounded,
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              source.label,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          if (current.url case final url?)
                            TextButton.icon(
                              onPressed: () => openExternalLink(
                                context,
                                url,
                                failureTitle: '无法打开作业',
                              ),
                              iconAlignment: IconAlignment.end,
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 16,
                              ),
                              label: const Text('打开作业'),
                            ),
                        ],
                      ),
                    ),
                  if (current.notes.isNotEmpty) ...[
                    if (current.location.isNotEmpty || current.source != null)
                      const SizedBox(height: 16),
                    Text(
                      '备注',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(current.notes, style: theme.textTheme.bodyLarge),
                  ],
                ],
              ),
            ),
          ),
          actions: SafeArea(
            top: false,
            child: Padding(
              padding: appSheetActionPadding,
              child: current.isDeadline
                  ? OverflowBar(
                      alignment: MainAxisAlignment.spaceBetween,
                      overflowAlignment: OverflowBarAlignment.end,
                      spacing: 12,
                      overflowSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: controller.agenda.busy ? null : edit,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('编辑'),
                        ),
                        FilledButton.icon(
                          style: current.done
                              ? FilledButton.styleFrom(
                                  backgroundColor: scheme.secondaryContainer,
                                  foregroundColor: scheme.onSecondaryContainer,
                                )
                              : null,
                          onPressed: controller.agenda.busy
                              ? null
                              : () => toggleAgendaDone(
                                  controller.agenda,
                                  current,
                                ),
                          icon: Icon(
                            current.done
                                ? Icons.undo_rounded
                                : Icons.check_rounded,
                            size: 20,
                          ),
                          label: Text(current.done ? '标为未完成' : '标记完成'),
                        ),
                      ],
                    )
                  : Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: controller.agenda.busy ? null : edit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('编辑'),
                      ),
                    ),
            ),
          ),
        ),
      );
    },
  ),
);

class _EntryTime extends StatelessWidget {
  const _EntryTime({required this.entry, required this.now});

  final AgendaEntry entry;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = entry.overdue(now) ? scheme.error : scheme.onSurface;
    final time = entry.isDeadline
        ? entry.allDay
              ? '当天结束前'
              : clockText(entry.startsAt)
        : entry.timeLabel;
    final lastDay = entry.allDay && !entry.isDeadline
        ? entry.endsAt!.subtract(const Duration(days: 1))
        : entry.startsAt;
    final date = calendarDate(lastDay) == calendarDate(entry.startsAt)
        ? agendaDateLabel(entry.startsAt)
        : '${agendaDateLabel(entry.startsAt)} – ${agendaDateLabel(lastDay)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: entry.overdue(now) ? scheme.error : scheme.primary,
            width: 3,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              date,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: time),
                  if (entry.isDeadline && !entry.allDay)
                    TextSpan(
                      text: '  截止',
                      style: theme.textTheme.bodyMedium?.copyWith(color: color),
                    ),
                ],
              ),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: entry.isDeadline && !entry.allDay ? 30 : 22,
                height: 1.25,
                fontWeight: FontWeight.w500,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
