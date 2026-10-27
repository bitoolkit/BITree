import 'dart:io';

import 'package:flutter/material.dart';

import '../model.dart';
import 'study_common.dart';

class StudyContent extends StatelessWidget {
  const StudyContent({super.key, required this.child, this.maxWidth = 1380});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(7),
    );
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(0, MediaQuery.sizeOf(context).width < 760 ? 44 : 38),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      shape: WidgetStatePropertyAll(shape),
      textStyle: WidgetStatePropertyAll(
        theme.textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: style.merge(theme.filledButtonTheme.style),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: style.merge(theme.outlinedButtonTheme.style),
        ),
        textButtonTheme: TextButtonThemeData(
          style: style
              .copyWith(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 4),
                ),
              )
              .merge(theme.textButtonTheme.style),
        ),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: LayoutBuilder(
            builder: (context, size) => Padding(
              padding: EdgeInsets.fromLTRB(
                size.maxWidth < 760 ? 17 : 30,
                20,
                size.maxWidth < 760 ? 17 : 30,
                20,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class StudyHeading extends StatelessWidget {
  const StudyHeading(this.title, {super.key, this.subtitle, this.leading});
  final String title;
  final String? subtitle;
  final Widget? leading;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (leading != null) ...[leading!, const SizedBox(width: 15)],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: MediaQuery.sizeOf(context).width < 480 ? 23 : 26,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            if (subtitle?.isNotEmpty == true) ...[
              const SizedBox(height: 7),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    ],
  );
}

class StudyAppBar extends StatelessWidget implements PreferredSizeWidget {
  const StudyAppBar(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 64 : 80);
  @override
  Widget build(BuildContext context) => AppBar(
    toolbarHeight: preferredSize.height,
    title: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontSize: MediaQuery.sizeOf(context).width < 480 ? 23 : 26,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(height: 1.25),
          ),
        ],
      ],
    ),
  );
}

({Color fill, Color ink}) _courseColors(BuildContext context, String title) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final index = title.runes.fold<int>(0, (sum, rune) => sum + rune) % 4;
  final colors = dark
      ? [
          (0xff263b35, 0xffb1d9c7),
          (0xff253a4e, 0xffafc7e5),
          (0xff3a304b, 0xffc9b9e6),
          (0xff42332b, 0xffe9bb97),
        ]
      : [
          (0xffe1efeb, 0xff37645a),
          (0xffe3ecfc, 0xff36567f),
          (0xffeee8f8, 0xff70588e),
          (0xfff8e9de, 0xff8b5538),
        ];
  return (fill: Color(colors[index].$1), ink: Color(colors[index].$2));
}

String _initials(String title) =>
    String.fromCharCodes(title.trim().runes.take(2)).toUpperCase();

class StudyCourseMark extends StatelessWidget {
  const StudyCourseMark(this.title, {super.key, this.large = false});
  final String title;
  final bool large;
  @override
  Widget build(BuildContext context) {
    final colors = _courseColors(context, title);
    return ExcludeSemantics(
      child: Container(
        width: large ? 46 : 36,
        height: large ? 56 : 42,
        decoration: BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(5),
        ),
        alignment: Alignment.center,
        child: Text(
          _initials(title),
          style: TextStyle(
            color: colors.ink,
            fontSize: large ? 17 : 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class StudyCourseCover extends StatelessWidget {
  const StudyCourseCover({
    super.key,
    required this.course,
    required this.lecture,
    this.material,
  });
  final StudyCourse course;
  final StudyLecture lecture;
  final LectureMaterials? material;
  @override
  Widget build(BuildContext context) {
    final colors = _courseColors(context, course.title);
    final file = material?.slides
        .where((slide) => !slide.hidden)
        .firstOrNull
        ?.file;
    final placeholder = ColoredBox(
      color: colors.fill,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Text(
              course.title.toLowerCase().contains('java')
                  ? '{ }'
                  : _initials(course.title),
              style: TextStyle(
                fontSize: 38,
                color: colors.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            right: 8,
            child: Text(
              lectureDate(lecture),
              style: TextStyle(color: colors.ink, fontSize: 11),
            ),
          ),
        ],
      ),
    );
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: file == null
            ? placeholder
            : Image.file(
                File(file),
                fit: BoxFit.contain,
                cacheWidth: 360,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class StudyAside extends StatelessWidget {
  const StudyAside({super.key, required this.child, this.below = false});
  final Widget child;
  final bool below;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: below
          ? Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            )
          : Border(
              left: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
    ),
    child: Padding(
      padding: below
          ? const EdgeInsets.only(top: 24)
          : const EdgeInsets.only(left: 25),
      child: child,
    ),
  );
}

class StudyNotes extends StatelessWidget {
  const StudyNotes({
    super.key,
    required this.text,
    required this.onSeek,
    this.timeline = false,
  });
  final String text;
  final ValueChanged<Duration> onSeek;
  final bool timeline;
  @override
  Widget build(BuildContext context) {
    final times = RegExp(
      r'^\[(\d{1,3}):(\d{2})\]\s*',
      multiLine: true,
    ).allMatches(text).toList();
    if (times.isEmpty) return StudyMarkdown(text: text, onSeek: onSeek);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (text.substring(0, times.first.start).trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: StudyMarkdown(
              text: text.substring(0, times.first.start),
              onSeek: onSeek,
            ),
          ),
        for (final (index, match) in times.indexed)
          Builder(
            builder: (context) {
              final position = Duration(
                minutes: int.parse(match[1]!),
                seconds: int.parse(match[2]!),
              );
              final body = StudyMarkdown(
                text: text
                    .substring(
                      match.end,
                      index + 1 < times.length
                          ? times[index + 1].start
                          : text.length,
                    )
                    .trim(),
                onSeek: onSeek,
              );
              final time = TextButton(
                onPressed: () => onSeek(position),
                style: TextButton.styleFrom(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  textStyle: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(fontSize: 11),
                ),
                child: Text(studyTimestamp(position)),
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: timeline
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          time,
                          const SizedBox(width: 14),
                          Expanded(child: body),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [time, const SizedBox(height: 8), body],
                      ),
              );
            },
          ),
      ],
    );
  }
}
