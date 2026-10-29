import 'dart:async';

import 'package:flutter/material.dart';

import '../../agenda/deadline_clear_scope.dart';
import '../../agenda/ui/clear_deadlines_dialog.dart';
import '../../schedule/ui/week_range_dialog.dart';
import '../../school/ui/school_account.dart';
import '../../school/ui/school_screen.dart';
import '../../ui/app_menu_anchor.dart';
import '../../ui/app_menu_trigger.dart';
import '../../ui/app_page.dart';
import '../../ui/course_palette.dart';
import '../../ui/external_link.dart';
import '../../updates/version.dart';
import '../controller.dart';
import 'logs_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.checkingForUpdates,
    required this.onCheckForUpdates,
  });

  final AppController controller;
  final bool checkingForUpdates;
  final VoidCallback onCheckForUpdates;

  Future<bool> _selectTerm(BuildContext context, String term) =>
      controller.timetable.selectTerm(
        term,
        importTerm: (term) async {
          if (!context.mounted) return false;
          return await openSchoolPage(
                context,
                controller,
                action: SchoolAction.importSchedule,
                term: term,
              ) ==
              true;
        },
      );

  Future<void> _clearSchedule(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除本地课表？'),
        content: const Text('将删除所有学期的课表，包括手动添加的课程。删除后无法恢复。'),
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
            child: const Text('删除课表'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.timetable.clear();
  }

  Future<void> _showAbout(BuildContext context) async {
    final version = await appVersion();
    final builtAt = appBuildTime?.toLocal();
    if (!context.mounted) return;

    var iconTaps = 0;
    Timer? resetTaps;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final localizations = MaterialLocalizations.of(dialogContext);
        var versionLabel = version;
        if (builtAt != null) {
          final date = localizations.formatCompactDate(builtAt);
          final time = localizations.formatTimeOfDay(
            TimeOfDay.fromDateTime(builtAt),
            alwaysUse24HourFormat: true,
          );
          versionLabel += '\n构建于 $date $time';
        }
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          scrollable: true,
          title: Row(
            children: [
              Semantics(
                button: true,
                label: 'BITree 图标',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (controller.developerMode) return;
                    resetTaps?.cancel();
                    resetTaps = Timer(const Duration(seconds: 2), () {
                      iconTaps = 0;
                    });
                    iconTaps++;
                    if (iconTaps < 5) return;
                    controller.unlockDeveloperMode();
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已开启开发者模式')),
                    );
                  },
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Image.asset(
                        'assets/brand/bitree.png',
                        width: 40,
                        height: 40,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'BITree',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text('理枝', style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      versionLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('面向北京理工大学的本地跨平台工具集。'),
              const SizedBox(height: 12),
              Semantics(
                link: true,
                child: InkWell(
                  onTap: () => openExternalLink(
                    dialogContext,
                    Uri.https('github.com', '/bitoolkit'),
                    failureTitle: '无法打开 BIToolkit',
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Unlicense. Made by '),
                          TextSpan(
                            text: 'BIToolkit',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                          const TextSpan(text: ' with ♥️'),
                        ],
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                showLicensePage(
                  context: context,
                  applicationName: 'BITree 理枝',
                  applicationVersion: version,
                  applicationIcon: Image.asset(
                    'assets/brand/bitree.png',
                    width: 40,
                    height: 40,
                  ),
                );
              },
              child: const Text('查看许可'),
            ),
            TextButton(
              onPressed: () => openExternalLink(
                dialogContext,
                Uri.https('github.com', '/bitoolkit/bitree'),
                failureTitle: '无法打开 GitHub',
              ),
              child: const Text('GitHub'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
    resetTaps?.cancel();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      controller,
      controller.timetable,
      controller.agenda,
    ]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final deadlineCount = controller.agenda.countDeadlinesIn(
      DeadlineClearScope.values,
    );

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(title),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );

    const tilePadding = EdgeInsets.symmetric(vertical: 2);

    return AppPage(
      title: const Text('设置'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SchoolAccount(controller: controller),
          section('外观', [
            SegmentedButton<ThemeMode>(
              expandedInsets: EdgeInsets.zero,
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('跟随系统', maxLines: 2, textAlign: TextAlign.center),
                ),
                ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
              ],
              selected: {controller.themeMode},
              onSelectionChanged: (selection) =>
                  controller.setTheme(selection.single),
            ),
          ]),
          if (controller.developerMode)
            section('更多设置', [
              LayoutBuilder(
                builder: (context, constraints) => AppMenuAnchor(
                  menuWidth: constraints.maxWidth,
                  menuChildren: [
                    for (final palette in DarkCoursePalette.values)
                      Semantics(
                        selected: controller.darkCoursePalette == palette,
                        child: AppMenuItemButton(
                          onPressed: () =>
                              controller.setDarkCoursePalette(palette),
                          trailingIcon:
                              controller.darkCoursePalette == palette
                              ? const Icon(Icons.check_rounded, size: 18)
                              : const SizedBox(width: 18),
                          child: Text(palette.label),
                        ),
                      ),
                  ],
                  builder: (context, menu, isOpen) => ListTile(
                    contentPadding: tilePadding,
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('深色模式调色板'),
                    subtitle: Text(
                      '${controller.darkCoursePalette.label} · 仅影响深色课程配色',
                    ),
                    trailing: AppMenuArrow(isOpen: isOpen),
                    onTap: () => isOpen ? menu.close() : menu.open(),
                  ),
                ),
              ),
            ]),
          if (controller.timetable.schedule != null)
            section('本地课表', [
              LayoutBuilder(
                builder: (context, constraints) => AppMenuAnchor(
                  menuWidth: constraints.maxWidth,
                  menuChildren: [
                    for (final term in controller.timetable.terms)
                      Semantics(
                        selected: controller.timetable.schedule!.term == term,
                        child: AppMenuItemButton(
                          onPressed: controller.timetable.busy
                              ? null
                              : () => _selectTerm(context, term),
                          trailingIcon:
                              controller.timetable.schedule!.term == term
                              ? const Icon(Icons.check_rounded, size: 18)
                              : const SizedBox(width: 18),
                          overflowAxis: Axis.vertical,
                          child: Text(term),
                        ),
                      ),
                  ],
                  builder: (context, menu, isOpen) => ListTile(
                    contentPadding: tilePadding,
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: const Text('学期'),
                    subtitle: Text(controller.timetable.schedule!.termLabel),
                    trailing: AppMenuArrow(isOpen: isOpen),
                    onTap: controller.timetable.busy
                        ? null
                        : () => isOpen ? menu.close() : menu.open(),
                  ),
                ),
              ),
              ListTile(
                contentPadding: tilePadding,
                leading: const Icon(Icons.date_range_outlined),
                title: const Text('周数管理'),
                subtitle: Text(
                  '${controller.timetable.schedule!.firstWeek} - ${controller.timetable.schedule!.lastWeek} 周',
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: controller.timetable.busy
                    ? null
                    : () => manageTermWeeks(context, controller),
              ),
              ListTile(
                contentPadding: tilePadding,
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: scheme.error,
                ),
                title: Text('删除本地课表', style: TextStyle(color: scheme.error)),
                onTap: controller.timetable.busy
                    ? null
                    : () => _clearSchedule(context),
              ),
            ]),
          section('本地日程', [
            ListTile(
              contentPadding: tilePadding,
              leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
              title: Text('删除 DDL', style: TextStyle(color: scheme.error)),
              subtitle: Text(
                '可勾选手动创建、大物实验、乐学和新延河课堂来源\n'
                '共 $deadlineCount 条（所有学期，含已完成、已删除）',
              ),
              onTap:
                  !controller.agenda.ready ||
                      controller.agenda.busy ||
                      deadlineCount == 0
                  ? null
                  : () => showClearDeadlines(context, controller.agenda),
            ),
          ]),
          section('应用', [
            ListTile(
              contentPadding: tilePadding,
              leading: const Icon(Icons.description_outlined),
              title: const Text('导出日志'),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const LogsScreen()),
              ),
            ),
            ListTile(
              contentPadding: tilePadding,
              leading: const Icon(Icons.system_update_outlined),
              title: Text(checkingForUpdates ? '正在检查更新…' : '检查更新'),
              trailing: checkingForUpdates
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: checkingForUpdates ? null : onCheckForUpdates,
            ),
            ListTile(
              contentPadding: tilePadding,
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('关于 BITree'),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => _showAbout(context),
            ),
          ]),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
