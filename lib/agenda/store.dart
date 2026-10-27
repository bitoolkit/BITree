import '../core/platform/desktop_widget.dart';
import '../core/storage/json_file.dart';
import 'model.dart';

class AgendaStore {
  final _file = const JsonFile('agenda.json');

  Future<List<AgendaEntry>> read() async {
    return await _file.read(
          (json) => (json as List)
              .map((row) => AgendaEntry.fromJson(row as Map<String, dynamic>))
              .toList(),
        ) ??
        [];
  }

  Future<void> write(List<AgendaEntry> entries) async {
    await _file.write(entries.map((entry) => entry.toJson()).toList());
    await updateDesktopWidget();
  }
}
