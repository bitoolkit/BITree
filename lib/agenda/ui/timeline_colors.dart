import 'package:flutter/material.dart';

import '../../schedule/building_palette.dart';
import '../deadline_source.dart';
import '../model.dart';
import '../physics_lab_deadlines.dart';

/// Source/type colors are specific to the timeline, not other agenda views.
({Color fill, Color text, Color accent}) agendaTimelineColors(
  BuildContext context,
  AgendaEntry entry,
  DateTime now,
) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final paletteName = switch (entry.kind) {
    AgendaKind.exam => '物理实验中心',
    AgendaKind.deadline => isPhysicsLabDeadline(entry)
        ? '综合教学楼A'
        : switch (entry.source) {
            DeadlineSource.lexue => '文博中心',
            DeadlineSource.eclass => '文化体育中心',
            null => null,
          },
    AgendaKind.event => null,
  };
  final palette = paletteName == null ? null : buildingPaletteNamed(paletteName);
  final finished = entry.isFinished(now);
  final alpha = entry.isDeadline && entry.done
      ? 0.35
      : finished
          ? 0.55
          : 1.0;
  if (palette != null) {
    final values = theme.brightness == Brightness.dark
        ? palette.dark
        : palette.light;
    return (
      fill: Color(values.fill).withValues(alpha: alpha),
      text: Color(values.text),
      accent: Color(values.accent),
    );
  }

  final overdue = entry.overdue(now);
  final fill = finished
      ? scheme.surfaceContainerHighest
      : overdue
          ? scheme.errorContainer
          : switch (entry.kind) {
              AgendaKind.event => scheme.primaryContainer,
              AgendaKind.exam => scheme.tertiaryContainer,
              AgendaKind.deadline => scheme.secondaryContainer,
            };
  final text = finished
      ? scheme.onSurfaceVariant
      : overdue
          ? scheme.onErrorContainer
          : switch (entry.kind) {
              AgendaKind.event => scheme.onPrimaryContainer,
              AgendaKind.exam => scheme.onTertiaryContainer,
              AgendaKind.deadline => scheme.onSecondaryContainer,
            };
  final accent = overdue
      ? scheme.error
      : switch (entry.kind) {
          AgendaKind.event => scheme.primary,
          AgendaKind.exam => scheme.tertiary,
          AgendaKind.deadline => scheme.secondary,
        };
  return (
    fill: fill.withValues(alpha: alpha),
    text: text,
    accent: accent,
  );
}
