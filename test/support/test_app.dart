import 'package:bitree/academics/controller.dart';
import 'package:bitree/academics/model.dart';
import 'package:bitree/academics/store.dart';
import 'package:bitree/agenda/controller.dart';
import 'package:bitree/agenda/model.dart';
import 'package:bitree/agenda/store.dart';
import 'package:bitree/app/controller.dart';
import 'package:bitree/schedule/model.dart';
import 'package:bitree/schedule/store.dart';
import 'package:bitree/school/service.dart';
import 'package:bitree/school/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryScheduleStore extends ScheduleStore {
  MemoryScheduleStore({
    List<SemesterSchedule> schedules = const [],
    SemesterSchedule? selected,
  }) : schedules = {for (final schedule in schedules) schedule.term: schedule},
       selectedTerm = selected?.term ?? schedules.firstOrNull?.term {
    if (selected != null) this.schedules[selected.term] = selected;
  }

  final Map<String, SemesterSchedule> schedules;
  String? selectedTerm;

  @override
  Future<({String? selectedTerm, Map<String, SemesterSchedule> schedules})>
  read() async => (selectedTerm: selectedTerm, schedules: Map.of(schedules));

  @override
  Future<void> write(SemesterSchedule schedule) async {
    schedules[schedule.term] = schedule;
    selectedTerm = schedule.term;
  }

  @override
  Future<void> clear() async {
    schedules.clear();
    selectedTerm = null;
  }
}

class MemoryAgendaStore extends AgendaStore {
  MemoryAgendaStore([this.entries = const []]);
  List<AgendaEntry> entries;
  @override
  Future<List<AgendaEntry>> read() async => entries;
  @override
  Future<void> write(List<AgendaEntry> entries) async =>
      this.entries = List.of(entries);
}

class MemoryAcademicStore extends AcademicStore {
  final accounts = <String, AcademicRecord>{};
  @override
  Future<AcademicRecord> read(String account) async =>
      accounts[account] ?? const AcademicRecord();
  @override
  Future<void> write(String account, AcademicRecord record) async =>
      accounts[account] = record;
}

class _Preferences extends Fake implements SharedPreferencesAsync {
  final _values = <String, String>{};
  @override
  Future<String?> getString(String key) async => _values[key];
  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;
}

class MemorySchoolStorage extends SchoolStorage {
  MemorySchoolStorage({this.credentials});
  SchoolCredentials? credentials;
  @override
  Future<SchoolCredentials?> readCredentials() async => credentials;
  @override
  Future<void> saveCredentials(SchoolCredentials credentials) async =>
      this.credentials = credentials;
  @override
  Future<void> clear() async => credentials = null;
}

/// Uses production controllers; only persistence and platform boundaries are in memory.
class TestAppController extends AppController {
  TestAppController({
    SemesterSchedule? schedule,
    List<SemesterSchedule> schedules = const [],
    this.initialWeek,
    AgendaController? agenda,
    List<AgendaEntry> entries = const [],
    MemorySchoolStorage? schoolStorage,
  }) : super(
         store: MemoryScheduleStore(schedules: schedules, selected: schedule),
         school: SchoolService(),
         schoolStorage: schoolStorage ?? MemorySchoolStorage(),
         preferences: _Preferences(),
         agenda: agenda ?? AgendaController(MemoryAgendaStore(entries)),
         academics: AcademicController(MemoryAcademicStore()),
       ) {
    addTearDown(dispose);
  }

  final int? initialWeek;
  @override
  Future<void> initialize() async {
    await super.initialize();
    if (initialWeek case final week?) timetable.selectWeek(week);
  }
}
