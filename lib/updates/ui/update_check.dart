import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics.dart';
import '../release.dart';
import '../version.dart';
import 'update_dialog.dart';

const _lastCheckKey = 'updates.lastCheck';

String _notifiedVersionKey(AppRelease release) =>
    'updates.${release.isDevelopment ? 'dev' : 'stable'}.notifiedVersion';

Future<void> checkForUpdates(
  BuildContext context, {
  bool silent = false,
}) async {
  try {
    final preferences = SharedPreferencesAsync();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (silent) {
      final lastCheck = await preferences.getInt(_lastCheckKey);
      if (lastCheck != null &&
          now - lastCheck < const Duration(days: 1).inMilliseconds) {
        return;
      }
    }

    final installed = await appVersion();
    final available = await availableAppReleases(
      installed,
      builtAt: appBuildTime,
    );
    await preferences.setInt(_lastCheckKey, now);

    final releases = <AppRelease>[];
    for (final release in available) {
      if (silent &&
          await preferences.getString(_notifiedVersionKey(release)) ==
              release.version) {
        continue;
      }
      releases.add(release);
    }

    if (!context.mounted) return;
    if (silent && !ModalRoute.of(context)!.isCurrent) return;

    if (releases.isEmpty) {
      if (!silent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已是最新版本')));
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

    for (final release in releases) {
      await preferences.setString(
        _notifiedVersionKey(release),
        release.version,
      );
    }
  } catch (failure, stack) {
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
