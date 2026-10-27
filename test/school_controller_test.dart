import 'dart:async';

import 'package:bitree/core/async/cancelable_request.dart';
import 'package:bitree/school/controller.dart';
import 'package:bitree/school/service.dart';
import 'package:bitree/school/storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  test('Disposing a school session cancels pending reads without notifying a dead view', () async {
    final app = TestAppController();
    await app.initialize();
    final school = SchoolController(
      service: SchoolService(),
      storage: MemorySchoolStorage(),
      timetable: app.timetable,
      agenda: app.agenda,
      academics: app.academics,
    );
    final response = Completer<int>();
    final read = school.read(
      '查询',
      (_) => response.future,
      verify: (_) async => null,
    );
    school.dispose();
    response.complete(1);
    expect(await read, isNull);
  });

  test('Cancelling a school read releases busy state without publishing its result', () async {
    final app = TestAppController();
    await app.initialize();
    final response = Completer<int>();
    final cancellation = CancellationToken();
    final read = app.school.read(
      '查询',
      (_) => response.future,
      verify: (_) async => null,
      cancellation: cancellation,
    );
    expect(app.school.busy, isTrue);
    cancellation.cancel();
    response.complete(1);
    expect(await read, isNull);
    expect(app.school.busy, isFalse);
  });

  test('Sign out cancels the active read before removing credentials and academic state', () async {
    final storage = MemorySchoolStorage(
      credentials: const SchoolCredentials(
        username: 'student',
        password: 'test',
      ),
    );
    final app = TestAppController(schoolStorage: storage);
    await app.initialize();
    final response = Completer<int>();
    final read = app.school.read(
      '查询',
      (_) => response.future,
      verify: (_) async => null,
    );
    final signOut = app.school.signOut();
    response.complete(1);
    expect(await read, isNull);
    expect(await signOut, isTrue);
    expect(app.school.busy, isFalse);
    expect(app.school.accountStatus, AccountStatus.signedOut);
    expect(app.school.username, isNull);
    expect(await storage.readCredentials(), isNull);
    expect(app.academics.record.grades, isEmpty);
  });
}
