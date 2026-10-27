import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'model.dart';

class StudyStore {
  StudyStore({this._directory});
  final Directory? _directory;
  Future<void> _pending = Future.value();

  Future<Directory> get directory async {
    final root =
        _directory ??
        Directory('${(await getApplicationSupportDirectory()).path}/study');
    return root.create(recursive: true);
  }

  Future<Directory> lectureDirectory(String course, String lecture) async {
    // Platform IDs are used as path components, never course titles or URLs.
    if (!RegExp(r'^[\w-]+$').hasMatch(course) ||
        !RegExp(r'^[\w-]+$').hasMatch(lecture)) {
      throw const FormatException('课时编号不正确');
    }
    return Directory('${(await directory).path}/$course/$lecture')
        .create(recursive: true);
  }

  Future<List<StudyCourse>> readCourses() async {
    final file = File('${(await directory).path}/courses.json');
    if (!await file.exists()) return [];
    return [
      for (final item in jsonDecode(await file.readAsString()) as List)
        StudyCourse.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<void> writeCourses(List<StudyCourse> courses) async => _write(
    File('${(await directory).path}/courses.json'),
    jsonEncode(courses.map((item) => item.toJson()).toList()),
  );

  Future<({String course, String lecture})?> readResume() async {
    final file = File('${(await directory).path}/resume.json');
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return (
      course: json['course'] as String,
      lecture: json['lecture'] as String,
    );
  }

  Future<void> writeResume(String course, String lecture) async => _write(
    File('${(await directory).path}/resume.json'),
    jsonEncode({'course': course, 'lecture': lecture}),
  );

  Future<LectureMaterials> readMaterials(String course, String lecture) async {
    final file = File(
      '${(await lectureDirectory(course, lecture)).path}/materials.json',
    );
    if (!await file.exists()) return LectureMaterials();
    return LectureMaterials.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  Future<void> writeMaterials(
    String course,
    String lecture,
    LectureMaterials material,
  ) async => _write(
    File('${(await lectureDirectory(course, lecture)).path}/materials.json'),
    jsonEncode(material.toJson()),
  );

  Future<void> _write(File file, String content) {
    final result = _pending.then((_) async {
      final temporary = File('${file.path}.pending');
      await temporary.writeAsString(content, flush: true);
      await temporary.rename(file.path);
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
