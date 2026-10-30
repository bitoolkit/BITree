import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../academics/controller.dart';
import '../agenda/controller.dart';
import '../agenda/view_mode.dart';
import '../classrooms/repository.dart';
import '../core/diagnostics.dart';
import '../mooc/controller.dart';
import '../mooc/storage.dart';
import '../schedule/controller.dart';
import '../schedule/store.dart';
import '../school/controller.dart';
import '../school/service.dart';
import '../school/storage.dart';
import '../sync/controller.dart';

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
    MoocStorage? moocStorage,
  }) : timetable = TimetableController(store) {
    this.school = SchoolController(
      service: school,
      storage: schoolStorage,
      timetable: timetable,
      agenda: agenda,
      academics: academics,
    );
    classrooms = ClassroomRepository(this.school);
    mooc = MoocController(
      storage: moocStorage ?? MoocStorage(),
      agenda: agenda,
    );
    sync = SyncController(
      school: this.school,
      mooc: mooc,
      timetable: timetable,
      agenda: agenda,
    );
  }

  final TimetableController timetable;
  late final SchoolController school;
  late final ClassroomRepository classrooms;
  final AgendaController agenda;
  final AcademicController academics;
  late final MoocController mooc;
  late final SyncController sync;
  final SharedPreferencesAsync _preferences;
  final agendaViewMode = ValueNotifier(AgendaViewMode.timeline);
  Future<void> _agendaViewWrite = Future<void>.value();
  bool _agendaViewChosen = false;
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
    try {
      final savedView = await _preferences.getString('agendaViewMode');
      if (!_agendaViewChosen) {
        agendaViewMode.value =
            AgendaViewMode.values
                .where((mode) => mode.name == savedView)
                .firstOrNull ??
            AgendaViewMode.timeline;
      }
    } catch (failure, stack) {
      AppDiagnostics.instance.report('读取日程视图设置', failure, stack);
    }
    await school.loadAccount();
    await agenda.load();
    await mooc.load();
    await academics.load(school.username);
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

  /// Publish immediately and serialize writes so rapid toggles cannot save an
  /// older choice after a newer one. Preference failures do not alter entries.
  Future<void> setAgendaViewMode(AgendaViewMode value) {
    _agendaViewChosen = true;
    agendaViewMode.value = value;
    _agendaViewWrite = _agendaViewWrite.then((_) async {
      try {
        await _preferences.setString('agendaViewMode', value.name);
      } catch (failure, stack) {
        AppDiagnostics.instance.report('保存日程视图设置', failure, stack);
      }
    });
    return _agendaViewWrite;
  }

  @override
  void dispose() {
    agendaViewMode.dispose();
    sync.dispose();
    classrooms.dispose();
    school.dispose();
    mooc.dispose();
    timetable.dispose();
    agenda.dispose();
    academics.dispose();
    super.dispose();
  }
}
