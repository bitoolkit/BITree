import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/async/cancelable_request.dart';
import '../../ui/external_link.dart';
import '../legacy_yanhekt.dart';
import '../model.dart';
import 'study_common.dart';
import 'study_live_player.dart';

class LegacyLiveBrowser extends StatefulWidget {
  const LegacyLiveBrowser({super.key});
  @override
  State<LegacyLiveBrowser> createState() => _LegacyLiveBrowserState();
}

class _LegacyLiveBrowserState extends State<LegacyLiveBrowser> {
  final _repository = LegacyYanhektRepository();
  CancellationToken? _request;
  final _query = TextEditingController();
  List<LegacyLive> _items = [];
  String _keyword = '';
  int _page = 0;
  bool _more = false;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_read()));
  }

  Future<void> _read({bool more = false}) async {
    final keyword = more ? _keyword : _query.text.trim();
    if (_loading && more) return;
    _request?.cancel();
    final request = CancellationToken();
    _request = request;
    setState(() {
      if (keyword != _keyword) {
        _items = [];
        _page = 0;
        _more = false;
      }
      _keyword = keyword;
      _loading = true;
      _failed = false;
    });
    final page = more ? _page + 1 : 1;
    final result = await studyOperation(
      context,
      '读取旧版直播',
      () => _repository.lives(request, keyword: keyword, page: page),
    );
    if (!mounted || !identical(_request, request)) return;
    setState(() {
      _loading = false;
      _failed = result == null;
      if (result != null) {
        _items = more ? [..._items, ...result.items] : result.items;
        _page = page;
        _more = result.more;
      }
    });
  }

  @override
  void dispose() {
    _request?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _query,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _read(),
                      decoration: InputDecoration(
                        labelText: '搜索课程',
                        suffixIcon: IconButton(
                          tooltip: '搜索',
                          onPressed: () => _read(),
                          icon: const Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '刷新直播',
                    onPressed: _loading ? null : () => _read(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _items.isEmpty
                  ? Center(
                      child: _loading
                          ? const CircularProgressIndicator()
                          : StudyEmpty(
                              text: _failed ? '无法获取旧版直播' : '没有找到直播或预告',
                              action: _failed
                                  ? TextButton(
                                      onPressed: () => _read(),
                                      child: const Text('重试'),
                                    )
                                  : null,
                            ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _read(),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          for (final item in _items)
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              title: Text(item.title),
                              subtitle: Text(
                                '${_time(item.startsAt)}–${_clock(item.endsAt)}${item.location.isEmpty ? '' : '\n${item.location}'}',
                              ),
                              trailing: Text(
                                item.status.label,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color:
                                          item.status == StudyLectureStatus.live
                                          ? Theme.of(context).colorScheme.error
                                          : Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                    ),
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => _LegacyLiveScreen(
                                    item: item,
                                    repository: _repository,
                                  ),
                                ),
                              ),
                            ),
                          if (_more)
                            TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => _read(more: true),
                              child: const Text('加载更多'),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _clock(DateTime value) {
  final date = value.toUtc().add(const Duration(hours: 8));
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String _time(DateTime value) {
  final date = value.toUtc().add(const Duration(hours: 8));
  return '${date.month}月${date.day}日 ${_clock(value)}';
}

class _LegacyLiveScreen extends StatelessWidget {
  const _LegacyLiveScreen({required this.item, required this.repository});
  final LegacyLive item;
  final LegacyYanhektRepository repository;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(item.title)),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${_time(item.startsAt)}–${_clock(item.endsAt)}${item.location.isEmpty ? '' : '  ${item.location}'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                StudyLivePlayer(
                  initialStatus: item.status,
                  load: (cancel) => repository.streams(item.id, cancel),
                  endedAction: TextButton(
                    onPressed: () => openExternalLink(
                      context,
                      Uri.https('www.yanhekt.cn'),
                      failureTitle: '无法打开延河课堂',
                    ),
                    child: const Text('打开延河课堂'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
