import 'dart:convert';

import '../agenda/model.dart';
import '../schedule/model.dart';
import 'read_cache.dart';
import 'school_exams.dart';
import 'school_schedule.dart';
import 'school_session.dart';

class SchoolService {
  final _currentTerms = ReadCache<String, String>(
    maxAge: const Duration(hours: 1),
  );
  final _availableTerms = ReadCache<String, List<String>>(
    maxAge: const Duration(hours: 1),
  );

  Future<({SemesterSchedule schedule, List<String> terms})> synchronize(
    SchoolSession session, {
    required String account,
    String? term,
  }) async {
    await session.request(session.network.app, stopAtLogin: true);
    final selectedTerm = term ?? await _currentTerm(session, account);
    final terms = await _availableTerms.read(account, () async {
      final response = await session.json('modules/jshkcb/xnxqcx.do');
      return _rows(
        response,
        'xnxqcx',
      ).map((row) => row['DM'] as String).toList();
    });
    final calendar = await session.json(
      'wdkbByController/cxzkbrq.do',
      form: {
        'requestParamStr': jsonEncode({'XNXQDM': selectedTerm, 'ZC': '1'}),
      },
    );
    final monday = (calendar['data'] as List).cast<Map>().firstWhere(
      (row) => row['XQ'].toString() == '1',
    );
    final response = await session.json(
      'modules/xskcb/cxxszhxqkb.do',
      form: {'XNXQDM': selectedTerm},
    );
    return (
      schedule: parseSchoolSchedule(
        term: selectedTerm,
        termStartMonday: DateTime.parse(monday['RQ'] as String),
        rows: _rows(response, 'cxxszhxqkb'),
      ),
      terms: terms,
    );
  }

  Future<({String term, List<AgendaEntry> exams})> exams(
    SchoolSession session, {
    required String account,
    String? term,
  }) async {
    if (term == null) {
      await session.request(session.network.app, stopAtLogin: true);
      term = await _currentTerm(session, account);
    }
    return fetchSchoolExams(session, term: term);
  }

  Future<String> _currentTerm(SchoolSession session, String account) =>
      _currentTerms.read(account, () async {
        final response = await session.json('modules/jshkcb/dqxnxq.do');
        return _rows(response, 'dqxnxq').first['DM'] as String;
      });

  void clearCache() {
    _currentTerms.clear();
    _availableTerms.clear();
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> response, String key) =>
      ((response['datas'] as Map)[key]['rows'] as List)
          .cast<Map<String, dynamic>>();
}
