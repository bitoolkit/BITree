import 'package:flutter/material.dart';

import '../agenda/model.dart';
import '../app_controller.dart';
import 'agenda_list_tile.dart';
import 'campus_time_builder.dart';
import 'sheet_layout.dart';

Future<void> showAgendaDay(
  BuildContext context,
  AppController controller,
  DateTime date,
) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (sheetContext) => ListenableBuilder(
    listenable: controller.agenda,
    builder: (context, _) => CampusTimeBuilder(
      active: true,
      builder: (context, now) {
        final entries = controller.agenda.pendingOn(date, now: now);
        return SafeArea(
          top: false,
          child: SheetLayout(
            header: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      agendaDateLabel(date),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            content: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in entries)
                    AgendaListTile(
                      key: ValueKey(entry.id),
                      controller: controller,
                      entry: entry,
                      now: now,
                    ),
                  if (entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('没有未完成的日程')),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  ),
);
