import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/async/cancelable_request.dart';
import '../core/diagnostics.dart';
import '../school/verification.dart';
import 'bcut.dart';
import 'llm.dart';
import 'media.dart';
import 'model.dart';
import 'store.dart';
import 'tasks.dart';
import 'yanhekt.dart';

class StudyController extends ChangeNotifier {
  StudyController({
    required this.store,
    required this.repository,
    StudyModel? model,
  }) : model = model ?? StudyModel();
  final StudyStore store;
  final YanhektRepository repository;
  final StudyModel model;
  final tasks = StudyTasks();
  final _reads = LatestRequest();
  final _materials = <String, Future<LectureMaterials>>{};
  List<StudyCourse> _courses = [];
  bool _loading = false;
  bool _disposed = false;
  ({String course, String lecture})? lastReading;

  List<StudyCourse> get courses => List.unmodifiable(_courses);
  bool get loading => _loading;

  Future<void> load() async {
    try {
      _courses = await store.readCourses();
      lastReading = await store.readResume();
    } catch (failure, stack) {
      AppDiagnostics.instance.report('读取学习资料', failure, stack);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> remember(StudyCourse course, StudyLecture lecture) async {
    await store.writeResume(course.id, lecture.id);
    lastReading = (course: course.id, lecture: lecture.id);
    if (!_disposed) notifyListeners();
  }

  Future<LectureMaterials> materials(StudyCourse course, StudyLecture lecture) {
    final key = '${course.id}/${lecture.id}';
    return _materials.putIfAbsent(
      key,
      () => store.readMaterials(course.id, lecture.id).catchError((
        Object failure,
      ) {
        _materials.remove(key);
        throw failure;
      }),
    );
  }

  Future<void> save(StudyCourse course, StudyLecture lecture) async {
    await store.writeMaterials(
      course.id,
      lecture.id,
      await materials(course, lecture),
    );
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh(VerifySchoolLogin verify) async {
    _loading = true;
    notifyListeners();
    try {
      await _reads.run((cancel) async {
        final fresh = await repository.courses(verify, cancel);
        cancel.check();
        for (final item in fresh) {
          final index = _courses.indexWhere((old) => old.id == item.id);
          if (index < 0) {
            _courses.add(item);
          } else {
            _courses[index]
              ..title = item.title
              ..teacher = item.teacher
              ..term = item.term;
          }
        }
        await store.writeCourses(_courses);
      });
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<StudyCourse> refreshCourse(
    String id,
    VerifySchoolLogin verify,
    CancellationToken cancellation,
  ) async {
    final fresh = await repository.course(id, verify, cancellation);
    cancellation.check();
    final index = _courses.indexWhere((course) => course.id == id);
    final course = index < 0 ? fresh : _courses[index];
    if (index < 0) _courses.add(fresh);
    course
      ..title = fresh.title
      ..teacher = fresh.teacher
      ..term = fresh.term
      ..lectures = fresh.lectures;
    await store.writeCourses(_courses);
    if (!_disposed) notifyListeners();
    return course;
  }

  Future<StudyCourse> addLocalCourse(String title) async {
    final course = StudyCourse(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      remote: false,
    );
    _courses.add(course);
    await store.writeCourses(_courses);
    notifyListeners();
    return course;
  }

  Future<StudyLecture> importRecording(
    StudyCourse course,
    String path,
    String title,
  ) async {
    final lecture = StudyLecture(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      startsAt: DateTime.now(),
    );
    final directory = await store.lectureDirectory(course.id, lecture.id);
    final extension = path.split('.').last;
    final file = await File(path).copy('${directory.path}/screen.$extension');
    course.lectures = [lecture, ...course.lectures];
    final material = await materials(course, lecture);
    material.recordings = {'screen': file.path};
    await save(course, lecture);
    await store.writeCourses(_courses);
    return lecture;
  }

  void fetchTranscript(
    StudyCourse course,
    StudyLecture lecture,
    VerifySchoolLogin verify,
  ) {
    tasks.add(
      StudyTask(
        key: '${course.id}/${lecture.id}/transcript',
        title: '获取字幕',
        course: course.id,
        lecture: lecture.id,
        operation: (cancel, progress) async {
          progress(null, '正在获取平台字幕');
          final transcript = await repository.transcript(
            lecture.id,
            verify,
            cancel,
          );
          cancel.check();
          final material = await materials(course, lecture);
          material.transcript = transcript;
          await save(course, lecture);
        },
      ),
    );
  }

  void download(
    StudyCourse course,
    StudyLecture lecture,
    VerifySchoolLogin verify,
    String kind,
  ) {
    tasks.add(
      StudyTask(
        key: '${course.id}/${lecture.id}/download-$kind',
        title: kind == 'screen' ? '保存课件录播' : '保存教室录播',
        course: course.id,
        lecture: lecture.id,
        operation: (cancel, progress) async {
          progress(null, '正在读取录播地址');
          final streams = await repository.streams(
            course.id,
            lecture.id,
            verify,
            cancel,
          );
          final uri = streams.urls[kind];
          if (uri == null) {
            throw StateError('这节课没有${kind == 'screen' ? '课件' : '教室'}录播');
          }
          final directory = await store.lectureDirectory(course.id, lecture.id);
          final file = await StudyDownloader().download(
            uri,
            streams,
            Directory('${directory.path}/$kind'),
            cancel,
            progress,
          );
          cancel.check();
          final material = await materials(course, lecture);
          material.recordings = {...material.recordings, kind: file.path};
          await save(course, lecture);
        },
      ),
    );
  }

  void extractSlides(
    StudyCourse course,
    StudyLecture lecture,
    VerifySchoolLogin verify,
  ) {
    tasks.add(
      StudyTask(
        key: '${course.id}/${lecture.id}/slides',
        title: '提取课件',
        course: course.id,
        lecture: lecture.id,
        operation: (cancel, progress) async {
          final material = await materials(course, lecture);
          if (material.slidesComplete) return;
          var source = material.recordings['screen'];
          final proxy = StudyMediaProxy();
          try {
            if (source == null) {
              final streams = await repository.streams(
                course.id,
                lecture.id,
                verify,
                cancel,
              );
              final url = streams.urls['screen'];
              if (url == null) throw StateError('这节课没有课件画面');
              source = (await proxy.open(url, streams)).toString();
            }
            final directory = await store.lectureDirectory(
              course.id,
              lecture.id,
            );
            final slides = await StudySlideExtractor().extract(
              source,
              Directory('${directory.path}/slides'),
              cancel,
              progress,
              startAt: material.slideScanPosition,
              existing: material.slides,
              checkpoint: (position, slides) async {
                material.slideScanPosition = position;
                material.slides = List.of(slides);
                await save(course, lecture);
              },
            );
            cancel.check();
            material.slides = slides;
            material.slidesComplete = true;
            await save(course, lecture);
          } finally {
            await proxy.close();
          }
        },
      ),
    );
  }

  void transcribe(StudyCourse course, StudyLecture lecture, File audio) {
    tasks.add(
      StudyTask(
        key: '${course.id}/${lecture.id}/bcut',
        title: '必剪转写',
        pausable: false,
        course: course.id,
        lecture: lecture.id,
        operation: (cancel, progress) async {
          final segments = await BCutTranscriber().transcribe(
            audio,
            cancel,
            progress,
          );
          cancel.check();
          final material = await materials(course, lecture);
          material.transcript = segments;
          await save(course, lecture);
        },
      ),
    );
  }

  StudyTask? generation(
    StudyCourse course,
    StudyLecture? lecture,
    String kind,
  ) => tasks.items
      .where(
        (task) => task.key == '${course.id}/${lecture?.id ?? 'course'}/$kind',
      )
      .firstOrNull;

  void generate(
    StudyCourse course,
    StudyLecture? lecture,
    StudyModelSettings settings, {
    String? question,
  }) {
    final kind = lecture == null
        ? 'review'
        : question == null
        ? 'summary'
        : 'answer';
    late final StudyTask task;
    task = StudyTask(
      key: '${course.id}/${lecture?.id ?? 'course'}/$kind',
      title: switch (kind) {
        'review' => '生成复习提纲',
        'summary' => '整理笔记',
        _ => '课程问答',
      },
      course: course.id,
      lecture: lecture?.id ?? '',
      pausable: false,
      operation: (cancel, progress) async {
        task.output = '';
        final context = StringBuffer('${course.title}\n');
        final selected = lecture == null ? course.lectures : [lecture];
        for (final item in selected) {
          final material = await materials(course, item);
          context.writeln('\n课时：${item.title}，编号：${item.id}');
          for (final row in material.transcript) {
            context.writeln('[${studyTimestamp(row.start)}] ${row.text}');
          }
          if (material.notes.isNotEmpty) {
            context.writeln('用户笔记：${material.notes}');
          }
        }
        final hasMaterial = await Future.wait(
          selected.map((item) => materials(course, item)),
        );
        if (!hasMaterial.any(
          (item) => item.transcript.isNotEmpty || item.notes.isNotEmpty,
        )) {
          throw StateError('请先获取字幕或填写笔记');
        }
        final instruction =
            question ??
            (lecture == null
                ? '按课时整理复习提纲，串联概念，列出做题要求、作业、考勤和考试提示。引用使用 Markdown 链接：'
                      '[课时名 mm:ss](study-lecture:课时编号?seconds=秒数)。仅使用资料里出现的课时编号和时间。'
                : '整理本节课笔记：主要概念、方法、例题、作业、考勤和考试提示。保留必要推导，附时间戳。');
        try {
          await for (final text in model.generate(
            settings: settings,
            instruction: instruction,
            material: context.toString(),
            cancellation: cancel,
          )) {
            task.output += text;
            progress(null, '正在生成');
          }
        } finally {
          // Stopping or losing the connection keeps the text already received.
          if (task.output.isNotEmpty) {
            if (lecture == null) {
              course.review = task.output;
              await store.writeCourses(_courses);
            } else {
              final material = await materials(course, lecture);
              if (question == null) {
                material.summary = task.output;
              } else {
                material.question = question;
                material.answer = task.output;
              }
              await save(course, lecture);
            }
          }
        }
      },
    );
    tasks.add(task);
  }

  @override
  void dispose() {
    _disposed = true;
    _reads.cancel();
    tasks.dispose();
    super.dispose();
  }
}
