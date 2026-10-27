import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/async/cancelable_request.dart';
import '../../school/errors.dart';
import '../../ui/app_menu_anchor.dart';
import '../../ui/app_notice.dart';
import '../media.dart';
import '../model.dart';
import '../playback.dart';
import 'study_common.dart';

class StudyLivePlayer extends StatefulWidget {
  const StudyLivePlayer({
    super.key,
    required this.load,
    this.initialStatus = StudyLectureStatus.live,
    this.onRecording,
    this.onCollapse,
    this.endedAction,
  });

  final Future<LectureStreams> Function(CancellationToken) load;
  final StudyLectureStatus initialStatus;
  final VoidCallback? onRecording;
  final VoidCallback? onCollapse;
  final Widget? endedAction;

  @override
  State<StudyLivePlayer> createState() => _StudyLivePlayerState();
}

class _StudyLivePlayerState extends State<StudyLivePlayer>
    with WidgetsBindingObserver {
  final _cancellation = CancellationToken();
  final _proxy = StudyMediaProxy();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _sources = <String, String>{};
  Player? _player;
  Player? _secondary;
  VideoController? _video;
  VideoController? _secondaryVideo;
  late StudyLectureStatus _status = widget.initialStatus;
  String _source = 'classroom';
  bool _opening = false;
  bool _playing = false;
  bool get _dual => _source == 'dual';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_open()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_player?.pause());
      unawaited(_secondary?.pause());
    }
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    await studyOperation(context, '播放直播', () async {
      await _player?.pause();
      await _secondary?.pause();
      final streams = await widget.load(_cancellation);
      _cancellation.check();
      _status = streams.status;
      if (_status == StudyLectureStatus.recorded &&
          widget.onRecording != null) {
        widget.onRecording!();
        return;
      }
      if (_status != StudyLectureStatus.live) return;
      _sources.clear();
      for (final entry in streams.urls.entries) {
        _sources[entry.key] = '${await _proxy.open(entry.value, streams)}';
      }
      if (_sources.isEmpty) {
        throw const SchoolRequestError('直播暂时没有可用画面，请稍后重新连接');
      }
      if (_player == null) {
        MediaKit.ensureInitialized();
        _player = Player();
        _video = VideoController(_player!);
        _subscriptions.add(
          _player!.stream.playing.listen((playing) {
            if (_dual) {
              unawaited(playing ? _secondary?.play() : _secondary?.pause());
            }
            if (mounted) setState(() => _playing = playing);
          }),
        );
        _subscriptions.add(
          _player!.stream.error.listen((error) {
            if (mounted) showAppNotice(context, '直播连接中断，可尝试重新连接。');
          }),
        );
      }
      _source = _sources.containsKey('classroom')
          ? 'classroom'
          : _sources.keys.first;
      if (mounted) setState(() {});
      await _openMedia(_source);
      _cancellation.check();
      await _player!.play();
    });
    if (mounted) setState(() => _opening = false);
  }

  Future<void> _openMedia(String source) async {
    await _player!.open(Media(_sources[source]!), play: false);
    if (source == 'screen' && _sources.containsKey('classroom')) {
      await _player!.setAudioTrack(AudioTrack.uri(_sources['classroom']!));
    }
  }

  Future<void> _switchSource(String source) async {
    if (_opening || _player == null) return;
    setState(() => _opening = true);
    final playing = _playing;
    await studyOperation(context, '切换直播画面', () async {
      await _secondary?.pause();
      if (source == 'dual') {
        _secondary ??= Player();
        _secondaryVideo ??= VideoController(_secondary!);
        await _secondary!.setVolume(0);
        await _openMedia('screen');
        await _secondary!.open(Media(_sources['classroom']!), play: false);
      } else {
        await _openMedia(source);
      }
      _cancellation.check();
      if (mounted) setState(() => _source = source);
      if (playing) {
        await _player!.play();
        if (_dual) await _secondary!.play();
      }
    });
    if (mounted) setState(() => _opening = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancellation.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player?.dispose());
    unawaited(_secondary?.dispose());
    unawaited(_proxy.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_status != StudyLectureStatus.live || _video == null)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 180),
            child: Center(
              child: _opening
                  ? const CircularProgressIndicator()
                  : StudyEmpty(
                      text: switch (_status) {
                        StudyLectureStatus.live => '尚未连接直播',
                        StudyLectureStatus.ended => '直播已结束',
                        _ => _status.label,
                      },
                      action: Wrap(
                        spacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          TextButton(
                            onPressed: _open,
                            child: Text(
                              _status == StudyLectureStatus.live
                                  ? '重新连接'
                                  : '刷新状态',
                            ),
                          ),
                          if (_status == StudyLectureStatus.ended &&
                              widget.endedAction != null)
                            widget.endedAction!,
                        ],
                      ),
                    ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, size) {
              Widget video(VideoController controller) => AspectRatio(
                aspectRatio: 16 / 9,
                child: Video(controller: controller, controls: NoVideoControls),
              );
              if (_dual && size.maxWidth >= 600) {
                return Row(
                  children: [
                    Expanded(flex: 2, child: video(_video!)),
                    const SizedBox(width: 8),
                    Expanded(child: video(_secondaryVideo!)),
                  ],
                );
              }
              return Column(
                children: [
                  video(_video!),
                  if (_dual)
                    SizedBox(height: 110, child: video(_secondaryVideo!)),
                ],
              );
            },
          ),
        if (_status == StudyLectureStatus.live)
          Row(
            children: [
              IconButton(
                tooltip: _playing ? '暂停' : '播放',
                onPressed: _opening || _player == null
                    ? null
                    : () => _player!.playOrPause(),
                icon: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              Expanded(
                child: Text(
                  '直播中',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
              TextButton.icon(
                onPressed: _opening ? null : _open,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重新连接'),
              ),
            ],
          ),
        Row(
          children: [
            if (_status == StudyLectureStatus.live && _sources.isNotEmpty)
              AppMenuAnchor(
                menuChildren: [
                  for (final key in _sources.keys)
                    AppMenuItemButton(
                      onPressed: _opening ? null : () => _switchSource(key),
                      child: Text(key == 'screen' ? '课件画面' : '教室画面'),
                    ),
                  if (_sources.containsKey('screen') &&
                      _sources.containsKey('classroom'))
                    AppMenuItemButton(
                      onPressed: _opening ? null : () => _switchSource('dual'),
                      child: const Text('双画面'),
                    ),
                ],
                builder: (context, menu, open) => TextButton(
                  onPressed: _opening
                      ? null
                      : () => open ? menu.close() : menu.open(),
                  child: Text(
                    _dual
                        ? '双画面'
                        : _source == 'screen'
                        ? '课件画面'
                        : '教室画面',
                  ),
                ),
              ),
            const Spacer(),
            if (widget.onCollapse != null)
              IconButton(
                tooltip: '收起直播',
                onPressed: widget.onCollapse,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
          ],
        ),
      ],
    ),
  );
}
