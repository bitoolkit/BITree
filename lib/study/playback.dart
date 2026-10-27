import 'dart:convert';

import 'package:pointycastle/export.dart';

import 'model.dart';

class LectureStreams {
  const LectureStreams({
    required this.urls,
    this.duration = Duration.zero,
    this.status = StudyLectureStatus.recorded,
    this.referer = 'https://aita.yanhekt.cn/',
    this._signing,
  });

  final Map<String, Uri> urls;
  final Duration duration;
  final StudyLectureStatus status;
  final String referer;
  final ({String user, String tenant, String phone})? _signing;

  Uri sign(Uri url, {DateTime? at}) {
    final identity = _signing;
    if (identity == null || !url.path.startsWith('/play/')) return url;
    final seconds = ((at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000)
        .toString();
    final input = utf8.encode(
      '${url.path}${identity.user}${identity.tenant}${identity.phone.split('').reversed.join()}$seconds',
    );
    final digest = MD5Digest()
        .process(input)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return url.replace(
      queryParameters: {'t': '${identity.user}-$seconds-$digest'},
    );
  }
}
