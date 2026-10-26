import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../diagnostics.dart';
import 'app_notice.dart';
import 'app_page.dart';
import 'calendar_screen.dart';
import 'campus_time_builder.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'school_verification_dialog.dart';
import 'tools_screen.dart';
import 'update_check.dart';

class AppScreen extends StatefulWidget {
  const AppScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppScreen> createState() => _AppScreenState();
}

class _AppScreenState extends State<AppScreen> {
  int _tab = 0;
  bool _checkingUpdates = false;
  bool _started = false;
  late final StreamSubscription<String> _errors;

  @override
  void initState() {
    super.initState();
    _errors = AppDiagnostics.instance.messages.listen((message) {
      if (mounted) showAppNotice(context, message);
    });
    widget.controller.addListener(_onReady);
    _onReady();
  }

  void _onReady() {
    if (_started || !widget.controller.ready) return;
    _started = true;
    widget.controller.removeListener(_onReady);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_restoreAccount());
    });
  }

  Future<void> _restoreAccount() async {
    await widget.controller.restoreAccount(
      (request) => verifySchoolLogin(context, request),
    );
    if (mounted) await _checkUpdates(silent: true);
  }

  @override
  void dispose() {
    _errors.cancel();
    widget.controller.removeListener(_onReady);
    super.dispose();
  }

  Future<void> _checkUpdates({bool silent = false}) async {
    if (_checkingUpdates) return;
    setState(() => _checkingUpdates = true);

    try {
      await checkForUpdates(context, silent: silent);
    } finally {
      if (mounted) setState(() => _checkingUpdates = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      CampusTimeBuilder(active: true, builder: _build);

  Widget _build(BuildContext context, DateTime now) {
    final count = widget.controller.agenda.ready
        ? widget.controller.agenda.pendingOn(now, now: now).length
        : 0;
    final scheme = Theme.of(context).colorScheme;

    Widget agendaIcon(IconData icon) => Semantics(
      label: count > 0 ? '今天$count项待办' : null,
      excludeSemantics: true,
      child: Badge.count(
        count: count,
        isLabelVisible: count > 0,
        backgroundColor: scheme.primary,
        textColor: scheme.onPrimary,
        child: Icon(icon),
      ),
    );

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          IndexedStack(
            index: _tab,
            children: [
              HomeScreen(
                controller: widget.controller,
                now: now,
                active: _tab == 0,
              ),
              CalendarScreen(controller: widget.controller, now: now),
              ToolsScreen(controller: widget.controller),
              SettingsScreen(
                controller: widget.controller,
                checkingForUpdates: _checkingUpdates,
                onCheckForUpdates: () => _checkUpdates(),
              ),
            ],
          ),
          if (widget.controller.schoolBusy)
            Positioned(
              top: MediaQuery.paddingOf(context).top,
              left: 0,
              right: 0,
              child: const LinearProgressIndicator(minHeight: 3),
            ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: NavigationBar(
                height: appNavigationBarHeight(context),
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                selectedIndex: _tab,
                onDestinationSelected: (value) => setState(() => _tab = value),
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: '首页',
                  ),
                  NavigationDestination(
                    icon: agendaIcon(Icons.calendar_month_outlined),
                    selectedIcon: agendaIcon(Icons.calendar_month_rounded),
                    label: '日程',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view_rounded),
                    label: '工具',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings_rounded),
                    label: '设置',
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
