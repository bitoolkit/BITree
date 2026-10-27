import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../model.dart';
import 'study_common.dart';
import 'study_tasks.dart';

Future<void> showStudyOrganize(
  BuildContext context,
  AppController app,
  StudyCourse course, {
  StudyLecture? lecture,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) =>
        StudyOrganizeScreen(app: app, course: course, lecture: lecture),
  ),
);

class StudyOrganizeScreen extends StatefulWidget {
  const StudyOrganizeScreen({
    super.key,
    required this.app,
    required this.course,
    this.lecture,
  });
  final AppController app;
  final StudyCourse course;
  final StudyLecture? lecture;
  @override
  State<StudyOrganizeScreen> createState() => _StudyOrganizeScreenState();
}

class _StudyOrganizeScreenState extends State<StudyOrganizeScreen> {
  late final _lectures = widget.course.lectures
      .where((lecture) => lecture.status == StudyLectureStatus.recorded)
      .toList();
  late final _selected = <String>{
    if (widget.lecture case final lecture?)
      lecture.id
    else
      ..._lectures.take(3).map((lecture) => lecture.id),
  };
  late final _outputs = <String>{
    if (widget.course.remote) 'transcript',
    'slides',
  };
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    if (widget.course.remote && !await studyAccount(context, widget.app)) {
      if (mounted) setState(() => _starting = false);
      return;
    }
    if (!mounted) return;
    final verify = studyVerify(context);
    for (final item in _lectures.where(
      (lecture) => _selected.contains(lecture.id),
    )) {
      final remote = widget.course.remote && !item.id.startsWith('local-');
      if (remote && _outputs.contains('transcript')) {
        widget.app.study.fetchTranscript(widget.course, item, verify);
      }
      if (_outputs.contains('slides')) {
        widget.app.study.extractSlides(widget.course, item, verify);
      }
      for (final kind in ['screen', 'classroom']) {
        if (remote && _outputs.contains(kind)) {
          widget.app.study.download(widget.course, item, verify, kind);
        }
      }
    }
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => StudyTaskScreen(app: widget.app)),
    );
  }

  Widget _selection(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              '选择课时 · 已选 ${_selected.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              if (_selected.length == _lectures.length) {
                _selected.clear();
              } else {
                _selected.addAll(_lectures.map((lecture) => lecture.id));
              }
            }),
            child: Text(_selected.length == _lectures.length ? '全不选' : '全选'),
          ),
        ],
      ),
      const Divider(height: 16),
      for (final lecture in _lectures)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(studyLectureTitle(lecture)),
          subtitle: Text(lectureDate(lecture)),
          value: _selected.contains(lecture.id),
          onChanged: (value) => setState(
            () => value == true
                ? _selected.add(lecture.id)
                : _selected.remove(lecture.id),
          ),
        ),
      if (_lectures.isEmpty) const StudyEmpty(text: '暂无可整理的录播'),
    ],
  );

  Widget _options(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('保存内容', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      for (final (key, label, detail) in [
        ('slides', '提取课件', '合并重复画面，可导出为 PDF'),
        if (widget.course.remote) ...[
          ('transcript', '课堂字幕', '保留时间戳，可定位到录播'),
          ('screen', '课件录播', '保存后可离线观看'),
          ('classroom', '教室录播', '保存后可离线观看'),
        ],
      ])
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(label),
          subtitle: Text(detail),
          value: _outputs.contains(key),
          onChanged: (value) => setState(
            () => value == true ? _outputs.add(key) : _outputs.remove(key),
          ),
        ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _starting || _selected.isEmpty || _outputs.isEmpty
            ? null
            : _start,
        child: Text(_starting ? '正在创建任务' : '开始整理 ${_selected.length} 课时'),
      ),
      const SizedBox(height: 16),
      Text(
        '资料保存在对应课时中。可离开页面，稍后到处理任务查看。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('整理课程资料')),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: LayoutBuilder(
            builder: (context, size) => SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.course.title,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  if (size.maxWidth >= 850)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _selection(context)),
                        const SizedBox(width: 40),
                        SizedBox(width: 280, child: _options(context)),
                      ],
                    )
                  else ...[
                    _selection(context),
                    const Divider(height: 40),
                    _options(context),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
