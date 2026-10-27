import 'dart:convert';

class StudyCourse {
  StudyCourse({
    required this.id,
    required this.title,
    this.teacher = '',
    this.term = '',
    this.remote = true,
    this.lectures = const [],
    this._lectureCount,
    this.review = '',
    this.reviewLectureIds = const [],
  });

  final String id;
  String title;
  String teacher;
  String term;
  final bool remote;
  List<StudyLecture> lectures;
  int? _lectureCount;
  String review;
  List<String> reviewLectureIds;

  // Loaded lectures take precedence over the course-list API's summary.
  int? get lectureCount =>
      lectures.isNotEmpty ? lectures.length : _lectureCount;
  set lectureCount(int? value) => _lectureCount = value;

  bool get isEmptyRemote =>
      remote && lectureCount == 0 && lectures.isEmpty && review.isEmpty;

  factory StudyCourse.fromJson(Map<String, dynamic> json) => StudyCourse(
    id: json['id'] as String,
    title: json['title'] as String,
    teacher: json['teacher'] as String? ?? '',
    term: json['term'] as String? ?? '',
    remote: json['remote'] as bool? ?? true,
    review: json['review'] as String? ?? '',
    reviewLectureIds: List<String>.from(
      json['reviewLectureIds'] as List? ?? [],
    ),
    lectureCount: json['lectureCount'] as int?,
    lectures: [
      for (final item in json['lectures'] as List)
        StudyLecture.fromJson(item as Map<String, dynamic>),
    ],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'teacher': teacher,
    'term': term,
    'remote': remote,
    'review': review,
    'reviewLectureIds': reviewLectureIds,
    'lectureCount': lectureCount,
    'lectures': lectures.map((item) => item.toJson()).toList(),
  };
}

enum StudyLectureStatus {
  recorded,
  live,
  upcoming,
  processing,
  ended;

  static StudyLectureStatus fromYanhekt(Object? value) => switch ('$value') {
    '1' => live,
    '2' => upcoming,
    '3' => processing,
    '6' => recorded,
    _ => ended,
  };

  bool get canPlay => this == live || this == recorded;
  String get label => switch (this) {
    live => '直播中',
    upcoming => '尚未开始',
    processing => '录播生成中',
    ended => '暂无录播',
    recorded => '录播',
  };
}

class StudyLecture {
  const StudyLecture({
    required this.id,
    required this.title,
    this.startsAt,
    this.endsAt,
    this.status = StudyLectureStatus.recorded,
  });
  final String id;
  final String title;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final StudyLectureStatus status;

  factory StudyLecture.fromJson(Map<String, dynamic> json) => StudyLecture(
    id: json['id'] as String,
    title: json['title'] as String,
    startsAt: DateTime.tryParse(json['startsAt'] as String? ?? ''),
    endsAt: DateTime.tryParse(json['endsAt'] as String? ?? ''),
    status: StudyLectureStatus.values.byName(
      json['status'] as String? ?? 'recorded',
    ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startsAt': startsAt?.toIso8601String(),
    'endsAt': endsAt?.toIso8601String(),
    'status': status.name,
  };
}

class StudyBroadcast {
  const StudyBroadcast({required this.course, required this.lecture});
  final StudyCourse course;
  final StudyLecture lecture;
}

class TranscriptSegment {
  const TranscriptSegment(this.start, this.end, this.text);
  final Duration start;
  final Duration end;
  final String text;

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) =>
      TranscriptSegment(
        Duration(milliseconds: json['start'] as int),
        Duration(milliseconds: json['end'] as int),
        json['text'] as String,
      );

  Map<String, dynamic> toJson() => {
    'start': start.inMilliseconds,
    'end': end.inMilliseconds,
    'text': text,
  };
}

class StudySlide {
  StudySlide({required this.file, required this.position, this.hidden = false});
  final String file;
  final Duration position;
  bool hidden;

  factory StudySlide.fromJson(Map<String, dynamic> json) => StudySlide(
    file: json['file'] as String,
    position: Duration(milliseconds: json['position'] as int),
    hidden: json['hidden'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'file': file,
    'position': position.inMilliseconds,
    'hidden': hidden,
  };
}

/// Local material belongs to one lecture; no course-wide material bucket.
class LectureMaterials {
  LectureMaterials({
    this.recordings = const {},
    this.transcript = const [],
    this.slides = const [],
    this.notes = '',
    this.summary = '',
    this.answer = '',
    this.question = '',
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.slideScanPosition = Duration.zero,
    this.slidesComplete = false,
  });

  Map<String, String> recordings;
  List<TranscriptSegment> transcript;
  List<StudySlide> slides;
  String notes;
  String summary;
  String answer;
  String question;
  Duration position;
  Duration duration;
  Duration slideScanPosition;
  bool slidesComplete;

  factory LectureMaterials.fromJson(Map<String, dynamic> json) =>
      LectureMaterials(
        recordings: Map<String, String>.from(json['recordings'] as Map? ?? {}),
        transcript: [
          for (final item in json['transcript'] as List? ?? [])
            TranscriptSegment.fromJson(item as Map<String, dynamic>),
        ],
        slides: [
          for (final item in json['slides'] as List? ?? [])
            StudySlide.fromJson(item as Map<String, dynamic>),
        ],
        notes: json['notes'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        answer: json['answer'] as String? ?? '',
        question: json['question'] as String? ?? '',
        position: Duration(milliseconds: json['position'] as int? ?? 0),
        duration: Duration(milliseconds: json['duration'] as int? ?? 0),
        slideScanPosition: Duration(
          milliseconds: json['slideScanPosition'] as int? ?? 0,
        ),
        slidesComplete: json['slidesComplete'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
    'recordings': recordings,
    'transcript': transcript.map((item) => item.toJson()).toList(),
    'slides': slides.map((item) => item.toJson()).toList(),
    'notes': notes,
    'summary': summary,
    'answer': answer,
    'question': question,
    'position': position.inMilliseconds,
    'duration': duration.inMilliseconds,
    'slideScanPosition': slideScanPosition.inMilliseconds,
    'slidesComplete': slidesComplete,
  };
}

enum StudyMaterial { video, slides, transcript, notes, question }

String studyTimestamp(Duration position) {
  final seconds = position.inSeconds;
  final minutes = seconds ~/ 60;
  return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Supports the timestamped text used by exports and ordinary SRT/VTT files.
List<TranscriptSegment> parseTranscript(String text) {
  final lines = const LineSplitter().convert(text.replaceAll('\r', ''));
  final result = <TranscriptSegment>[];
  final timestamp = RegExp(r'(\d{1,2}:)?\d{1,2}:\d{2}(?:[.,]\d{1,3})?');
  Duration read(String value) {
    final parts = value
        .replaceAll(',', '.')
        .split(':')
        .map(double.parse)
        .toList();
    var seconds = 0.0;
    for (final part in parts) {
      seconds = seconds * 60 + part;
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final matches = timestamp.allMatches(line).toList();
    if (matches.isEmpty) continue;
    final start = read(matches.first[0]!);
    if (line.contains('-->') && matches.length >= 2) {
      final body = <String>[];
      while (index + 1 < lines.length && lines[index + 1].trim().isNotEmpty) {
        body.add(lines[++index]);
      }
      result.add(
        TranscriptSegment(start, read(matches[1][0]!), body.join('\n')),
      );
    } else if (line.trimLeft().startsWith('[')) {
      final content = line.substring(line.indexOf(']') + 1).trim();
      result.add(
        TranscriptSegment(start, start + const Duration(seconds: 10), content),
      );
    }
  }
  return result..sort((a, b) => a.start.compareTo(b.start));
}
