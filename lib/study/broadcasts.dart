import 'package:flutter/foundation.dart';

import '../core/async/cancelable_request.dart';
import '../core/diagnostics.dart';
import '../school/verification.dart';
import 'legacy_yanhekt.dart';
import 'model.dart';
import 'yanhekt.dart';

class StudyClassroom {
  const StudyClassroom.timetable(StudyBroadcast item)
    : timetable = item,
      legacy = null;
  const StudyClassroom.public(LegacyLive item)
    : timetable = null,
      legacy = item;

  final StudyBroadcast? timetable;
  final LegacyLive? legacy;

  String get id => timetable != null
      ? 'course-${timetable!.course.id}-${timetable!.lecture.id}'
      : 'live-${legacy!.id}';
  String get title => timetable?.course.title ?? legacy!.title;
  String get location => legacy?.location ?? '';
  String get teacher => timetable?.course.teacher ?? '';
  DateTime get startsAt =>
      timetable != null ? timetable!.lecture.startsAt! : legacy!.startsAt;
  DateTime get endsAt =>
      timetable != null ? timetable!.lecture.endsAt! : legacy!.endsAt;
  StudyLectureStatus get status => timetable?.lecture.status ?? legacy!.status;
}

/// Both catalogs keep their own identifiers and transports. A failed source
/// leaves the other source, and the last successful results, available.
class StudyBroadcastCatalog extends ChangeNotifier {
  StudyBroadcastCatalog(this._repository, this._legacy);

  final YanhektRepository _repository;
  final LegacyYanhektRepository _legacy;
  final _requests = LatestRequest();
  List<StudyBroadcast> _today = [];
  List<LegacyLive> _public = [];
  bool _loading = false;
  bool _more = false;
  bool _disposed = false;
  int _page = 0;
  String _keyword = '';
  Object? _failure;

  bool get loading => _loading;
  bool get more => _more;
  Object? get failure => _failure;

  List<StudyClassroom> get items {
    final items = <String, StudyClassroom>{};
    for (final item in [
      ..._today.map(StudyClassroom.timetable),
      ..._public.map(StudyClassroom.public),
    ]) {
      items[item.id] = item;
    }
    return items.values.toList()..sort((a, b) {
      int rank(StudyLectureStatus status) => switch (status) {
        StudyLectureStatus.live => 0,
        StudyLectureStatus.upcoming => 1,
        _ => 2,
      };
      final status = rank(a.status).compareTo(rank(b.status));
      if (status != 0) return status;
      final date = a.status == StudyLectureStatus.upcoming
          ? a.startsAt.compareTo(b.startsAt)
          : b.startsAt.compareTo(a.startsAt);
      return date != 0 ? date : a.id.compareTo(b.id);
    });
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh(
    DateTime date,
    VerifySchoolLogin verify, {
    required bool signedIn,
    String keyword = '',
  }) async {
    await _requests.run((cancel) async {
      _failure = null;
      _loading = true;
      if (!signedIn) _today = [];
      if (keyword != _keyword) {
        _public = [];
        _more = false;
      }
      _keyword = keyword;
      _changed();
      try {
        Future<void> read(String name, Future<void> Function() run) async {
          try {
            await run();
            cancel.check();
          } on RequestCancelled {
            rethrow;
          } catch (failure, stack) {
            cancel.check();
            _failure = failure;
            AppDiagnostics.instance.error(name, failure, stack);
          }
          _changed();
        }

        await Future.wait([
          if (signedIn)
            read('读取课表直播', () async {
              final items = await _repository.broadcasts(date, verify, cancel);
              cancel.check();
              _today = items;
            }),
          read('读取公开直播', () async {
            final result = await _legacy.lives(cancel, keyword: keyword);
            cancel.check();
            _public = result.items;
            _page = 1;
            _more = result.more;
          }),
        ]);
      } finally {
        _loading = false;
        _changed();
      }
    });
  }

  Future<void> loadMore() async {
    if (_loading || !_more) return;
    await _requests.run((cancel) async {
      _loading = true;
      _failure = null;
      _changed();
      try {
        final page = _page + 1;
        final result = await _legacy.lives(
          cancel,
          keyword: _keyword,
          page: page,
        );
        cancel.check();
        _public = [..._public, ...result.items];
        _page = page;
        _more = result.more;
      } finally {
        _loading = false;
        _changed();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _requests.cancel();
    super.dispose();
  }
}
