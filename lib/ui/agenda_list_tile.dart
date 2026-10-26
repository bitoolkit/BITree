import 'package:flutter/material.dart';

import '../agenda/model.dart';
import '../app_controller.dart';
import '../schedule/model.dart';
import 'agenda_detail.dart';
import 'agenda_operations.dart';
import 'agenda_time.dart';
import 'calendar_list.dart';
import 'completion_text.dart';
import 'swipe_action_tile.dart';

class AgendaListTile extends StatelessWidget {
  const AgendaListTile({
    super.key,
    required this.controller,
    required this.entry,
    required this.now,
  });

  final AppController controller;
  final AgendaEntry entry;
  final DateTime now;

  Future<bool> _complete({bool haptic = false}) =>
      toggleAgendaDone(controller.agenda, entry, haptic: haptic);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = [
      if (entry.course.isNotEmpty)
        entry.course
      else if (entry.source != null)
        entry.source!.label,
      if (entry.location.isNotEmpty) entry.location,
    ].join('  ');
    final dueToday =
        entry.isDeadline &&
        !entry.done &&
        calendarDate(entry.startsAt) == calendarDate(now);
    final timeColor = entry.overdue(now)
        ? scheme.error
        : dueToday
        ? scheme.primary
        : scheme.onSurface;
    final caption = agendaTimeCaption(entry, now);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SwipeActionTile(
        enabled: !controller.agenda.busy,
        leftAction: TileSwipeAction(
          label: '删除',
          releaseLabel: '松手删除',
          icon: Icons.delete_outline,
          background: scheme.error,
          foreground: scheme.onError,
          onInvoke: () =>
              deleteAgendaEntry(context, controller, entry, confirm: false),
        ),
        rightAction: entry.isDeadline
            ? TileSwipeAction(
                label: entry.done ? '未完成' : '完成',
                releaseLabel: entry.done ? '松手恢复' : '松手完成',
                icon: entry.done ? Icons.undo_rounded : Icons.check_rounded,
                background: scheme.primaryContainer,
                foreground: scheme.onPrimaryContainer,
                onInvoke: _complete,
              )
            : null,
        child: Material(
          color: scheme.surface,
          child: InkWell(
            hoverColor: Colors.transparent,
            onTap: () => showAgendaEntry(context, controller, entry),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox.square(
                    dimension: 44,
                    child: entry.isDeadline
                        ? Tooltip(
                            message: entry.done ? '标为未完成' : '标记完成',
                            child: Checkbox(
                              value: entry.done,
                              shape: const CircleBorder(),
                              onChanged: controller.agenda.busy
                                  ? null
                                  : (_) => _complete(haptic: true),
                            ),
                          )
                        : Icon(
                            agendaIcon(entry.kind),
                            size: 22,
                            color: scheme.onSurfaceVariant,
                          ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CompletionText(
                          entry.title,
                          completed: entry.done,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: MediaQuery.textScalerOf(context).scale(72),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          agendaClockLabel(entry),
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                            color: timeColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (caption.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            caption,
                            maxLines: 2,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: entry.overdue(now)
                                  ? scheme.error
                                  : dueToday
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
