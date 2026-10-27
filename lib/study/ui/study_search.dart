import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/async/cancelable_request.dart';
import '../model.dart';
import 'study_common.dart';

class StudySearchScreen extends StatefulWidget {
  const StudySearchScreen({super.key, required this.app});
  final AppController app;
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('搜索课程')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
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
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _results.isEmpty
                  ? StudyEmpty(text: _searched ? '没有找到课程' : '搜索课程，或粘贴课程链接。')
                  : ListView(
                      children: [
                        for (final course in _results)
                          ListTile(
                            title: Text(course.title),
                            subtitle: Text('${course.term}  ${course.teacher}'),
                            trailing: const Icon(Icons.add_rounded),
                            onTap: _loading
                                ? null
                                : () async {
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
                                    if (context.mounted && result != null) {
                                      Navigator.pop(context, result);
                                    }
                                    if (mounted) {
                                      setState(() => _loading = false);
                                    }
                                  },
                          ),
                        if (_more)
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => _find(more: true),
                            child: const Text('加载更多'),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
