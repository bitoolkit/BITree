import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_controller.dart';
import 'agenda/controller.dart';
import 'academics/controller.dart';
import 'data/academic_store.dart';
import 'data/agenda_store.dart';
import 'data/schedule_store.dart';
import 'data/school_service.dart';
import 'data/school_storage.dart';
import 'diagnostics.dart';
import 'ui/app_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final diagnostics = AppDiagnostics.instance;
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    diagnostics.error(
      'Flutter',
      details.exception,
      details.stack ?? StackTrace.current,
    );
  };
  WidgetsBinding.instance.platformDispatcher.onError = (failure, stack) {
    diagnostics.report('未处理的异常', failure, stack);
    return true;
  };
  diagnostics.info('启动 BITree（${Platform.operatingSystem}）');

  final controller = AppController(
    store: ScheduleStore(),
    school: SchoolService(),
    schoolStorage: SchoolStorage(),
    preferences: SharedPreferencesAsync(),
    agenda: AgendaController(AgendaStore()),
    academics: AcademicController(AcademicStore()),
  );
  runApp(BitreeApp(controller: controller));
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.initialize());
}

class BitreeApp extends StatelessWidget {
  const BitreeApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final lightTheme = bitreeTheme(Brightness.light);
    final darkTheme = bitreeTheme(Brightness.dark);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => MaterialApp(
        title: 'BITree',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: controller.themeMode,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: AppScreen(controller: controller),
      ),
    );
  }
}
