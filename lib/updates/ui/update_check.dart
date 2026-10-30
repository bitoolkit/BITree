import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics.dart';
import '../../ui/app_notice.dart';
import '../repository.dart';
import '../version.dart';
import 'update_dialog.dart';

Future<void> checkForUpdates(
  BuildContext context, {
  bool silent = false,
}) async {
  try {
    final updates = UpdateRepository(SharedPreferencesAsync());
    final installed = await appVersion();
    final releases = await updates.check(
      installed,
      builtAt: appBuildTime,
      automatic: silent,
    );

    if (!context.mounted) return;
    if (silent && !ModalRoute.of(context)!.isCurrent) return;

    if (releases.isEmpty) {
      if (!silent) {
        showAppNotice(context, '已是最新版本');
      }
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => UpdateDialog(
        releases: releases,
        preferDevelopment: installed.contains('-'),
      ),
    );

    await updates.markNotified(releases);
  } on Exception catch (failure, stack) {
    if (silent || !context.mounted) {
      AppDiagnostics.instance.error('检查更新', failure, stack);
    } else {
      AppDiagnostics.instance.report(
        '检查更新',
        failure,
        stack,
        message: failure is HttpException
            ? failure.message
            : '检查更新失败，请检查网络后重试。',
      );
    }
  }
}
