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
import 'study_layout.dart';
import 'study_live_player.dart';
import 'study_organize.dart';
import 'study_services.dart';
import 'study_video.dart';

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

class _StudyReaderState extends State<StudyReader>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _cancellation = CancellationToken();
  final _position = ValueNotifier(Duration.zero);
  final _notes = TextEditingController();
  final _question = TextEditingController();
  final _search = TextEditingController();
  final _noteDraft = TextEditingController();
  final _proxy = StudyMediaProxy();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _sources = <String, String>{};
  LectureMaterials? _material;
  Player? _player;
  Player? _secondary;
  VideoController? _video;
  VideoController? _secondaryVideo;
  Timer? _saveTimer;
  late bool _livePlayback =
      widget.lecture.status != StudyLectureStatus.recorded;
  late final _tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: widget.initial == StudyMaterial.video
        ? (widget.lecture.status == StudyLectureStatus.live ? 2 : 0)
        : switch (widget.initial) {
            StudyMaterial.transcript => 1,
            StudyMaterial.slides => 0,
            StudyMaterial.question => 3,
            _ => 2,
          },
  );
  bool _showPlayer = false;
  bool _opening = false;
  bool _playbackFailed = false;
  bool _loadFailed = false;
  bool _asking = false;
  bool _searchingTranscript = false;
  bool _editingNotes = false;
  bool _dual = false;
  String _source = 'screen';
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs.addListener(_materialChanged);
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
    if (streams.duration > Duration.zero) {
      _material!.duration = streams.duration;
    }
    _livePlayback = streams.status == StudyLectureStatus.live;
    for (final entry in streams.urls.entries) {
      _sources[entry.key] = (await _proxy.open(
        entry.value,
        streams,
      )).toString();
    }
  }

  Future<void> _openPlayer({Duration? seek}) async {
    if (_opening || _material == null) return;
    if (_livePlayback) {
      setState(() => _showPlayer = true);
      return;
    }
    final requestedPosition = seek ?? _material!.position;
    setState(() {
      _opening = true;
      _showPlayer = true;
      _playbackFailed = false;
    });
    await studyOperation(context, '播放录播', () async {
      await _resolveSources();
      _cancellation.check();
      if (_livePlayback) return;
      if (_sources.isEmpty) throw StateError('这节课没有可播放的录播');
      if (!_sources.containsKey(_source)) _source = _sources.keys.first;
      if (_player == null) {
        MediaKit.ensureInitialized();
        _player = Player();
        _video = VideoController(_player!);
        _subscriptions.add(
          _player!.stream.duration.listen((value) {
            if (value > Duration.zero) _material!.duration = value;
          }),
        );
        _subscriptions.add(
          _player!.stream.position.listen((value) {
            _position.value = value;
            _material!.position = value;
            final now = DateTime.now();
            if (_dual &&
                !_opening &&
                _secondary != null &&
                now.difference(_lastSync).inMilliseconds >= 500) {
              _lastSync = now;
              if ((_secondary!.state.position - value).inMilliseconds.abs() >
                  600) {
                unawaited(_secondary!.seek(value));
              }
            }
          }),
        );
        _subscriptions.add(
          _player!.stream.playing.listen((value) {
            if (_dual && !_opening) {
              unawaited(value ? _secondary?.play() : _secondary?.pause());
            }
          }),
        );
        _subscriptions.add(
          _player!.stream.error.listen((error) {
            if (!mounted || _playbackFailed) return;
            AppDiagnostics.instance.error(
              '播放录播',
              StateError(error.replaceAll(RegExp(r'https?://\S+'), '[媒体地址]')),
              StackTrace.current,
            );
            setState(() => _playbackFailed = true);
          }),
        );
        _subscriptions.add(
          _player!.stream.rate.listen((rate) {
            if (_dual) unawaited(_secondary?.setRate(rate));
          }),
        );
        await _openRecordedMedia(_source, requestedPosition);
        _cancellation.check();
      } else if (seek != null) {
        await _player!.seek(seek);
        if (_dual) await _secondary?.seek(seek);
      } else {
        await _openRecordedMedia(_source, requestedPosition);
      }
      await widget.app.study.remember(widget.course, widget.lecture);
      await _player!.play();
      if (_dual) await _secondary?.play();
    });
    if (mounted) setState(() => _opening = false);
  }

  Future<void> _openRecordedMedia(String source, Duration position) async {
    await _player!.open(Media(_sources[source]!, start: position), play: false);
    if (source == 'screen' && _sources.containsKey('classroom')) {
      await _player!.setAudioTrack(AudioTrack.uri(_sources['classroom']!));
    }
  }

  Future<void> _switchSource(String source, bool dual) async {
    if (_opening || _player == null) return;
    final position = _position.value;
    final playing = _player!.state.playing;
    final rate = _player!.state.rate;
    setState(() {
      _opening = true;
      _playbackFailed = false;
    });
    await studyOperation(context, '切换画面', () async {
      await _secondary?.pause();
      if (source != _source) await _openRecordedMedia(source, position);
      if (dual) {
        _secondary ??= Player();
        _secondaryVideo ??= VideoController(_secondary!);
        await _secondary!.setVolume(0);
        await _secondary!.open(
          Media(
            _sources[source == 'screen' ? 'classroom' : 'screen']!,
            start: position,
          ),
          play: false,
        );
        await _secondary!.setRate(rate);
      }
      _cancellation.check();
      await _player!.setRate(rate);
      _source = source;
      _dual = dual;
      if (playing) {
        await _player!.play();
        if (_dual) await _secondary!.play();
      }
    });
    if (mounted) setState(() => _opening = false);
  }

  Future<void> _reconnect() async {
    if (_opening) return;
    await _player?.pause();
    await _secondary?.pause();
    if (!mounted) return;
    _sources.clear();
    setState(() => _dual = false);
    await _openPlayer();
  }

  Future<void> _seek(Duration value) async {
    if (_livePlayback) return;
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
    var settings = await widget.app.study.model.readSettings();
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
      await studyOperation(context, '准备学习资料', () async {
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
      });
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
    _noteDraft.dispose();
    _tabs.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.course.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(22),
        child: Padding(
          padding: const EdgeInsets.only(left: 56, right: 20, bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${lectureDate(widget.lecture)} · ${studyLectureTitle(widget.lecture)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
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
                constraints: BoxConstraints(maxWidth: _showPlayer ? 1440 : 840),
                child: StudyContent(
                  maxWidth: 1440,
                  child: LayoutBuilder(
                    builder: (context, size) {
                      final wide =
                          _showPlayer &&
                          (size.maxWidth >= 900 ||
                              size.maxWidth >= 720 &&
                                  size.maxWidth > size.maxHeight * 1.35);
                      final materials = Column(
                        children: [
                          if (!wide && !_showPlayer)
                            ListTile(
                              dense: true,
                              leading: const Icon(
                                Icons.play_circle_outline_rounded,
                              ),
                              title: Text(
                                studyLectureTitle(widget.lecture),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(_livePlayback ? '观看直播' : '观看录播'),
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
                              child: SingleChildScrollView(
                                child: _playerWithActions(),
                              ),
                            ),
                            const SizedBox(width: 24),
                            SizedBox(
                              width: 290,
                              child: StudyAside(child: materials),
                            ),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          if (_showPlayer)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: size.maxHeight * .65,
                              ),
                              child: SingleChildScrollView(
                                child: _playerWithActions(),
                              ),
                            ),
                          Expanded(
                            child: _showPlayer
                                ? StudyAside(below: true, child: materials)
                                : materials,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
  );

  Widget _playerWithActions() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _playerPanel(),
      LayoutBuilder(
        builder: (context, size) {
          final actions = <Widget>[
            TextButton.icon(
              onPressed: _outline,
              icon: const Icon(Icons.video_library_outlined, size: 18),
              label: const Text('课时目录'),
            ),
            if (!_livePlayback) ...[
              TextButton.icon(
                onPressed: _adjacent(-1) == null
                    ? null
                    : () => _openLesson(_adjacent(-1)!),
                icon: const Icon(Icons.chevron_left_rounded, size: 17),
                label: const Text('上一节'),
              ),
              TextButton(
                onPressed: _adjacent(1) == null
                    ? null
                    : () => _openLesson(_adjacent(1)!),
                child: const Text('下一节 ›'),
              ),
            ],
            if (!_livePlayback)
              TextButton.icon(
                onPressed: () => showStudyOrganize(
                  context,
                  widget.app,
                  widget.course,
                  lecture: widget.lecture,
                ),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('保存资料'),
              ),
          ];
          return size.maxWidth < 650 ||
                  MediaQuery.textScalerOf(context).scale(14) > 19
              ? Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                )
              : Row(
                  children: [actions.first, const Spacer(), ...actions.skip(1)],
                );
        },
      ),
    ],
  );

  Future<void> _capture() async {
    await studyOperation(context, '保存课堂截图', () async {
      await _save();
      final bytes = await _player!.screenshot();
      if (bytes == null) throw StateError('暂时无法截取画面');
      await widget.app.study.addScreenshot(
        widget.course,
        widget.lecture,
        _position.value,
        bytes,
      );
      if (!mounted) return;
      _notes.text = _material!.notes;
      _tabs.animateTo(2);
    });
  }

  Future<void> _outline() async {
    final lectures = widget.course.lectures;
    final lecture = await showDialog<StudyLecture>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('课时目录'),
        children: [
          for (final item in lectures)
            ListTile(
              selected: item.id == widget.lecture.id,
              title: Text(item.title),
              subtitle: Text('${lectureDate(item)} · ${item.status.label}'),
              trailing: item.id == widget.lecture.id
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(context, item),
            ),
        ],
      ),
    );
    if (lecture == null || lecture.id == widget.lecture.id || !mounted) return;
    await _openLesson(lecture);
  }

  StudyLecture? _adjacent(int delta) {
    final lectures =
        widget.course.lectures
            .where((lecture) => lecture.status.canPlay)
            .toList()
          ..sort(
            (a, b) => (a.startsAt ?? DateTime(0)).compareTo(
              b.startsAt ?? DateTime(0),
            ),
          );
    final index = lectures.indexWhere(
      (lecture) => lecture.id == widget.lecture.id,
    );
    final next = index + delta;
    return index >= 0 && next >= 0 && next < lectures.length
        ? lectures[next]
        : null;
  }

  Future<void> _openLesson(StudyLecture lecture) async {
    await _save();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(
        builder: (_) => StudyReader(
          app: widget.app,
          course: widget.course,
          lecture: lecture,
          initial: lecture.status.canPlay
              ? StudyMaterial.video
              : StudyMaterial.notes,
        ),
      ),
    );
  }

  Widget _playerPanel() {
    if (_livePlayback) {
      return StudyLivePlayer(
        initialStatus: widget.lecture.status,
        load: (cancel) => widget.app.study.repository.streams(
          widget.course.id,
          widget.lecture.id,
          studyVerify(context),
          cancel,
        ),
        onRecording: () {
          setState(() => _livePlayback = false);
          _sources.clear();
          unawaited(_openPlayer());
        },
        onCollapse: () => setState(() => _showPlayer = false),
        viewActions: _viewActions(),
      );
    }
    return _recordedPlayerPanel();
  }

  Widget _recordedPlayerPanel() => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: _video == null
        ? AspectRatio(
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
        : StudyVideo(
            controller: _video!,
            secondary: _dual ? _secondaryVideo : null,
            failed: _playbackFailed,
            onRetry: _opening ? null : _reconnect,
            sources: _sources.keys.toSet(),
            source: _source,
            busy: _opening,
            onView: _switchSource,
            viewActions: _viewActions(),
            onCollapse: () {
              unawaited(_player?.pause());
              unawaited(_secondary?.pause());
              setState(() => _showPlayer = false);
            },
          ),
  );

  Widget _viewActions() => Wrap(
    spacing: 12,
    children: [
      if (_player != null)
        TextButton.icon(
          onPressed: _capture,
          icon: const Icon(Icons.photo_camera_outlined, size: 17),
          label: const Text('截图'),
        ),
      TextButton.icon(
        onPressed: () => _tabs.animateTo(2),
        icon: const Icon(Icons.edit_note_rounded, size: 17),
        label: const Text('记笔记'),
      ),
    ],
  );

  Widget _materialTabs() => TabBar(
    controller: _tabs,
    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    tabs: const [
      Tab(text: '课件'),
      Tab(text: '字幕'),
      Tab(text: '笔记'),
      Tab(text: '问答'),
    ],
  );

  Widget _materialPanel() => switch (_tabs.index) {
    0 => _slidesPanel(),
    1 => _transcriptPanel(),
    2 => _notesPanel(),
    _ => _questionPanel(),
  };

  Widget _transcriptPanel() {
    final transcript = _material!.transcript;
    if (transcript.isEmpty) {
      return StudyEmpty(
        text: _livePlayback ? '直播结束后可获取平台字幕' : '还没有字幕',
        action: Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (!_livePlayback &&
                widget.course.remote &&
                !widget.lecture.id.startsWith('local-'))
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
            TextButton(onPressed: _bcut, child: const Text('必剪转写')),
          ],
        ),
      );
    }
    final query = _searchingTranscript ? _search.text.trim() : '';
    final rows = transcript.where((item) => item.text.contains(query)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: _searchingTranscript
              ? TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    labelText: '搜索字幕',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      tooltip: '收起搜索',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () =>
                          setState(() => _searchingTranscript = false),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        '课堂字幕',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '搜索字幕',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          setState(() => _searchingTranscript = true),
                      icon: const Icon(Icons.search_rounded, size: 18),
                    ),
                    AppMenuAnchor(
                      menuChildren: [
                        AppMenuItemButton(
                          onPressed: _importTranscript,
                          child: const Text('导入字幕'),
                        ),
                        AppMenuItemButton(
                          onPressed: _bcut,
                          child: const Text('必剪转写'),
                        ),
                      ],
                      builder: (context, menu, open) => IconButton(
                        tooltip: '字幕选项',
                        onPressed: () => open ? menu.close() : menu.open(),
                        icon: const Icon(Icons.more_horiz_rounded, size: 18),
                      ),
                    ),
                    IconButton(
                      tooltip: '导出字幕',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.file_download_outlined, size: 18),
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
                  ],
                ),
        ),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: _position,
            builder: (context, position, _) => ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final current = position >= row.start && position < row.end;
                final theme = Theme.of(context);
                return Semantics(
                  selected: current,
                  child: Material(
                    color: current
                        ? theme.colorScheme.primaryContainer.withValues(
                            alpha: .35,
                          )
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    child: InkWell(
                      onTap: _livePlayback ? null : () => _seek(row.start),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 6,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: MediaQuery.textScalerOf(context).scale(42),
                              child: Text(
                                studyTimestamp(row.start),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  height: 1.45,
                                  color: current
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                row.text.replaceAll(RegExp(r'\s*\n\s*'), ' '),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
        text: _livePlayback ? '直播结束后可提取课件' : '还没有课件',
        action: _livePlayback
            ? null
            : TextButton(
                onPressed: () => showStudyOrganize(
                  context,
                  widget.app,
                  widget.course,
                  lecture: widget.lecture,
                ),
                child: const Text('从课件录播提取'),
              ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '本节课件 · ${slides.length} 页',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: '导出 PDF',
                icon: const Icon(Icons.file_download_outlined, size: 18),
                onPressed: () => studyOperation(context, '导出课件', () async {
                  final bytes = await studySlidesPdf(
                    slides.map((slide) => slide.file).toList(),
                  );
                  if (mounted) await _export('课件.pdf', bytes);
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, size) => GridView.builder(
              padding: const EdgeInsets.only(bottom: 12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: size.maxWidth < 420
                    ? 2
                    : (size.maxWidth / 180).floor().clamp(2, 5),
                mainAxisSpacing: 14,
                crossAxisSpacing: 12,
                childAspectRatio:
                    MediaQuery.textScalerOf(context).scale(12) > 16 ? .8 : 1.05,
              ),
              itemCount: slides.length,
              itemBuilder: (context, index) {
                final slide = slides[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Material(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _seek(slide.position),
                          child: Image.file(
                            File(slide.file),
                            cacheWidth: 500,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${(index + 1).toString().padLeft(2, '0')} · ${studyTimestamp(slide.position)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontSize: 11),
                          ),
                        ),
                        IconButton(
                          tooltip: '预览第${index + 1}页',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.open_in_full_rounded,
                            size: 15,
                          ),
                          onPressed: () => _previewSlide(slide, index + 1),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        if (_material!.slides.any((slide) => slide.hidden))
          TextButton(
            onPressed: () async {
              for (final slide in _material!.slides) {
                slide.hidden = false;
              }
              await widget.app.study.save(widget.course, widget.lecture);
            },
            child: const Text('恢复移除的页面'),
          ),
      ],
    );
  }

  Future<void> _previewSlide(StudySlide slide, int number) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('第 $number 页'),
      content: SizedBox(
        width: 700,
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: InteractiveViewer(
            child: Image.file(File(slide.file), fit: BoxFit.contain),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => studyOperation(context, '移除课件页', () async {
            slide.hidden = true;
            await widget.app.study.save(widget.course, widget.lecture);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            if (mounted) {
              showAppNotice(
                context,
                '已移除课件页',
                action: (
                  label: '撤销',
                  onPressed: () {
                    slide.hidden = false;
                    unawaited(
                      widget.app.study.save(widget.course, widget.lecture),
                    );
                  },
                ),
              );
            }
          }),
          child: const Text('移除此页'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            _seek(slide.position);
          },
          child: const Text('看讲解'),
        ),
      ],
    ),
  );

  Widget _notesPanel() => ListView(
    padding: const EdgeInsets.symmetric(vertical: 14),
    children: [
      Row(
        children: [
          Expanded(
            child: Text('本节笔记', style: Theme.of(context).textTheme.titleSmall),
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
            icon: const Icon(Icons.file_download_outlined, size: 17),
            label: const Text('导出'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (_editingNotes)
        TextField(
          controller: _notes,
          minLines: 6,
          maxLines: null,
          decoration: const InputDecoration(
            labelText: '随堂笔记',
            alignLabelWithHint: true,
          ),
          onChanged: (_) => _saveSoon(),
        )
      else if (_notes.text.isNotEmpty)
        StudyNotes(text: _notes.text, onSeek: _seek)
      else
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('本节还没有笔记'),
        ),
      if (_notes.text.isNotEmpty || _editingNotes)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _editingNotes = !_editingNotes),
            icon: Icon(
              _editingNotes ? Icons.check_rounded : Icons.edit_outlined,
              size: 16,
            ),
            label: Text(_editingNotes ? '完成编辑' : '编辑全文'),
          ),
        ),
      const Divider(height: 28),
      ValueListenableBuilder(
        valueListenable: _position,
        builder: (context, position, _) => Text(
          '${studyTimestamp(position)} 的笔记',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _noteDraft,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(
          labelText: '新笔记',
          hintText: '记下理解、疑问或例题思路',
        ),
      ),
      const SizedBox(height: 8),
      ValueListenableBuilder(
        valueListenable: _noteDraft,
        builder: (context, value, _) => FilledButton.icon(
          onPressed: value.text.trim().isEmpty ? null : _addNote,
          icon: const Icon(Icons.add_rounded, size: 17),
          label: const Text('添加笔记'),
        ),
      ),
      const Divider(height: 28),
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

  Future<void> _addNote() async {
    final text = _noteDraft.text.trim();
    if (text.isEmpty) return;
    final previous = _notes.text.trimRight();
    _notes.text =
        '${previous.isEmpty ? '' : '$previous\n\n'}[${studyTimestamp(_position.value)}] $text';
    _noteDraft.clear();
    setState(() {});
    await _save();
  }

  Widget _questionPanel() => ListView(
    padding: const EdgeInsets.symmetric(vertical: 14),
    children: [
      TextField(
        controller: _question,
        minLines: 2,
        maxLines: 6,
        decoration: const InputDecoration(
          labelText: '问本节课',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<bool>(
              builder: (_) => StudyServices(model: widget.app.study.model),
            ),
          ),
          child: const Text('学习服务'),
        ),
      ),
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
