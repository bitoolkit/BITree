import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/async/cancelable_request.dart';
import '../library.dart';
import '../model.dart';
import 'study_common.dart';
import 'study_layout.dart';

class StudySearchScreen extends StatefulWidget {
  const StudySearchScreen({super.key, required this.app, this.onLocal});
  final AppController app;
  final VoidCallback? onLocal;
  @override
  State<StudySearchScreen> createState() => _StudySearchScreenState();
}

class _StudySearchScreenState extends State<StudySearchScreen> {
  final _query = TextEditingController();
  final _requests = LatestRequest();
  List<StudyCourse> _results = [];
  bool _loading = false;
  bool _searched = false;
  bool _more = false;
  int _page = 1;
  String _search = '';
  @override
  void dispose() {
    _requests.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _find({bool more = false}) async {
    if (!await studyAccount(context, widget.app) || !mounted) return;
    setState(() => _loading = true);
    final query = more ? _search : _query.text.trim();
    final uri = Uri.tryParse(query);
    final id =
        uri != null &&
            (uri.host == 'yanhekt.cn' || uri.host.endsWith('.yanhekt.cn'))
        ? (uri.queryParameters['id'] ??
              uri.queryParameters['course_id'] ??
              RegExp(r'/coursedetail/(\d+)').firstMatch(uri.path)?[1])
        : null;
    try {
      await studyOperation(
        context,
        '搜索课程',
        () => _requests.run((cancel) async {
          if (id != null) {
            final course = await widget.app.study.refreshCourse(
              id,
              studyVerify(context),
              cancel,
            );
            if (mounted) Navigator.pop(context, course);
            return;
          }
          final page = more ? _page + 1 : 1;
          final results = await widget.app.study.repository.courses(
            studyVerify(context),
            cancel,
            search: query,
            page: page,
          );
          cancel.check();
          if (!mounted) return;
          setState(() {
            _search = query;
            _page = page;
            _results = more ? [..._results, ...results] : results;
            _more = results.length == 30;
            _searched = true;
          });
        }),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add(StudyCourse course) async {
    setState(() => _loading = true);
    final result = await studyOperation(
      context,
      '添加课程',
      () => widget.app.study.refreshCourse(
        course.id,
        studyVerify(context),
        CancellationToken(),
      ),
    );
    if (mounted && result != null) Navigator.pop(context, result);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const StudyAppBar('添加课程'),
    body: SafeArea(
      child: StudyContent(
        maxWidth: 1200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '课程、教师或延河课堂链接',
                suffixIcon: IconButton(
                  tooltip: '搜索',
                  onPressed: _loading ? null : _find,
                  icon: const Icon(Icons.search_rounded),
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _find(),
            ),
            const SizedBox(height: 24),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: LayoutBuilder(
                builder: (context, size) {
                  final local = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '本地录播',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      const Text('先选择或创建课程，再导入录播。'),
                      if (widget.onLocal != null) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: widget.onLocal,
                          icon: const Icon(
                            Icons.folder_open_outlined,
                            size: 18,
                          ),
                          label: const Text('创建本地课程'),
                        ),
                      ],
                      const Divider(height: 32),
                      Text(
                        '同名课程合并展示，进入课程后可切换教学班。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  );
                  final list = ListView(
                    children: [
                      Text(
                        '搜索结果 · ${_results.length} 门',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      if (_results.isEmpty && !_loading)
                        StudyEmpty(
                          text: _searched ? '没有找到课程' : '搜索课程，或粘贴课程链接。',
                        ),
                      for (final course in _results) ...[
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                          leading: StudyCourseMark(course.title),
                          title: Text(course.title),
                          subtitle: Text(
                            '${course.teacher}\n${studyTermLabel(course.term)}',
                          ),
                          trailing:
                              widget.app.study.courses.any(
                                (item) => item.id == course.id,
                              )
                              ? const Text('已添加 ✓')
                              : const Icon(Icons.add_rounded),
                          onTap: _loading ? null : () => _add(course),
                        ),
                        const Divider(height: 1),
                      ],
                      if (_more)
                        TextButton(
                          onPressed: _loading ? null : () => _find(more: true),
                          child: const Text('加载更多'),
                        ),
                      if (size.maxWidth < 850) ...[
                        const SizedBox(height: 28),
                        StudyAside(below: true, child: local),
                      ],
                    ],
                  );
                  return size.maxWidth >= 850
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: list),
                            const SizedBox(width: 36),
                            SizedBox(
                              width: 270,
                              child: SingleChildScrollView(
                                child: StudyAside(child: local),
                              ),
                            ),
                          ],
                        )
                      : list;
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
