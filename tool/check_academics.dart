import 'dart:convert';
import 'dart:io';

import 'package:bitree/academics/exam_conflicts.dart';
import 'package:bitree/academics/model.dart';
import 'package:bitree/agenda/model.dart';
import 'package:bitree/data/school_network.dart';
import 'package:bitree/schedule/model.dart';

void expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

bool near(double? actual, double expected) =>
    actual != null && (actual - expected).abs() < 1e-9;

CourseGrade grade(
  String number,
  String result, {
  double credits = 3,
  String attribute = '必修',
}) => CourseGrade(
  id: '$number-$result',
  number: number,
  name: number,
  term: '2026-2027-1',
  credits: credits,
  result: result,
  attribute: attribute,
  category: '专业课',
);

AgendaEntry exam(
  String id,
  int hour,
  int minute,
  int endHour,
  int endMinute, {
  String term = '2026-2027-1',
}) => AgendaEntry(
  id: id,
  title: id,
  kind: AgendaKind.exam,
  startsAt: DateTime.utc(2026, 10, 27, hour, minute),
  endsAt: DateTime.utc(2026, 10, 27, endHour, endMinute),
  term: term,
);

void main() {
  expect(gradePoints(59) == 0 && gradePoints(60) == 1, '及格边界');
  expect(creditText(0.1 + 0.2) == '0.3', '学分显示不暴露浮点误差');
  expect(gradePoints(85) == 3.6 && gradePoints(100) == 4, '学校公式和一位小数舍入');
  expect(grade('A', '良好').points == 3.6, '五级制绩点');
  final passFail = AcademicStats([grade('PE', '合格', credits: 1)]);
  expect(passFail.gpa == null && passFail.earnedCredits == 1, '合格制只统计学分');
  final elective = AcademicStats([grade('E', '50', attribute: '校公选课')]);
  expect(elective.gpa == null && elective.earnedCredits == 0, '公选课不及格不计绩点');
  final retakes = AcademicStats([
    grade('A', '50'),
    grade('A', '85'),
    grade('A', '70'),
  ]);
  expect(
    near(retakes.gpa, 3.6) && retakes.earnedCredits == 3,
    '重修只取最高成绩且只获得一次学分',
  );
  final base = [grade('A', '60'), grade('B', '100', credits: 1)];
  expect(near(AcademicStats(base).gpa, 1.75), '按学分加权');
  final projected = [
    const ProjectedCourse(
      id: 'simulation-A',
      name: 'A',
      credits: 3,
      score: 80,
      replaces: 'A',
    ),
  ];
  expect(
    near(projectGrades(base, projected, replaceRetakes: true).gpa, 3.475),
    '重修试算替换低分',
  );
  expect(
    near(projectGrades(base, projected, replaceRetakes: false).gpa, 16.9 / 7),
    '试算可同时计入两次成绩',
  );
  expect(base.first.result == '60', '试算不改原成绩');
  expect(
    projectGrades(
          [grade('E', '50', attribute: '校公选课')],
          [
            const ProjectedCourse(
              id: 'simulation-E',
              name: 'E',
              credits: 3,
              score: 55,
              replaces: 'E',
            ),
          ],
          replaceRetakes: true,
        ).gpa ==
        null,
    '试算保留重修课程属性，公选课未通过仍不计绩点',
  );
  final needed = scoreForTarget(
    base,
    projected,
    target: 3.6,
    replaceRetakes: true,
  )!;
  expect(
    projectGrades(
          base,
          projected,
          replaceRetakes: true,
          uniformScore: needed.toDouble(),
        ).gpa! >=
        3.6,
    '目标倒推能达到目标',
  );
  expect(
    projectGrades(
          base,
          projected,
          replaceRetakes: true,
          uniformScore: (needed - 1).toDouble(),
        ).gpa! <
        3.6,
    '目标倒推返回最低整数成绩',
  );
  expect(
    scoreForTarget(
          [grade('A', '0', credits: 20)],
          [const ProjectedCourse(id: 'X', name: 'X', credits: 1, score: 80)],
          target: 4,
          replaceRetakes: true,
        ) ==
        null,
    '不可达目标',
  );
  expect(
    scoreForTarget(base, [], target: 3, replaceRetakes: true) == null,
    '没有试算课程',
  );
  final record = AcademicRecord(
    grades: base,
    targetCredits: 150,
    categoryTargets: const {'专业课': 80},
    categoryOverrides: const {'A': '专业必修'},
    gradesUpdatedAt: DateTime.utc(2026, 10, 27),
  );
  final restored = AcademicRecord.fromJson(
    jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>,
  );
  expect(
    restored.grades.length == 2 &&
        restored.targetCredits == 150 &&
        restored.categoryTargets['专业课'] == 80 &&
        restored.categoryOf(base.first) == '专业必修',
    '学业数据本地保存格式',
  );
  expect(
    restored.copyWith(grades: []).categoryTargets['专业课'] == 80 &&
        restored.copyWith(grades: []).categoryOverrides['A'] == '专业必修',
    '更新成绩保留个人学分目标',
  );

  final schedule = SemesterSchedule(
    term: '2026-2027-1',
    firstMonday: DateTime.utc(2026, 10, 26),
    courses: [
      Course(
        id: 'C',
        name: '课程',
        weekday: DateTime.tuesday,
        startSection: 3,
        endSection: 3,
        weeks: [1],
      ),
    ],
  );
  final a = exam('A', 9, 30, 10, 0);
  final b = exam('B', 10, 0, 11, 0);
  expect(
    findExamConflicts([a, b], [schedule], includeClasses: false).isEmpty,
    '考试首尾相接不算冲突',
  );
  final classConflicts = findExamConflicts(
    [a, b],
    [schedule],
    includeClasses: true,
  );
  expect(
    classConflicts.length == 2 &&
        classConflicts.first.minutes == 5 &&
        classConflicts.last.minutes == 40,
    '考试与课程按实际起止时间比较',
  );
  final overlaps = findExamConflicts(
    [a, exam('C', 9, 50, 10, 10)],
    [],
    includeClasses: false,
  );
  expect(overlaps.length == 1 && overlaps.single.minutes == 10, '考试重叠分钟数');
  expect(
    findExamConflicts(
      [exam('D', 10, 40, 11, 0)],
      [schedule],
      includeClasses: true,
    ).isEmpty,
    '课程结束时考试开始不算冲突',
  );
  expect(
    findExamConflicts(
      [exam('E', 10, 0, 11, 0, term: '2025-2026-1')],
      [schedule],
      includeClasses: true,
    ).isEmpty,
    '不同学期的课表不混用',
  );
  final route = SchoolNetwork.webvpn.route(SchoolNetwork.recordsService);
  expect(
    route.scheme == 'https' && route.host == 'webvpn.bit.edu.cn',
    '成绩接口支持 WebVPN 路由',
  );
  expect(
    isSchoolUrl(SchoolNetwork.recordsService) &&
        !isSchoolUrl(Uri.parse('http://other.bit.edu.cn/')),
    '仅为旧教务系统保留 HTTP 例外',
  );
  stdout.writeln('Academic model checks passed.');
}
