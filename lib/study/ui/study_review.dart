import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../ui/app_notice.dart';
import '../model.dart';
import '../tasks.dart';
import 'study_common.dart';
import 'study_reader.dart';
import 'study_services.dart';

class StudyReviewScreen extends StatefulWidget {
  const StudyReviewScreen({super.key, required this.app, required this.course});
  final AppController app;
  final StudyCourse course;
  @override
  State<StudyReviewScreen> createState() => _StudyReviewScreenState();
}

class _StudyReviewScreenState extends State<StudyReviewScreen> {
  bool _loading = false;
  Future<void> _generate() async {
    setState(() => _loading = true);
    try {
      final materials = await Future.wait(
        widget.course.lectures.map(
          (lecture) => widget.app.study.materials(widget.course, lecture),
        ),
      );
      if (!mounted) return;
      if (!materials.any(
        (item) => item.transcript.isNotEmpty || item.notes.isNotEmpty,
      )) {
        showAppNotice(context, '请先获取字幕或填写笔记');
        return;
      }
      var settings = await studyOperation(
        context,
        '读取模型设置',
        widget.app.study.model.readSettings,
      );
      if (settings == null && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<bool>(
            builder: (_) => StudyServices(model: widget.app.study.model),
          ),
        );
        settings = await widget.app.study.model.readSettings();
      }
      if (settings != null && mounted) {
        widget.app.study.generate(widget.course, null, settings);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.course.title}复习')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListenableBuilder(
          listenable: widget.app.study.tasks,
          builder: (context, _) {
            final task = widget.app.study.generation(
              widget.course,
              null,
              'review',
            );
            final active =
                task != null &&
                [
                  StudyTaskStatus.running,
                  StudyTaskStatus.queued,
                ].contains(task.status);
            final text = task?.output.isNotEmpty == true
                ? task!.output
                : widget.course.review;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '使用已获取的字幕和随堂笔记。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: active
                      ? TextButton.icon(
                          onPressed: () => widget.app.study.tasks.cancel(task),
                          icon: const Icon(Icons.stop_rounded),
                          label: const Text('停止生成'),
                        )
                      : FilledButton(
                          onPressed: _loading ? null : _generate,
                          child: const Text('生成复习提纲'),
                        ),
                ),
                const SizedBox(height: 16),
                if (active && text.isEmpty)
                  const LinearProgressIndicator(minHeight: 2),
                StudyMarkdown(
                  text: text,
                  onLecture: (id, position) {
                    final lecture = widget.course.lectures
                        .where((item) => item.id == id)
                        .firstOrNull;
                    if (lecture != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => StudyReader(
                            app: widget.app,
                            course: widget.course,
                            lecture: lecture,
                            initial: StudyMaterial.video,
                            initialPosition: position,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
