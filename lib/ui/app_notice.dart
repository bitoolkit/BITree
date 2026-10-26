import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_page.dart';
import 'design.dart';

OverlayEntry? _notice;
Timer? _dismissTimer;

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
  _notice = OverlayEntry(
    builder: (context) {
      final theme = Theme.of(context);
      return Positioned(
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
      );
    },
  );
  overlay.insert(_notice!);
  if (action == null || !MediaQuery.accessibleNavigationOf(overlay.context)) {
    _dismissTimer = Timer(
      Duration(seconds: action == null ? 4 : 8),
      _dismissNotice,
    );
  }
}

void _dismissNotice() {
  _dismissTimer?.cancel();
  _dismissTimer = null;
  _notice?.remove();
  _notice?.dispose();
  _notice = null;
}
