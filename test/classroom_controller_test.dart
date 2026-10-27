import 'dart:async';

import 'package:bitree/classrooms/controller.dart';
import 'package:bitree/classrooms/model.dart';
import 'package:bitree/classrooms/repository.dart';
import 'package:bitree/core/async/cancelable_request.dart';
import 'package:bitree/school/storage.dart';
import 'package:bitree/school/verification.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

const buildings = [
  SchoolBuilding(code: 'a', name: '文萃楼A', campusCode: 'lx'),
  SchoolBuilding(code: 'b', name: '文萃楼B', campusCode: 'lx'),
  SchoolBuilding(code: 'c', name: '综合教学楼', campusCode: 'lx'),
];

class _Repository extends ClassroomRepository {
  _Repository(super.school);
  final dates = <DateTime>[];
  Future<List<BuildingOccupancy>> Function(DateTime)? respond;

  @override
  Future<ClassroomDirectory?> directory({
    required VerifySchoolLogin verify,
    bool refresh = false,
    CancellationToken? cancellation,
  }) async => const ClassroomDirectory(
    campuses: [SchoolCampus(code: 'lx', name: '良乡校区')],
    buildings: buildings,
  );

  @override
  Future<List<BuildingOccupancy>?> occupancy({
    required List<SchoolBuilding> buildings,
    required DateTime date,
    required VerifySchoolLogin verify,
    bool refresh = false,
    CancellationToken? cancellation,
  }) async {
    dates.add(date);
    return respond == null
        ? [
            for (final building in buildings)
              BuildingOccupancy(
                building: building,
                rooms: const [
                  ClassroomOccupancy(name: '101', busySections: {1, 2}),
                ],
              ),
          ]
        : respond!(date);
  }
}

void main() {
  Future<(_Repository, ClassroomController)> create() async {
    final app = TestAppController(
      schoolStorage: MemorySchoolStorage(
        credentials: const SchoolCredentials(
          username: 'student',
          password: 'test',
        ),
      ),
    );
    await app.initialize();
    final repository = _Repository(app.school);
    addTearDown(repository.dispose);
    final query = ClassroomController(
      repository: repository,
      school: app.school,
      verify: (_) async => null,
      signIn: () async => fail('An authenticated query must not request login'),
      date: DateTime.utc(2026, 10, 27),
    );
    addTearDown(query.dispose);
    return (repository, query);
  }

  test('Building groups and period filters reuse loaded occupancy', () async {
    final (repository, query) = await create();
    await query.load();
    expect(query.campusCode, 'lx');
    expect(query.results, hasLength(3));
    query.selectBuilding(wenCuiBuildingFilter);
    expect(query.results.map((group) => group.building.code), ['a', 'b']);
    query.selectPeriod((start: 1, end: 3));
    expect(query.results, isEmpty);
    query.selectPeriod((start: 3, end: 4));
    expect(query.results, hasLength(2));
    expect(repository.dates, hasLength(1));
  });

  test(
    'Changing the date cancels old results and retains the newest query',
    () async {
      final (repository, query) = await create();
      final started = Completer<void>();
      final oldResponse = Completer<List<BuildingOccupancy>>();
      repository.respond = (_) {
        started.complete();
        return oldResponse.future;
      };
      final old = query.load();
      await started.future;
      final tomorrow = DateTime.utc(2026, 10, 28);
      final latest = query.selectDate(tomorrow);
      expect(query.date, tomorrow);
      expect(query.busy, isTrue);
      repository.respond = (_) async => [
        BuildingOccupancy(
          building: buildings[1],
          rooms: const [ClassroomOccupancy(name: '201', busySections: {})],
        ),
      ];
      oldResponse.complete([
        BuildingOccupancy(
          building: buildings[0],
          rooms: const [ClassroomOccupancy(name: 'old', busySections: {})],
        ),
      ]);
      await Future.wait([old, latest]);
      expect(query.busy, isFalse);
      expect(query.results.single.rooms.single.name, '201');
      expect(repository.dates, [DateTime.utc(2026, 10, 27), tomorrow]);
    },
  );
}
