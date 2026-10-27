import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../academics/controller.dart';
import '../agenda/controller.dart';
import '../classrooms/repository.dart';
import '../core/diagnostics.dart';
import '../schedule/controller.dart';
import '../schedule/store.dart';
import '../school/controller.dart';
import '../school/service.dart';
import '../school/storage.dart';
import '../study/controller.dart';

/// Composes feature state and owns application startup and appearance.
/// Feature changes are observed by their views, not relayed through this object.
class AppController extends ChangeNotifier {
  AppController({
    required ScheduleStore store,
    required SchoolService school,
    required SchoolStorage schoolStorage,
    required this._preferences,
    required this.agenda,
    required this.academics,
    required this.study,
  }) : timetable = TimetableController(store) {
    this.school = SchoolController(
      service: school,
      storage: schoolStorage,
      timetable: timetable,
      agenda: agenda,
      academics: academics,
    );
    classrooms = ClassroomRepository(this.school);
  }

  final TimetableController timetable;
  late final SchoolController school;
  late final ClassroomRepository classrooms;
  final AgendaController agenda;
  final AcademicController academics;
  final StudyController study;
  final SharedPreferencesAsync _preferences;
  bool _ready = false;
  ThemeMode _themeMode = ThemeMode.system;

  bool get ready => _ready;
  ThemeMode get themeMode => _themeMode;

  Future<void> initialize() async {
    await timetable.load();
    try {
      final theme = await _preferences.getString('theme');
      _themeMode =
          ThemeMode.values.where((value) => value.name == theme).firstOrNull ??
          ThemeMode.system;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('读取外观设置', failure, stack);
    }
    await school.loadAccount();
    await agenda.load();
    await academics.load(school.username);
    await study.load();
    _ready = true;
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode value) async {
    try {
      await _preferences.setString('theme', value.name);
      _themeMode = value;
      notifyListeners();
    } catch (failure, stack) {
      AppDiagnostics.instance.report('保存外观设置', failure, stack);
    }
  }

  @override
  void dispose() {
    classrooms.dispose();
    school.dispose();
    timetable.dispose();
    agenda.dispose();
    academics.dispose();
    study.dispose();
    super.dispose();
  }
}
