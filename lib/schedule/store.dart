import '../core/platform/desktop_widget.dart';
import '../core/storage/json_file.dart';
import 'model.dart';

class ScheduleStore {
  final _file = const JsonFile('schedule.json');

  Future<({String? selectedTerm, Map<String, SemesterSchedule> schedules})>
  read() async {
    final library = await _readLibrary();
    final semesters = library['semesters'] as Map<String, dynamic>;
    return (
      selectedTerm: library['selectedTerm'] as String?,
      schedules: semesters.map(
        (term, value) => MapEntry(
          term,
          SemesterSchedule.fromJson(value as Map<String, dynamic>),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _readLibrary() async {
    return await _file.read((json) => json as Map<String, dynamic>) ??
        {'selectedTerm': null, 'semesters': <String, dynamic>{}};
  }

  Future<void> write(SemesterSchedule schedule) async {
    final library = await _readLibrary();
    final semesters = library['semesters'] as Map<String, dynamic>;
    semesters[schedule.term] = schedule.toJson();
    library['selectedTerm'] = schedule.term;

    await _file.write(library);
    await updateDesktopWidget();
  }

  Future<void> clear() async {
    await _file.delete();
    await updateDesktopWidget();
  }
}
