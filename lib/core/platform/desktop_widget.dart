import 'dart:io';

import 'package:flutter/services.dart';

import '../diagnostics.dart';

/// Refreshes the native widget after a persisted change. A widget failure does
/// not turn a completed data write into a failed save. Supply [darkCourseColors]
/// to persist a new palette, or an empty map to restore native default colours.
/// Content-only refreshes leave the saved appearance unchanged.
Future<void> updateDesktopWidget({
  Map<String, List<int>>? darkCourseColors,
  bool? useSystemPalette,
}) async {
  if (!Platform.isAndroid) return;
  try {
    await const MethodChannel('dev.so1ve.bitree/widget').invokeMethod<void>(
      'update',
      darkCourseColors == null && useSystemPalette == null
          ? null
          : {
              'darkCourseColors': ?darkCourseColors,
              'useSystemPalette': ?useSystemPalette,
            },
    );
  } catch (failure, stack) {
    AppDiagnostics.instance.report('更新桌面组件', failure, stack);
  }
}
