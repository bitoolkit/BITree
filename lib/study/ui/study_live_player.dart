import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/async/cancelable_request.dart';
import '../../core/diagnostics.dart';
import '../../school/errors.dart';
import '../media.dart';
import '../model.dart';
import '../playback.dart';
import 'study_common.dart';
import 'study_video.dart';

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
  String _source = 'screen';
  bool _opening = false;
  bool _dual = false;
  bool _failed = false;

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
    setState(() {
      _opening = true;
      _failed = false;
      _dual = false;
    });
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
            if (_dual && !_opening) {
              unawaited(playing ? _secondary?.play() : _secondary?.pause());
            }
          }),
        );
        _subscriptions.add(
          _player!.stream.error.listen((error) {
            if (!mounted || _failed) return;
            AppDiagnostics.instance.error(
              '播放直播',
              StateError(error.replaceAll(RegExp(r'https?://\S+'), '[媒体地址]')),
              StackTrace.current,
            );
            setState(() => _failed = true);
          }),
        );
      }
      _source = _sources.containsKey('screen') ? 'screen' : _sources.keys.first;
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

  Future<void> _switchSource(String source, bool dual) async {
    if (_opening || _player == null) return;
    setState(() {
      _opening = true;
      _failed = false;
    });
    final playing = _player!.state.playing;
    await studyOperation(context, '切换直播画面', () async {
      await _secondary?.pause();
      if (source != _source) await _openMedia(source);
      if (dual) {
        _secondary ??= Player();
        _secondaryVideo ??= VideoController(_secondary!);
        await _secondary!.setVolume(0);
        await _secondary!.open(
          Media(_sources[source == 'screen' ? 'classroom' : 'screen']!),
          play: false,
        );
      }
      _cancellation.check();
      _source = source;
      _dual = dual;
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
          StudyVideo(
            controller: _video!,
            secondary: _dual ? _secondaryVideo : null,
            live: true,
            failed: _failed,
            onRetry: _opening ? null : _open,
            sources: _sources.keys.toSet(),
            source: _source,
            busy: _opening,
            onView: _switchSource,
            onCollapse: widget.onCollapse,
          ),
      ],
    ),
  );
}
