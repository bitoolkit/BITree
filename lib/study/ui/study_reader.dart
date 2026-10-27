import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/controller.dart';
import '../../core/async/cancelable_request.dart';
import '../../core/diagnostics.dart';
import '../../ui/app_menu_anchor.dart';
import '../../ui/app_notice.dart';
import '../llm.dart';
import '../media.dart';
import '../model.dart';
import '../tasks.dart';
import 'study_common.dart';
import 'study_organize.dart';
import 'study_services.dart';

class StudyReader extends StatefulWidget {
  const StudyReader({
    super.key,
    required this.app,
    required this.course,
    required this.lecture,
    required this.initial,
    this.initialPosition,
  });
  final AppController app;
  final StudyCourse course;
  final StudyLecture lecture;
  final StudyMaterial initial;
  final Duration? initialPosition;
  @override
  State<StudyReader> createState() => _StudyReaderState();
}

class _StudyReaderState extends State<StudyReader> with WidgetsBindingObserver {
  final _cancellation = CancellationToken();
  final _position = ValueNotifier(Duration.zero);
  final _notes = TextEditingController();
  final _question = TextEditingController();
  final _search = TextEditingController();
  final _proxy = StudyMediaProxy();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _sources = <String, String>{};
  LectureMaterials? _material;
  Player? _player;
  Player? _secondary;
  VideoController? _video;
  VideoController? _secondaryVideo;
  Timer? _saveTimer;
  late var _tab = widget.initial == StudyMaterial.video
      ? 0
      : switch (widget.initial) {
          StudyMaterial.transcript => 0,
          StudyMaterial.slides => 1,
          _ => 2,
        };
  bool _showPlayer = false;
  bool _opening = false;
  bool _playing = false;
  bool _scrubbing = false;
  bool _loadFailed = false;
  bool _asking = false;
  bool _dual = false;
  double _speed = 1;
  String _source = 'screen';
  Duration _duration = Duration.zero;
  int _slide = 0;
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.study.addListener(_materialChanged);
    unawaited(_load());
  }

  Future<void> _load() async {
    final material = await studyOperation(
      context,
      '读取课时资料',
      () => widget.app.study.materials(widget.course, widget.lecture),
    );
    if (!mounted) return;
    if (material == null) {
      setState(() => _loadFailed = true);
      return;
    }
    _notes.text = material.notes;
    _question.text = material.question;
    _position.value = material.position;
    setState(() => _material = material);
    if (widget.initial == StudyMaterial.video) {
      await _openPlayer(seek: widget.initialPosition);
    }
  }

  void _materialChanged() {
    if (mounted) setState(() {});
  }

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    if (_material == null) return;
    _material!
      ..notes = _notes.text
      ..position = _position.value;
    try {
      await widget.app.study.save(widget.course, widget.lecture);
    } catch (failure, stack) {
      // Route disposal can still be saving the last edited note.
      AppDiagnostics.instance.report('保存笔记', failure, stack);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_player?.pause());
      unawaited(_secondary?.pause());
      unawaited(_save());
    }
  }

  Future<void> _resolveSources() async {
    if (_sources.isNotEmpty) return;
    _sources.addAll(_material!.recordings);
    if (_sources.isNotEmpty ||
        !widget.course.remote ||
        widget.lecture.id.startsWith('local-')) {
      return;
    }
    final streams = await widget.app.study.repository.streams(
      widget.course.id,
      widget.lecture.id,
      studyVerify(context),
      _cancellation,
    );
    for (final entry in streams.urls.entries) {
      _sources[entry.key] = (await _proxy.open(
        entry.value,
        streams,
      )).toString();
    }
  }

  Future<void> _openPlayer({Duration? seek}) async {
    if (_opening || _material == null) return;
    final requestedPosition = seek ?? _material!.position;
    setState(() {
      _opening = true;
      _showPlayer = true;
    });
    await studyOperation(context, '播放录播', () async {
      await _resolveSources();
      _cancellation.check();
      if (_sources.isEmpty) throw StateError('这节课没有可播放的录播');
      if (_player == null) {
        MediaKit.ensureInitialized();
        _player = Player();
        _video = VideoController(_player!);
        _subscriptions.add(
          _player!.stream.position.listen((value) {
            if (!_scrubbing) _position.value = value;
            _material!.position = value;
            final now = DateTime.now();
            if (_dual &&
                _secondary != null &&
                now.difference(_lastSync).inSeconds >= 2) {
              _lastSync = now;
              if ((_secondary!.state.position - value).inMilliseconds.abs() >
                  600) {
                unawaited(_secondary!.seek(value));
              }
            }
          }),
        );
        _subscriptions.add(
          _player!.stream.duration.listen((value) {
            if (mounted) setState(() => _duration = value);
          }),
        );
        _subscriptions.add(
          _player!.stream.playing.listen((value) {
            if (_dual) {
              unawaited(value ? _secondary?.play() : _secondary?.pause());
            }
            if (mounted) setState(() => _playing = value);
          }),
        );
        _subscriptions.add(
          _player!.stream.error.listen((error) {
            if (mounted) showAppNotice(context, '录播播放失败，请重新打开。');
          }),
        );
        if (!_sources.containsKey(_source)) _source = _sources.keys.first;
        await _player!.open(Media(_sources[_source]!), play: false);
        _cancellation.check();
        await _player!.setRate(_speed);
        await _player!.seek(requestedPosition);
      } else if (seek != null) {
        await _player!.seek(seek);
        if (_dual) await _secondary?.seek(seek);
      }
      await widget.app.study.remember(widget.course, widget.lecture);
      await _player!.play();
    });
    if (mounted) setState(() => _opening = false);
  }

  Future<void> _switchSource(String source) async {
    if (_player == null) return;
    final position = _position.value;
    final playing = _playing;
    await studyOperation(context, '切换画面', () async {
      if (source == 'dual') {
        if (!_sources.containsKey('screen') ||
            !_sources.containsKey('classroom')) {
          return;
        }
        _secondary ??= Player();
        _secondaryVideo ??= VideoController(_secondary!);
        await _secondary!.setVolume(0);
        await _player!.open(Media(_sources['screen']!), play: false);
        await _secondary!.open(Media(_sources['classroom']!), play: false);
        await _player!.seek(position);
        await _secondary!.seek(position);
        await _secondary!.setRate(_speed);
        _dual = true;
      } else {
        _dual = false;
        await _secondary?.pause();
        await _player!.open(Media(_sources[source]!), play: false);
        await _player!.seek(position);
      }
      await _player!.setRate(_speed);
      if (playing) {
        await _player!.play();
        if (_dual) await _secondary!.play();
      }
      if (mounted) setState(() => _source = source);
    });
  }

  Future<void> _seek(Duration value) async {
    _position.value = value;
    await _openPlayer(seek: value);
  }

  Future<void> _export(String name, List<int> bytes) async {
    final path = await FilePicker.saveFile(
      dialogTitle: '导出资料',
      fileName: name,
      bytes: Uint8List.fromList(bytes),
    );
    if (path != null && mounted) showAppNotice(context, '已导出$name');
  }

  Future<StudyModelSettings?> _settings() async {
    var settings = await studyOperation(
      context,
      '读取模型设置',
      widget.app.study.model.readSettings,
    );
    if (settings == null && mounted) {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => StudyServices(model: widget.app.study.model),
        ),
      );
      if (saved == true) settings = await widget.app.study.model.readSettings();
    }
    return settings;
  }

  Future<void> _generate({String? question}) async {
    if (_asking || _material == null) return;
    setState(() => _asking = true);
    try {
      if (_material!.transcript.isEmpty && _material!.notes.isEmpty) {
        showAppNotice(context, '请先获取字幕或填写笔记');
        return;
      }
      final settings = await _settings();
      if (settings == null || !mounted) return;
      await _save();
      widget.app.study.generate(
        widget.course,
        widget.lecture,
        settings,
        question: question,
      );
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  Future<void> _importTranscript() async {
    await studyOperation(context, '导入字幕', () async {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt', 'txt'],
      );
      final path = result?.path;
      if (path == null) return;
      final segments = parseTranscript(await File(path).readAsString());
      if (segments.isEmpty) {
        if (mounted) showAppNotice(context, '未找到带时间戳的字幕');
        return;
      }
      _material!.transcript = segments;
      await widget.app.study.save(widget.course, widget.lecture);
    });
  }

  Future<void> _bcut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('用必剪转写音频？'),
        content: const Text('所选音频会上传到必剪，并替换这节课的本地字幕。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('选择音频'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['m4a', 'mp3', 'wav', 'aac'],
    );
    final path = result?.path;
    if (path == null || !mounted) return;
    widget.app.study.transcribe(widget.course, widget.lecture, File(path));
    showAppNotice(context, '已加入转写任务');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.app.study.removeListener(_materialChanged);
    _cancellation.cancel();
    _saveTimer?.cancel();
    // Capture controller text before disposing its editing controller.
    final material = _material;
    if (material != null) {
      material
        ..notes = _notes.text
        ..position = _position.value;
      unawaited(
        widget.app.study
            .save(widget.course, widget.lecture)
            .catchError(
              (Object failure, StackTrace stack) =>
                  AppDiagnostics.instance.report('保存课时资料', failure, stack),
            ),
      );
    }
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player?.dispose());
    unawaited(_secondary?.dispose());
    unawaited(_proxy.close());
    _notes.dispose();
    _question.dispose();
    _search.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.lecture.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        AppMenuAnchor(
          menuChildren: [
            AppMenuItemButton(
              onPressed: _material == null
                  ? null
                  : () => showStudyOrganize(
                      context,
                      widget.app,
                      widget.course,
                      lecture: widget.lecture,
                    ),
              leadingIcon: const Icon(Icons.download_outlined),
              child: const Text('保存资料'),
            ),
            AppMenuItemButton(
              onPressed: _material == null ? null : _importTranscript,
              leadingIcon: const Icon(Icons.subtitles_outlined),
              child: const Text('导入字幕'),
            ),
            AppMenuItemButton(
              onPressed: _material == null ? null : _bcut,
              leadingIcon: const Icon(Icons.mic_none_rounded),
              child: const Text('必剪转写'),
            ),
          ],
          builder: (context, menu, open) => IconButton(
            tooltip: '更多选项',
            onPressed: () => open ? menu.close() : menu.open(),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ),
      ],
    ),
    body: _material == null
        ? Center(
            child: _loadFailed
                ? StudyEmpty(
                    text: '无法读取课时资料',
                    action: TextButton(
                      onPressed: _load,
                      child: const Text('重试'),
                    ),
                  )
                : const CircularProgressIndicator(),
          )
        : SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: LayoutBuilder(
                  builder: (context, size) {
                    final wide = size.maxWidth >= 880 && _showPlayer;
                    final materials = Column(
                      children: [
                        if (!wide && !_showPlayer)
                          ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.play_circle_outline_rounded,
                            ),
                            title: Text(
                              widget.course.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Text('观看录播'),
                            onTap: () => _openPlayer(),
                          ),
                        _materialTabs(),
                        Expanded(child: _materialPanel()),
                      ],
                    );
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 6,
                            child: SingleChildScrollView(child: _playerPanel()),
                          ),
                          const SizedBox(width: 16),
                          Expanded(flex: 5, child: materials),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        if (_showPlayer)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: size.maxHeight * .46,
                            ),
                            child: SingleChildScrollView(child: _playerPanel()),
                          ),
                        Expanded(child: materials),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
  );

  Widget _playerPanel() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Column(
      children: [
        if (_video == null)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Center(
              child: _opening
                  ? const CircularProgressIndicator()
                  : TextButton.icon(
                      onPressed: () => _openPlayer(),
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('重新播放'),
                    ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, size) {
              final videos = [
                Expanded(
                  flex: 2,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Video(
                      controller: _video!,
                      controls: NoVideoControls,
                    ),
                  ),
                ),
                if (_dual && _secondaryVideo != null)
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Video(
                        controller: _secondaryVideo!,
                        controls: NoVideoControls,
                      ),
                    ),
                  ),
              ];
              return _dual && size.maxWidth >= 600
                  ? Row(children: videos)
                  : Column(
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Video(
                            controller: _video!,
                            controls: NoVideoControls,
                          ),
                        ),
                        if (_dual && _secondaryVideo != null)
                          SizedBox(
                            height: 110,
                            child: Video(
                              controller: _secondaryVideo!,
                              controls: NoVideoControls,
                            ),
                          ),
                      ],
                    );
            },
          ),
        ValueListenableBuilder(
          valueListenable: _position,
          builder: (context, position, _) => Row(
            children: [
              IconButton(
                tooltip: _playing ? '暂停' : '播放',
                onPressed: _opening ? null : () => _player?.playOrPause(),
                icon: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              Text(
                studyTimestamp(position),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Expanded(
                child: Slider(
                  value: position.inMilliseconds.toDouble().clamp(
                    0,
                    _duration.inMilliseconds.toDouble(),
                  ),
                  max: _duration.inMilliseconds.toDouble().clamp(
                    1,
                    double.infinity,
                  ),
                  onChanged: _player == null
                      ? null
                      : (value) => _position.value = Duration(
                          milliseconds: value.round(),
                        ),
                  onChangeStart: _player == null
                      ? null
                      : (_) => _scrubbing = true,
                  onChangeEnd: _player == null
                      ? null
                      : (value) {
                          _scrubbing = false;
                          _seek(Duration(milliseconds: value.round()));
                        },
                ),
              ),
              Text(
                studyTimestamp(_duration),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Row(
          children: [
            AppMenuAnchor(
              menuChildren: [
                for (final speed in [1.0, 1.25, 1.5, 2.0, 3.0, 4.0])
                  AppMenuItemButton(
                    onPressed: () async {
                      await _player?.setRate(speed);
                      await _secondary?.setRate(speed);
                      if (mounted) setState(() => _speed = speed);
                    },
                    child: Text('$speed×'),
                  ),
              ],
              builder: (context, menu, open) => TextButton(
                onPressed: () => open ? menu.close() : menu.open(),
                child: Text('$_speed×'),
              ),
            ),
            AppMenuAnchor(
              menuChildren: [
                for (final entry in _sources.entries)
                  AppMenuItemButton(
                    onPressed: () => _switchSource(entry.key),
                    child: Text(entry.key == 'screen' ? '课件画面' : '教室画面'),
                  ),
                if (_sources.length > 1)
                  AppMenuItemButton(
                    onPressed: () => _switchSource('dual'),
                    child: const Text('双画面'),
                  ),
              ],
              builder: (context, menu, open) => TextButton(
                onPressed: _sources.isEmpty
                    ? null
                    : () => open ? menu.close() : menu.open(),
                child: Text(
                  _source == 'dual'
                      ? '双画面'
                      : _source == 'screen'
                      ? '课件画面'
                      : '教室画面',
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: '收起录播',
              onPressed: () {
                _player?.pause();
                setState(() => _showPlayer = false);
              },
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _materialTabs() => Row(
    children: [
      for (final (index, label) in ['字幕', '课件', '笔记', '问答'].indexed)
        Expanded(
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: _tab == index
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onPressed: () => setState(() => _tab = index),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                const SizedBox(height: 4),
                Container(
                  height: 2,
                  color: _tab == index
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _materialPanel() => switch (_tab) {
    0 => _transcriptPanel(),
    1 => _slidesPanel(),
    2 => _notesPanel(),
    _ => _questionPanel(),
  };

  Widget _transcriptPanel() {
    final transcript = _material!.transcript;
    if (transcript.isEmpty) {
      return StudyEmpty(
        text: '还没有字幕',
        action: Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (widget.course.remote && !widget.lecture.id.startsWith('local-'))
              FilledButton(
                onPressed: () {
                  widget.app.study.fetchTranscript(
                    widget.course,
                    widget.lecture,
                    studyVerify(context),
                  );
                  showAppNotice(context, '正在获取字幕，可离开此页');
                },
                child: const Text('获取平台字幕'),
              ),
            OutlinedButton(
              onPressed: _importTranscript,
              child: const Text('导入字幕'),
            ),
          ],
        ),
      );
    }
    final query = _search.text.trim();
    final rows = transcript.where((item) => item.text.contains(query)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: '搜索字幕',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: '导出字幕',
                icon: const Icon(Icons.file_download_outlined),
                onPressed: () => studyOperation(
                  context,
                  '导出字幕',
                  () => _export(
                    '字幕.txt',
                    utf8.encode(
                      transcript
                          .map(
                            (row) =>
                                '[${studyTimestamp(row.start)}] ${row.text}',
                          )
                          .join('\n'),
                    ),
                  ),
                ),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: _position,
            builder: (context, position, _) => ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final current = position >= row.start && position < row.end;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  selected: current,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: .35),
                  leading: Text(
                    studyTimestamp(row.start),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  title: Text(
                    row.text,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  onTap: () => _seek(row.start),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _slidesPanel() {
    final slides = _material!.slides.where((slide) => !slide.hidden).toList();
    if (slides.isEmpty) {
      return StudyEmpty(
        text: '还没有课件',
        action: FilledButton(
          onPressed: () {
            widget.app.study.extractSlides(
              widget.course,
              widget.lecture,
              studyVerify(context),
            );
            showAppNotice(context, '已加入课件提取任务');
          },
          child: const Text('从课件录播提取'),
        ),
      );
    }
    _slide = _slide.clamp(0, slides.length - 1);
    final slide = slides[_slide];
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: InteractiveViewer(
              child: Center(
                child: Image.file(File(slide.file), fit: BoxFit.contain),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.center,
            children: [
              IconButton(
                tooltip: '上一页',
                onPressed: _slide > 0 ? () => setState(() => _slide--) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text('${_slide + 1} / ${slides.length}'),
              IconButton(
                tooltip: '下一页',
                onPressed: _slide + 1 < slides.length
                    ? () => setState(() => _slide++)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              TextButton(
                onPressed: () => _seek(slide.position),
                child: Text('${studyTimestamp(slide.position)} 看讲解'),
              ),
              IconButton(
                tooltip: '移除此页',
                icon: const Icon(Icons.hide_image_outlined),
                onPressed: () async {
                  slide.hidden = true;
                  await widget.app.study.save(widget.course, widget.lecture);
                  if (mounted) {
                    showAppNotice(
                      context,
                      '已移除课件页',
                      action: (
                        label: '撤销',
                        onPressed: () {
                          slide.hidden = false;
                          unawaited(
                            widget.app.study.save(
                              widget.course,
                              widget.lecture,
                            ),
                          );
                        },
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 12,
          alignment: WrapAlignment.center,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('导出 PDF'),
              onPressed: () => studyOperation(context, '导出课件', () async {
                final bytes = await studySlidesPdf(
                  slides.map((item) => item.file).toList(),
                );
                if (mounted) await _export('课件.pdf', bytes);
              }),
            ),
            if (_material!.slides.any((slide) => slide.hidden))
              TextButton(
                onPressed: () async {
                  for (final item in _material!.slides) {
                    item.hidden = false;
                  }
                  await widget.app.study.save(widget.course, widget.lecture);
                },
                child: const Text('恢复移除的页面'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _notesPanel() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
    children: [
      TextField(
        controller: _notes,
        minLines: 6,
        maxLines: null,
        decoration: const InputDecoration(
          labelText: '随堂笔记',
          alignLabelWithHint: true,
        ),
        onChanged: (_) => _saveSoon(),
      ),
      Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: () {
              final insert = '[${studyTimestamp(_position.value)}] ';
              final selected = _notes.selection;
              final start = selected.isValid
                  ? selected.start
                  : _notes.text.length;
              final end = selected.isValid ? selected.end : start;
              _notes.value = TextEditingValue(
                text: _notes.text.replaceRange(start, end, insert),
                selection: TextSelection.collapsed(
                  offset: start + insert.length,
                ),
              );
              _saveSoon();
            },
            icon: const Icon(Icons.more_time_rounded, size: 18),
            label: const Text('插入时间'),
          ),
          TextButton.icon(
            onPressed: () => studyOperation(
              context,
              '导出笔记',
              () => _export(
                '笔记.md',
                utf8.encode('${_notes.text}\n\n${_material!.summary}'),
              ),
            ),
            icon: const Icon(Icons.file_download_outlined, size: 18),
            label: const Text('导出笔记'),
          ),
        ],
      ),
      const Divider(height: 24),
      ListenableBuilder(
        listenable: widget.app.study.tasks,
        builder: (context, _) {
          final task = widget.app.study.generation(
            widget.course,
            widget.lecture,
            'summary',
          );
          return _generated(
            task,
            task?.output.isNotEmpty == true ? task!.output : _material!.summary,
            label: '整理笔记',
            onGenerate: _asking ? null : () => _generate(),
          );
        },
      ),
    ],
  );

  Widget _questionPanel() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
    children: [
      TextField(
        controller: _question,
        minLines: 2,
        maxLines: 6,
        decoration: const InputDecoration(
          labelText: '询问这节课的内容',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 8),
      ListenableBuilder(
        listenable: widget.app.study.tasks,
        builder: (context, _) {
          final task = widget.app.study.generation(
            widget.course,
            widget.lecture,
            'answer',
          );
          return _generated(
            task,
            task?.output.isNotEmpty == true ? task!.output : _material!.answer,
            label: '提问',
            onGenerate: _asking
                ? null
                : () {
                    if (_question.text.trim().isNotEmpty) {
                      _generate(question: _question.text.trim());
                    }
                  },
          );
        },
      ),
    ],
  );

  Widget _generated(
    StudyTask? task,
    String text, {
    required String label,
    VoidCallback? onGenerate,
  }) {
    final active =
        task != null &&
        [StudyTaskStatus.running, StudyTaskStatus.queued].contains(task.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: active
              ? TextButton.icon(
                  onPressed: () => widget.app.study.tasks.cancel(task),
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('停止生成'),
                )
              : FilledButton.tonal(onPressed: onGenerate, child: Text(label)),
        ),
        if (active && text.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (text.isNotEmpty) ...[
          const SizedBox(height: 12),
          StudyMarkdown(text: text, onSeek: _seek),
        ],
        if (task?.status == StudyTaskStatus.failed)
          const Text('生成中断，已保留收到的内容。'),
      ],
    );
  }
}
