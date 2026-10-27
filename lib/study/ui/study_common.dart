import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../app/controller.dart';
import '../../core/async/cancelable_request.dart';
import '../../core/diagnostics.dart';
import '../../core/error_message.dart';
import '../../school/ui/school_screen.dart';
import '../../school/ui/school_verification_dialog.dart';
import '../../school/verification.dart';
import '../../ui/app_notice.dart';
import '../../ui/external_link.dart';
import '../model.dart';

Future<T?> studyOperation<T>(
  BuildContext context,
  String label,
  Future<T> Function() run,
) async {
  try {
    return await run();
  } on RequestCancelled {
    return null;
  } catch (failure, stack) {
    AppDiagnostics.instance.error(label, failure, stack);
    if (context.mounted) showAppNotice(context, errorMessage(failure));
    return null;
  }
}

class StudyEmpty extends StatelessWidget {
  const StudyEmpty({super.key, required this.text, this.action});
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class StudyMarkdown extends StatelessWidget {
  const StudyMarkdown({
    super.key,
    required this.text,
    this.onSeek,
    this.onLecture,
  });
  final String text;
  final ValueChanged<Duration>? onSeek;
  final void Function(String, Duration)? onLecture;
  @override
  Widget build(BuildContext context) {
    final linked = onSeek == null
        ? text
        : text.replaceAllMapped(
            RegExp(r'\[(\d{1,3}):(\d{2})\](?!\()'),
            (match) =>
                '[${match[1]}:${match[2]}](study-time:${int.parse(match[1]!) * 60 + int.parse(match[2]!)})',
          );
    return MarkdownBody(
      data: linked,
      selectable: true,
      imageBuilder: (uri, title, alt) => uri.scheme == 'file'
          ? Image.file(File.fromUri(uri), semanticLabel: alt)
          : Image.network(uri.toString(), semanticLabel: alt),
      onTapLink: (_, href, _) {
        final url = Uri.tryParse(href ?? '');
        if (url == null) return;
        if (url.scheme == 'study-lecture') {
          final seconds = int.tryParse(url.queryParameters['seconds'] ?? '');
          if (seconds != null && seconds >= 0) {
            onLecture?.call(url.path, Duration(seconds: seconds));
          }
        } else if (url.scheme == 'study-time') {
          onSeek?.call(Duration(seconds: int.parse(url.path)));
        } else if (url.scheme == 'https' || url.scheme == 'http') {
          openExternalLink(context, url, failureTitle: '无法打开链接');
        }
      },
    );
  }
}

String lectureDate(StudyLecture lecture) {
  final date = lecture.startsAt?.toUtc().add(const Duration(hours: 8));
  return date == null ? '' : '${date.month}月${date.day}日';
}

String studyLectureTitle(StudyLecture lecture) =>
    lecture.title.replaceFirst(RegExp(r'^\d{4}[-/]\d{1,2}[-/]\d{1,2}\s*'), '');

VerifySchoolLogin studyVerify(BuildContext context) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return (request) => navigator.mounted
      ? verifySchoolLogin(navigator.context, request)
      : Future.value(null);
}

Future<bool> studyAccount(BuildContext context, AppController app) async {
  if (app.school.username != null) return true;
  return await openSchoolPage(context, app, action: SchoolAction.signIn) ==
      true;
}
