import 'dart:convert';

import '../classrooms/model.dart';
import '../schedule/model.dart';
import 'school_session.dart';

Future<ClassroomDirectory> fetchClassroomDirectory(
  SchoolSession session,
) async {
  await _openClassroomApp(session, 'kxjasbyMobile');

  final campuses = _rows(
    await session.json(
      'modules/jxllb/ggzdpx.do?dicCode=48682&SFSY=1&order=%2BDM',
      app: 'kxjasbyMobile',
    ),
    'ggzdpx',
  );
  final buildings = _rows(
    await session.json('modules/jxllb/cxjxl.do', app: 'kxjasbyMobile'),
    'cxjxl',
  );

  return ClassroomDirectory(
    campuses: [
      for (final row in campuses)
        SchoolCampus(code: row['DM'] as String, name: row['MC'] as String),
    ],
    buildings: [
      for (final row in buildings)
        if ((row['JXLMC'] as String).trim() != '文萃楼')
          SchoolBuilding(
            code: row['JXLDM'] as String,
            name: row['JXLMC'] as String,
            campusCode: row['XXXQDM'] as String?,
          ),
    ],
  );
}

Future<List<BuildingOccupancy>> fetchClassroomOccupancy(
  SchoolSession session, {
  required List<SchoolBuilding> buildings,
  required DateTime date,
}) async {
  await _openClassroomApp(session, 'kxjas');

  // Use the school's calendar, independently of the user's local timetable.
  final current = await _query(session, 'dqxnxqcx');
  final term = (current['rows'] as List).first as Map<String, dynamic>;
  final day = await _query(session, 'rqzhzcjc', {
    'RQ': dateText(date),
    'XN': term['XNDM'].toString(),
    'XQ': term['XQDM'].toString(),
  });

  final form = {
    'XNXQDM': term['DM'] as String,
    'ZC': day['ZC'].toString(),
    'XQ': day['XQJ'].toString(),
    'RQ': dateText(date),
  };

  final result = <BuildingOccupancy>[];
  for (final building in buildings) {
    result.add(
      BuildingOccupancy(
        building: building,
        rooms: await _buildingOccupancy(session, building.code, form),
      ),
    );
  }
  return result;
}

Future<List<ClassroomOccupancy>> _buildingOccupancy(
  SchoolSession session,
  String buildingCode,
  Map<String, String> date,
) async {
  const pageSize = 50;
  final form = {
    ...date,
    'querySetting': jsonEncode([
      {
        'name': 'JXLDM',
        'caption': '教学楼代码',
        'builder': 'equal',
        'linkOpt': 'AND',
        'value': buildingCode,
      },
    ]),
    '*order': '+JASMC',
    'pageSize': '$pageSize',
  };
  final rooms = <ClassroomOccupancy>[];
  var page = 1;
  while (true) {
    final response = await _query(session, 'cxjsqk', {
      ...form,
      'pageNumber': '$page',
    });
    final rows = (response['rows'] as List).cast<Map<String, dynamic>>();
    for (final row in rows) {
      rooms.add(
        ClassroomOccupancy(
          name: row['JASMC'] as String,
          busySections: {
            for (var section = 1; section <= sectionTimes.length; section++)
              // Each entry describes a booking; 1_ marks an occupied section.
              if ((row['JC$section']?.toString() ?? '')
                  .split(',')
                  .any((booking) => booking.startsWith('1_')))
                section,
          },
        ),
      );
    }
    final total = int.parse(response['totalSize'].toString());
    if (page * pageSize >= total) return rooms;
    page++;
  }
}

Future<void> _openClassroomApp(SchoolSession session, String app) async {
  await session.request(session.network.app, stopAtLogin: true);
  await session.request(
    session.network.endpoint(
      'api/getAppConfig/wdkbby-5959167891382285.do',
      app: 'funauthapp',
    ),
    stopAtLogin: true,
  );
  await session.request(
    session.network.timetableTranslations,
    stopAtLogin: true,
  );
  await session.request(
    session.network.endpoint('*default/index.do', app: app),
    stopAtLogin: true,
  );
}

Future<Map<String, dynamic>> _query(
  SchoolSession session,
  String name, [
  Map<String, String> form = const {},
]) async {
  final response = await session.json(
    'modules/kxjas/$name.do',
    app: 'kxjas',
    form: form,
  );
  return response['datas'][name] as Map<String, dynamic>;
}

List<Map<String, dynamic>> _rows(Map<String, dynamic> response, String name) =>
    (response['datas'][name]['rows'] as List).cast<Map<String, dynamic>>();
