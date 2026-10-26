import 'dart:async';

import 'package:flutter/material.dart';

import '../agenda/model.dart';
import '../app_controller.dart';
import '../schedule/model.dart';
import 'agenda_list_tile.dart';
import 'agenda_time.dart';
import 'campus_time_builder.dart';
import 'sheet_layout.dart';

class AgendaReminder extends StatefulWidget {
  const AgendaReminder({
    super.key,
    required this.controller,
    required this.entries,
    required this.now,
    required this.active,
  });

  final AppController controller;
  final List<AgendaEntry> entries;
  final DateTime now;
  final bool active;

  @override
  State<AgendaReminder> createState() => _AgendaReminderState();
}

class _AgendaReminderState extends State<AgendaReminder>
    with WidgetsBindingObserver {
  Timer? _timer;
  late bool _visible;
  bool _hovered = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _visible = widget.entries.isNotEmpty;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleDismiss();
  }

  @override
  void didUpdateWidget(covariant AgendaReminder oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousIds = oldWidget.entries.map((entry) => entry.id).toSet();
    final newEntries = widget.entries.any(
      (entry) => !previousIds.contains(entry.id),
    );
    final newDay = calendarDate(widget.now) != calendarDate(oldWidget.now);
    final activityChanged = widget.active != oldWidget.active;

    if (activityChanged && !widget.active) _visible = false;
    if (newEntries || newDay) _visible = widget.entries.isNotEmpty;
    if (widget.entries.isEmpty) _visible = false;
    if (newEntries || newDay || activityChanged || widget.entries.isEmpty) {
      _scheduleDismiss();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleDismiss();
    } else {
      _timer?.cancel();
    }
  }

  void _scheduleDismiss() {
    _timer?.cancel();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!_visible ||
        !widget.active ||
        _hovered ||
        _focused ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
        ModalRoute.of(context)?.isCurrent == false ||
        MediaQuery.accessibleNavigationOf(context)) {
      return;
    }
    _timer = Timer(const Duration(seconds: 6), _dismiss);
  }

  void _dismiss() {
    _timer?.cancel();
    if (_visible) setState(() => _visible = false);
  }

  Future<void> _open() async {
    _dismiss();
    await _showTodayAgenda(context, widget.controller);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visible && widget.active && widget.entries.isNotEmpty;
    final entry = widget.entries.firstOrNull;
    final caption = entry == null
        ? ''
        : entry.overdue(widget.now)
        ? '${agendaClockLabel(entry)} 已逾期'
        : entry.isDeadline || entry.allDay
        ? entry.timeLabel
        : entry.startsAt.isAfter(widget.now)
        ? '${agendaClockLabel(entry)} 开始'
        : '进行中';

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.12),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: !visible
            ? const SizedBox.shrink()
            : Focus(
                key: const ValueKey('agenda-reminder'),
                canRequestFocus: false,
                onFocusChange: (focused) {
                  _focused = focused;
                  _scheduleDismiss();
                },
                child: MouseRegion(
                  onEnter: (_) {
                    _hovered = true;
                    _scheduleDismiss();
                  },
                  onExit: (_) {
                    _hovered = false;
                    _scheduleDismiss();
                  },
                  child: Semantics(
                    liveRegion: true,
                    child: Material(
                      color: scheme.surfaceContainerLow,
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _open,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 2,
                                      children: [
                                        Text(
                                          '${widget.entries.length}项待办',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          caption,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: entry!.overdue(widget.now)
                                                ? scheme.error
                                                : scheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      entry.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '收起待办提醒',
                            onPressed: _dismiss,
                            icon: const Icon(Icons.close_rounded, size: 20),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

Future<void> _showTodayAgenda(BuildContext context, AppController controller) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => ListenableBuilder(
        listenable: controller.agenda,
        builder: (context, _) => CampusTimeBuilder(
          active: true,
          builder: (context, now) {
            final entries = controller.agenda.pendingOn(now);
            return SafeArea(
              top: false,
              child: SheetLayout(
                header: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${now.month}月${now.day}日待办',
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
                          child: Center(child: Text('暂无待办')),
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
