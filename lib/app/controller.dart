import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../academics/controller.dart';
import '../agenda/controller.dart';
import '../agenda/view_mode.dart';
import '../classrooms/repository.dart';
import '../core/diagnostics.dart';
import '../core/platform/desktop_widget.dart';
import '../schedule/controller.dart';
import '../schedule/store.dart';
import '../school/controller.dart';
import '../school/service.dart';
import '../school/storage.dart';
import '../ui/course_palette.dart';

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
  final SharedPreferencesAsync _preferences;
  final agendaViewMode = ValueNotifier(AgendaViewMode.timeline);
  Future<void> _agendaViewWrite = Future<void>.value();
  bool _agendaViewChosen = false;
  bool _ready = false;
  ThemeMode _themeMode = ThemeMode.system;
  bool _developerMode = false;
  bool _widgetUseSystemPalette = false;
  DarkCoursePalette _darkCoursePalette = DarkCoursePalette.standard;
  Future<void> _coursePaletteWrite = Future<void>.value();

  bool get ready => _ready;
  ThemeMode get themeMode => _themeMode;
  bool get developerMode => _developerMode;
  bool get widgetUseSystemPalette => _widgetUseSystemPalette;
  DarkCoursePalette get darkCoursePalette => _darkCoursePalette;

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
      final savedPalette = await _preferences.getString('darkCoursePalette');
      _darkCoursePalette =
          DarkCoursePalette.values
              .where((palette) => palette.name == savedPalette)
              .firstOrNull ??
          DarkCoursePalette.standard;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('读取深色课程配色', failure, stack);
    }
    try {
      _widgetUseSystemPalette =
          await _preferences.getBool('widgetUseSystemPalette') ?? false;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('读取小组件调色板设置', failure, stack);
    }
    await updateDesktopWidget(
      darkCourseColors: _darkCoursePalette.widgetColors,
      useSystemPalette: _widgetUseSystemPalette,
    );
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

  void unlockDeveloperMode() {
    if (_developerMode) return;
    _developerMode = true;
    notifyListeners();
  }

  Future<void> setDarkCoursePalette(DarkCoursePalette value) {
    _darkCoursePalette = value;
    final useSystemPalette = _widgetUseSystemPalette;
    notifyListeners();
    _coursePaletteWrite = _coursePaletteWrite.then((_) async {
      try {
        await _preferences.setString('darkCoursePalette', value.name);
        await updateDesktopWidget(
          darkCourseColors: value.widgetColors,
          useSystemPalette: useSystemPalette,
        );
      } catch (failure, stack) {
        AppDiagnostics.instance.report('保存深色课程配色', failure, stack);
      }
    });
    return _coursePaletteWrite;
  }

  Future<void> setWidgetUseSystemPalette(bool value) {
    _widgetUseSystemPalette = value;
    final palette = _darkCoursePalette;
    notifyListeners();
    // Share the palette write queue so rapid changes reach native code in order.
    _coursePaletteWrite = _coursePaletteWrite.then((_) async {
      try {
        await _preferences.setBool('widgetUseSystemPalette', value);
        await updateDesktopWidget(
          darkCourseColors: palette.widgetColors,
          useSystemPalette: value,
        );
      } catch (failure, stack) {
        AppDiagnostics.instance.report('保存小组件调色板设置', failure, stack);
      }
    });
    return _coursePaletteWrite;
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
    classrooms.dispose();
    school.dispose();
    timetable.dispose();
    agenda.dispose();
    academics.dispose();
    super.dispose();
  }
}
