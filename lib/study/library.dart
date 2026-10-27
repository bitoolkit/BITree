import 'model.dart';

/// A library entry groups offerings without changing where their materials live.
class StudyCourseGroup {
  const StudyCourseGroup(this.courses);

  final List<StudyCourse> courses;
  String get title => courses.first.title;
  String get term => courses.first.remote ? courses.first.term : '';
  bool get remote => courses.first.remote;
  List<String> get teachers =>
      courses
          .map((course) => course.teacher)
          .where((teacher) => teacher.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  int? get lectureCount {
    if (courses.any(
      (course) =>
          course.remote &&
          course.lectureCount == null &&
          course.lectures.isEmpty,
    )) {
      return null;
    }
    return courses.fold<int>(
      0,
      (count, course) =>
          count + (course.lectureCount ?? course.lectures.length),
    );
  }
}

List<StudyCourseGroup> groupStudyCourses(Iterable<StudyCourse> courses) {
  final groups = <(String, String), List<StudyCourse>>{};
  for (final course in courses.where((course) => !course.isEmptyRemote)) {
    final title = course.title.replaceAll(RegExp(r'\s+'), '');
    final key = course.remote ? (course.term, title) : ('local', course.id);
    groups.putIfAbsent(key, () => []).add(course);
  }
  final result = groups.values.map(StudyCourseGroup.new).toList();
  result.sort((a, b) {
    if (a.remote != b.remote) return a.remote ? -1 : 1;
    final term = b.term.compareTo(a.term);
    return term != 0 ? term : a.title.compareTo(b.title);
  });
  return result;
}

String studyTermLabel(String term) {
  final parts = RegExp(r'^(\d{4}-\d{4})-([123])$').firstMatch(term);
  if (parts == null) return term.isEmpty ? '其他学期' : term;
  final season = switch (parts[2]) {
    '1' => '秋季学期',
    '2' => '春季学期',
    _ => '小学期',
  };
  return '${parts[1]} $season';
}
