import 'dart:io';

import 'package:flutter/services.dart';

import '../diagnostics.dart';

/// Refreshes the native widget after a persisted change. A widget failure does
/// not turn a completed data write into a failed save.
Future<void> updateDesktopWidget() async {
  if (!Platform.isAndroid) return;
  try {
    await const MethodChannel('dev.so1ve.bitree/widget')
        .invokeMethod<void>('update');
  } catch (failure, stack) {
    AppDiagnostics.instance.report('更新桌面组件', failure, stack);
  }
}
