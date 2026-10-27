import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../ui/design.dart';

/// Keeps the same controls and picture-in-picture layout in the page and fullscreen.
class StudyVideo extends StatefulWidget {
  const StudyVideo({
    super.key,
    required this.controller,
    required this.sources,
    required this.source,
    required this.onView,
    this.secondary,
    this.live = false,
    this.failed = false,
    this.onRetry,
    this.busy = false,
    this.onCollapse,
  });

  final VideoController controller;
  final Set<String> sources;
  final String source;
  final void Function(String source, bool dual) onView;
  final VideoController? secondary;
  final bool live;
  final bool failed;
  final VoidCallback? onRetry;
  final bool busy;
  final VoidCallback? onCollapse;

  @override
  State<StudyVideo> createState() => _StudyVideoState();
}

class _StudyVideoState extends State<StudyVideo> {
  bool _fullscreen = false;

  @override
  Widget build(BuildContext context) {
    final StudyVideo(
      :controller,
      :sources,
      :source,
      :onView,
      :secondary,
      :live,
      :failed,
      :onRetry,
      :busy,
      :onCollapse,
    ) = widget;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Video(
            controller: controller,
            onEnterFullscreen: () async {
              setState(() => _fullscreen = true);
              await defaultEnterNativeFullscreen();
            },
            onExitFullscreen: () async {
              await defaultExitNativeFullscreen();
              if (mounted) setState(() => _fullscreen = false);
            },
            controls: (state) {
              final color = Theme.of(state.context).colorScheme.primary;
              final actions = <Widget>[
                if (live)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('直播中', style: TextStyle(color: Colors.white)),
                  ),
                const Spacer(),
                _PlaybackActions(
                  player: controller.player,
                  sources: sources,
                  source: source,
                  dual: secondary != null,
                  busy: busy,
                  live: live,
                  showViews: _fullscreen,
                  onView: onView,
                  onReconnect: onRetry,
                  onCollapse: onCollapse == null
                      ? null
                      : () async {
                          if (isFullscreen(state.context)) {
                            await state.exitFullscreen();
                            await WidgetsBinding.instance.endOfFrame;
                          }
                          if (mounted) onCollapse();
                        },
                ),
              ];
              final desktop = MaterialDesktopVideoControlsThemeData(
                displaySeekBar: !live,
                visibleOnMount: true,
                seekBarPositionColor: color,
                seekBarThumbColor: color,
                topButtonBar: actions,
                bottomButtonBar: [
                  const MaterialDesktopPlayOrPauseButton(),
                  const MaterialDesktopVolumeButton(),
                  if (!live)
                    const Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: MaterialDesktopPositionIndicator(),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const MaterialDesktopFullscreenButton(),
                ],
              );
              MaterialVideoControlsThemeData mobile(bool fullscreen) =>
                  (fullscreen
                          ? kDefaultMaterialVideoControlsThemeDataFullscreen
                          : kDefaultMaterialVideoControlsThemeData)
                      .copyWith(
                        displaySeekBar: !live,
                        visibleOnMount: true,
                        seekOnDoubleTap: !live,
                        seekGesture: fullscreen && !live,
                        primaryButtonBar: const [
                          Spacer(),
                          MaterialPlayOrPauseButton(iconSize: 48),
                          Spacer(),
                        ],
                        topButtonBar: actions,
                        seekBarPositionColor: color,
                        seekBarThumbColor: color,
                        bottomButtonBar: [
                          if (!live)
                            const Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: MaterialPositionIndicator(),
                                ),
                              ),
                            )
                          else
                            const Spacer(),
                          const MaterialFullscreenButton(),
                        ],
                      );
              return MaterialVideoControlsTheme(
                normal: mobile(false),
                fullscreen: mobile(true),
                child: MaterialDesktopVideoControlsTheme(
                  normal: desktop,
                  fullscreen: desktop,
                  child: LayoutBuilder(
                    builder: (context, size) => Stack(
                      fit: StackFit.expand,
                      children: [
                        // 2.0.1's controls themes do not notify when their data changes.
                        // Remount the SDK controls when the selected view changes.
                        ExcludeFocus(
                          // Rebuilding the page's controls must not take keyboard
                          // focus away from the fullscreen route.
                          excluding: _fullscreen && !isFullscreen(context),
                          child: KeyedSubtree(
                            key: ValueKey((
                              source,
                              secondary != null,
                              busy,
                              live,
                            )),
                            child: AdaptiveVideoControls(state),
                          ),
                        ),
                        if (secondary != null && !failed)
                          Positioned(
                            right: 12,
                            bottom: 72,
                            child: SizedBox(
                              width: (size.maxWidth * .28).clamp(112.0, 240.0),
                              child: _VideoInset(
                                onSwap: busy
                                    ? null
                                    : () => onView(
                                        source == 'screen'
                                            ? 'classroom'
                                            : 'screen',
                                        true,
                                      ),
                                onClose: busy
                                    ? null
                                    : () => onView(source, false),
                                child: _InsetVideo(controller: secondary),
                              ),
                            ),
                          ),
                        if (failed)
                          ColoredBox(
                            color: Colors.black87,
                            child: Center(
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: onRetry,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('播放中断，重新连接'),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (!_fullscreen && sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 4,
                runSpacing: 0,
                children: [
                  for (final key in [
                    'screen',
                    'classroom',
                  ].where(sources.contains))
                    TextButton(
                      onPressed: busy ? null : () => onView(key, false),
                      style: TextButton.styleFrom(
                        foregroundColor: source == key && secondary == null
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        backgroundColor: source == key && secondary == null
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : null,
                      ),
                      child: Text(key == 'screen' ? '课件画面' : '老师画面'),
                    ),
                  if (sources.length > 1)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => onView(source, secondary == null),
                      style: TextButton.styleFrom(
                        foregroundColor: secondary != null
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        backgroundColor: secondary != null
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : null,
                      ),
                      child: const Text('画中画'),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// A nested Video inherits the main Video's fullscreen state and view parameters.
// Render the small window's SDK texture directly so both views stay independent.
class _InsetVideo extends StatelessWidget {
  const _InsetVideo({required this.controller});
  final VideoController controller;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: ValueListenableBuilder<int?>(
      valueListenable: controller.id,
      builder: (context, id, _) => ValueListenableBuilder<Rect?>(
        valueListenable: controller.rect,
        builder: (context, rect, _) =>
            id == null || rect == null || rect.width <= 1 || rect.height <= 1
            ? const ColoredBox(color: Colors.black)
            : FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: rect.width,
                  height: rect.height,
                  child: Texture(textureId: id),
                ),
              ),
      ),
    ),
  );
}

class _VideoInset extends StatelessWidget {
  const _VideoInset({
    required this.child,
    required this.onSwap,
    required this.onClose,
  });

  final Widget child;
  final VoidCallback? onSwap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black,
      border: Border.all(color: Colors.white54),
      borderRadius: BorderRadius.circular(6),
      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned.fill(
              child: Tooltip(
                message: '交换主画面',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onSwap,
                    child: const Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.swap_horiz_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: '关闭小窗',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(36, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.all(8),
                ),
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PlaybackActions extends StatelessWidget {
  const _PlaybackActions({
    required this.player,
    required this.sources,
    required this.source,
    required this.dual,
    required this.onView,
    this.busy = false,
    this.live = false,
    this.showViews = true,
    this.onReconnect,
    this.onCollapse,
  });

  final Player player;
  final Set<String> sources;
  final String source;
  final bool dual;
  final void Function(String source, bool dual) onView;
  final bool busy;
  final bool live;
  final bool showViews;
  final VoidCallback? onReconnect;
  final VoidCallback? onCollapse;

  // A route stays open when the SDK automatically hides/unmounts its controls.
  // Keep the app's menu shape and motion while letting Flutter own its lifecycle.
  Future<T?> _pick<T>(BuildContext context, List<PopupMenuEntry<T>> items) {
    final overlay =
        Navigator.of(
              context,
              rootNavigator: true,
            ).overlay!.context.findRenderObject()!
            as RenderBox;
    final button = context.findRenderObject()! as RenderBox;
    final origin = button.localToGlobal(
      Offset(0, button.size.height),
      ancestor: overlay,
    );
    return showMenu<T>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(origin.dx, origin.dy, button.size.width, 0),
        Offset.zero & overlay.size,
      ),
      shape: appControlShape,
      popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : appMenuMotion,
      items: items,
    );
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (!live)
        StreamBuilder<double>(
          stream: player.stream.rate,
          initialData: player.state.rate,
          builder: (context, snapshot) => Builder(
            builder: (buttonContext) => TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: busy
                  ? null
                  : () async {
                      final rate = await _pick<double>(buttonContext, [
                        for (final rate in [
                          0.75,
                          1.0,
                          1.25,
                          1.5,
                          2.0,
                          3.0,
                          4.0,
                        ])
                          CheckedPopupMenuItem(
                            value: rate,
                            checked: rate == snapshot.data,
                            child: Text('$rate×'),
                          ),
                      ]);
                      if (rate != null) await player.setRate(rate);
                    },
              child: Text('${snapshot.data}×'),
            ),
          ),
        ),
      if (showViews && sources.length > 1) ...[
        Builder(
          builder: (buttonContext) => IconButton(
            tooltip: '切换画面',
            color: Colors.white,
            onPressed: busy
                ? null
                : () async {
                    final next = await _pick<String>(buttonContext, [
                      for (final key in sources)
                        CheckedPopupMenuItem(
                          value: key,
                          checked: source == key,
                          child: Text(key == 'screen' ? '课件画面' : '教室画面'),
                        ),
                    ]);
                    if (next != null) onView(next, dual);
                  },
            icon: const Icon(Icons.video_settings_rounded),
          ),
        ),
        IconButton(
          tooltip: dual ? '关闭画中画' : '开启画中画',
          color: Colors.white,
          onPressed: busy ? null : () => onView(source, !dual),
          icon: Icon(
            dual
                ? Icons.picture_in_picture
                : Icons.picture_in_picture_alt_outlined,
          ),
        ),
      ],
      if (onReconnect != null || onCollapse != null)
        Builder(
          builder: (buttonContext) => IconButton(
            tooltip: '更多播放操作',
            color: Colors.white,
            onPressed: busy
                ? null
                : () async {
                    final action = await _pick<String>(buttonContext, [
                      if (onReconnect != null)
                        const PopupMenuItem(
                          value: 'reconnect',
                          child: Text('重新连接'),
                        ),
                      if (onCollapse != null)
                        const PopupMenuItem(
                          value: 'collapse',
                          child: Text('收起播放器'),
                        ),
                    ]);
                    if (action == 'reconnect') onReconnect?.call();
                    if (action == 'collapse') onCollapse?.call();
                  },
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ),
    ],
  );
}
