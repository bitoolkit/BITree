import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_page.dart';
import 'design.dart';

OverlayEntry? _notice;

/// The root overlay keeps feedback visible above course detail sheets.
void showAppNotice(
  BuildContext context,
  String message, {
  ({String label, VoidCallback onPressed})? action,
}) => showOverlayNotice(
  Overlay.of(context, rootOverlay: true),
  message,
  action: action,
);

/// Allows an undo action to outlive the route where it started.
void showOverlayNotice(
  OverlayState overlay,
  String message, {
  ({String label, VoidCallback onPressed})? action,
}) {
  _dismissNotice();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      final theme = Theme.of(context);
      return _NoticeLifetime(
        duration: action != null && MediaQuery.accessibleNavigationOf(context)
            ? null
            : Duration(seconds: action == null ? 4 : 8),
        onDismiss: () {
          if (identical(_notice, entry)) _dismissNotice();
        },
        child: Positioned(
          bottom:
              math.max(
                MediaQuery.viewInsetsOf(context).bottom,
                appNavigationBarHeight(context) +
                    MediaQuery.viewPaddingOf(context).bottom,
              ) +
              16,
          left: 0,
          right: 0,
          child: SafeArea(
            top: false,
            bottom: false,
            minimum: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  child: Material(
                    color: theme.colorScheme.inverseSurface,
                    borderRadius: AppCorners.control,
                    elevation: 6,
                    child: Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: action == null ? 12 : 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                message,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onInverseSurface,
                                ),
                              ),
                            ),
                            if (action != null) ...[
                              const SizedBox(width: 12),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      theme.colorScheme.inversePrimary,
                                ),
                                onPressed: () {
                                  _dismissNotice();
                                  action.onPressed();
                                },
                                child: Text(action.label),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  _notice = entry;
  overlay.insert(entry);
}

void _dismissNotice() {
  final entry = _notice;
  _notice = null;
  entry?.remove();
  entry?.dispose();
}

class _NoticeLifetime extends StatefulWidget {
  const _NoticeLifetime({
    required this.duration,
    required this.onDismiss,
    required this.child,
  });
  final Duration? duration;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_NoticeLifetime> createState() => _NoticeLifetimeState();
}

class _NoticeLifetimeState extends State<_NoticeLifetime> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.duration case final duration?) {
      _timer = Timer(duration, widget.onDismiss);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.onDismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
