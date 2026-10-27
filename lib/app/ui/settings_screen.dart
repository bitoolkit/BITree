import 'package:flutter/material.dart';

import '../../agenda/deadline_clear_scope.dart';
import '../../agenda/ui/physics_lab_import.dart';
import '../../schedule/ui/week_range_dialog.dart';
import '../../school/ui/school_account.dart';
import '../../school/ui/school_screen.dart';
import '../../ui/app_menu_anchor.dart';
import '../../ui/app_menu_trigger.dart';
import '../../ui/app_notice.dart';
import '../../ui/app_page.dart';
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

  Future<void> _clearDeadlines(
    BuildContext context,
    DeadlineClearScope scope,
  ) async {
    final agenda = controller.agenda;
    if (!agenda.ready || agenda.busy) {
      showAppNotice(context, '日程尚未加载或正在保存，请稍后重试。');
      return;
    }
    final count = agenda.countDeadlines(scope);
    if (count == 0) {
      showAppNotice(context, '没有可清空的${scope.label}。');
      return;
    }
    final recovery = switch (scope) {
      DeadlineClearScope.local =>
        '乐学和新延河课堂来源的 DDL 将保留。大物实验 DDL 可根据课表手动重新生成，手动创建的 DDL 无法恢复。',
      DeadlineClearScope.lexue => '乐学 DDL 之后可从平台重新同步。其他来源的 DDL 将保留。',
      DeadlineClearScope.eclass => '新延河课堂 DDL 之后可从平台重新同步。其他来源的 DDL 将保留。',
      DeadlineClearScope.all =>
        '平台来源的 DDL 之后可重新同步；大物实验 DDL 可根据课表手动重新生成，手动创建的 DDL 无法恢复。',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('清空${scope.label}？'),
        scrollable: true,
        content: Text(
          '将永久清空 $count 条${scope.label}。\n'
          '${scope.description}\n\n'
          '范围包含所有学期、已完成及已删除的匹配 DDL，不影响考试等其他日程。'
          '清空后无法撤销，也无法从“已删除的 DDL”中恢复。\n\n'
          '$recovery',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('清空 $count 条 DDL'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;
    if (!agenda.ready || agenda.busy) {
      showAppNotice(context, '日程尚未加载或正在保存，请稍后重试。');
      return;
    }
    if (agenda.countDeadlines(scope) != count) {
      showAppNotice(context, '匹配的 DDL 数量已变化，请重新确认后清空。');
      return;
    }
    final cleared = await agenda.clearDeadlines(scope);
    if (!context.mounted || !cleared) return;
    showAppNotice(context, '已清空 $count 条${scope.label}。');
  }

  Future<void> _showAbout(BuildContext context) async {
    final version = await appVersion();
    final builtAt = appBuildTime?.toLocal();
    if (!context.mounted) return;

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
              Image.asset('assets/brand/bitree.png', width: 40, height: 40),
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
              DefaultTextStyle(
                style: theme.textTheme.bodySmall!,
                child: const Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [Text('Made by Ray'), Text('Unlicense')],
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
                Uri.https('github.com', '/so1ve/bitree'),
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
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      controller,
      controller.timetable,
      controller.school,
      controller.agenda,
    ]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final schedule = controller.timetable.schedule;
    final physicsEnabled =
        schedule != null &&
        controller.timetable.ready &&
        !controller.timetable.busy &&
        controller.agenda.ready &&
        !controller.agenda.busy;

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
              leading: const Icon(Icons.science_outlined),
              title: const Text('更新大物实验 DDL'),
              subtitle: Text(
                schedule == null
                    ? '请先选择或导入本地课表；离线生成，无需学校登录'
                    : '当前选中：${schedule.termLabel} · 全部周次\n离线生成，无需学校登录，仅手动更新',
              ),
              onTap: physicsEnabled
                  ? () => updatePhysicsLabDeadlines(context, controller)
                  : null,
            ),
            for (final scope in DeadlineClearScope.values)
              ListTile(
                contentPadding: tilePadding,
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: scheme.error,
                ),
                title: Text(
                  '清空${scope.label}',
                  style: TextStyle(color: scheme.error),
                ),
                subtitle: Text(
                  '${scope.description}\n'
                  '${controller.agenda.countDeadlines(scope)} 条（含已完成、已删除）',
                ),
                onTap:
                    !controller.agenda.ready ||
                        controller.agenda.busy ||
                        controller.agenda.countDeadlines(scope) == 0
                    ? null
                    : () => _clearDeadlines(context, scope),
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
