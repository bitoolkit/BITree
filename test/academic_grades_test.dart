import 'dart:convert';

import 'package:bitree/academics/model.dart';
import 'package:flutter_test/flutter_test.dart';

CourseGrade grade(String id, String result, {double credits = 3}) =>
    CourseGrade(
      id: id,
      number: id,
      name: id,
      term: '2026-2027-1',
      credits: credits,
      result: result,
      attribute: '必修',
      category: '专业课',
    );

void main() {
  test('Non-percentage results survive import and persistence unchanged', () {
    const results = ['425', '100.5', '-1', '缓考', 'NaN', 'Infinity'];
    final record = AcademicRecord(
      grades: [
        grade('percent', '85'),
        for (final result in results) grade(result, result),
      ],
    );
    final restored = AcademicRecord.fromJson(
      jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>,
    );

    expect(restored.grades.map((course) => course.result), ['85', ...results]);
    for (final course in restored.grades.skip(1)) {
      expect(course.score, isNull, reason: course.result);
      expect(course.points, isNull, reason: course.result);
      expect(course.passed, isFalse, reason: course.result);
      expect(course.failed, isFalse, reason: course.result);
    }
    expect(restored.stats.gpa, 3.6);
    expect(restored.stats.averageScore, 85);
    expect(restored.stats.gpaCredits, 3);
    expect(restored.stats.earnedCredits, 3);
  });

  test('Only percentage scores and graded results contribute to GPA', () {
    final stats = AcademicStats([
      grade('zero', '0', credits: 1),
      grade('full', '100', credits: 1),
      grade('graded', '良好', credits: 1),
      grade('pass-fail', '合格', credits: 1),
      grade('other', '600', credits: 1),
    ]);

    expect(stats.gpa, closeTo(7.6 / 3, 1e-9));
    expect(stats.averageScore, 50);
    expect(stats.earnedCredits, 3);
    expect(stats.failed.map((course) => course.id), ['zero']);
  });
}
