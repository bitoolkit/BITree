import '../agenda/model.dart';
import 'session.dart';

Future<({String term, List<AgendaEntry> exams})> fetchSchoolExams(
  SchoolSession session, {
  required String term,
}) async {
  await session.request(session.network.examApp, stopAtLogin: true);
  final response = await session.json(
    'modules/ksap/cxxsksap.do',
    app: 'wdksapMobile',
    form: {'XNXQDM': term, '*order': '-KSRQ'},
  );
  final rows = (response['datas']['cxxsksap']['rows'] as List).cast<Map>();
  final exams = rows.map((row) {
    final date = DateTime.parse(row['KSRQ'] as String);
    final times = RegExp(r'(\d{2}):(\d{2})')
        .allMatches(row['KSSJMS'] as String)
        .toList();

    DateTime at(RegExpMatch time) => DateTime.utc(
      date.year,
      date.month,
      date.day,
      int.parse(time[1]!),
      int.parse(time[2]!),
    );

    final start = at(times[0]);
    final subject = row['KCM'] as String;
    return AgendaEntry(
      id: 'exam-$term-${row['KCH']}-$subject-${start.toIso8601String()}',
      title: subject,
      kind: AgendaKind.exam,
      startsAt: start,
      endsAt: at(times[1]),
      location: row['JASMC'] as String? ?? '',
      notes: [
        if (row['ZWH'] case final String seat when seat.isNotEmpty) '座位号：$seat',
        if (row['KSMC'] case final String mode when mode.isNotEmpty) mode,
        if (row['ZJJSXM'] case final String teacher when teacher.isNotEmpty)
          '教师：$teacher',
      ].join('\n'),
      term: term,
      local: false,
    );
  }).toList();
  return (term: term, exams: exams);
}
