import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../diagnostics.dart';

/// Refreshes the native widget after a persisted change. A widget failure does
/// not turn a completed data write into a failed save.
void refreshDesktopWidget() {
  if (!Platform.isAndroid) return;
  unawaited(_refresh());
}

Future<void> _refresh() async {
  try {
    await const MethodChannel('dev.so1ve.bitree/widget')
        .invokeMethod<void>('update');
  } on Exception catch (failure, stack) {
    AppDiagnostics.instance.error('更新桌面组件', failure, stack);
  }
}
