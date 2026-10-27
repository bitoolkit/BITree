import '../core/storage/json_file.dart';
import 'model.dart';

class AcademicStore {
  final _file = const JsonFile('academics.json');

  Future<Map<String, dynamic>> _accounts() async =>
      await _file.read((value) => value as Map<String, dynamic>) ?? {};

  Future<AcademicRecord> read(String account) async {
    final saved = (await _accounts())[account];
    return saved == null
        ? const AcademicRecord()
        : AcademicRecord.fromJson(saved as Map<String, dynamic>);
  }

  Future<void> write(String account, AcademicRecord record) async {
    final accounts = await _accounts();
    accounts[account] = record.toJson();
    await _file.write(accounts);
  }
}
