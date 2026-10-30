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

enum AppLanguage {
  system,
  chinese,
  english;

  Locale? get locale => switch (this) {
    AppLanguage.system => null,
    AppLanguage.chinese => const Locale('zh'),
    AppLanguage.english => const Locale('en'),
  };
}

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
  final _preferenceWrites = <String, Future<void>>{};
  bool _themeChosen = false;
  bool _agendaViewChosen = false;
  bool _ready = false;
  ThemeMode _themeMode = ThemeMode.system;
  AppLanguage _language = AppLanguage.system;

  bool get ready => _ready;
  ThemeMode get themeMode => _themeMode;
  AppLanguage get language => _language;

  Future<void> initialize() async {
    await timetable.load();
    try {
      final theme = await _preferences.getString('theme');
      if (!_themeChosen) {
        _themeMode =
            ThemeMode.values
                .where((value) => value.name == theme)
                .firstOrNull ??
            ThemeMode.system;
      }
    } on Exception catch (failure, stack) {
      AppDiagnostics.instance.error('读取外观设置', failure, stack);
    }
    try {
      final language = await _preferences.getString('language');
      _language =
          AppLanguage.values
              .where((value) => value.name == language)
              .firstOrNull ??
          AppLanguage.system;
    } catch (failure, stack) {
      AppDiagnostics.instance.report('读取语言设置', failure, stack);
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
    } on Exception catch (failure, stack) {
      AppDiagnostics.instance.error('读取日程视图设置', failure, stack);
    }
    await school.loadAccount();
    await agenda.load();
    await mooc.load();
    await academics.load(school.username);
    _ready = true;
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode value) {
    _themeChosen = true;
    _themeMode = value;
    notifyListeners();
    return _writePreference('theme', value.name, '保存外观设置');
  }

  Future<void> setLanguage(AppLanguage value) async {
    try {
      await _preferences.setString('language', value.name);
      _language = value;
      notifyListeners();
    } catch (failure, stack) {
      AppDiagnostics.instance.report('保存语言设置', failure, stack);
    }
  }

  /// Publish immediately and serialize writes so rapid toggles cannot save an
  /// older choice after a newer one.
  Future<void> setAgendaViewMode(AgendaViewMode value) {
    _agendaViewChosen = true;
    agendaViewMode.value = value;
    return _writePreference('agendaViewMode', value.name, '保存日程视图设置');
  }

  Future<void> _writePreference(String key, String value, String operation) {
    final previous = _preferenceWrites[key] ?? Future<void>.value();
    final write = previous.then((_) async {
      try {
        await _preferences.setString(key, value);
      } on Exception catch (failure, stack) {
        AppDiagnostics.instance.error(operation, failure, stack);
      }
    });
    _preferenceWrites[key] = write;
    return write;
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
