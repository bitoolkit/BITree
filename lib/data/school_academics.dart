import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../academics/model.dart';
import 'school_network.dart';
import 'school_session.dart';

Future<List<CourseGrade>> fetchSchoolGrades(SchoolSession session) async {
  final url = session.network.route(
    SchoolNetwork.recordsService.resolve('jsxsd/kscj/cjcx_list'),
  );
  final response = await session.request(
    url,
    form: {'kksj': '', 'kcxz': '', 'kcmc': '', 'xsfs': 'all'},
    headers: {'Origin': url.origin},
    stopAtLogin: true,
  );
  final table = html.parse(response.text).querySelector('#dataList');
  if (table == null) throw const FormatException('成绩页面中没有成绩列表');

  return [
    for (final row in table.querySelectorAll('tr').skip(1))
      if (row.querySelectorAll('td') case final cells when cells.length > 1)
        CourseGrade(
          id: jsonEncode([
            cells[1].text.trim(),
            cells[2].text.trim(),
            cells[3].text.trim(),
            cells[8].text.trim(),
            cells[4].text.trim(),
          ]),
          number: cells[2].text.trim(),
          name: cells[3].text.trim(),
          term: cells[1].text.trim(),
          result: cells[4].text.trim(),
          credits: double.parse(cells[6].text.trim()),
          attribute: cells[10].text.trim(),
          category: cells[11].text.trim(),
          examType: cells[8].text.trim(),
        ),
  ];
}

Future<StudyPlan> fetchStudyPlan(SchoolSession session) async {
  await session.request(session.network.accountPage, stopAtLogin: true);
  await session.request(session.network.accountConfig, stopAtLogin: true);
  final response = await session.json(
    'modules/pyfacxepg/grpyfacx.do',
    app: 'xsfacx',
  );
  final row = (response['datas']['grpyfacx']['rows'] as List).first as Map;
  double? credits(Object? value) => value == null || value.toString().isEmpty
      ? null
      : double.parse(value.toString());

  return StudyPlan(
    major: row['ZYDM_DISPLAY'] as String? ?? '',
    year: row['XZNJ_DISPLAY'] as String? ?? '',
    requiredCredits: credits(row['ZSYQXF']),
    completedCredits: credits(row['YWCXF']),
  );
}
