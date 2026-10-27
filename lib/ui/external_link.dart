import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/diagnostics.dart';

Future<bool> openExternalLink(
  BuildContext context,
  Uri url, {
  required String failureTitle,
}) async {
  bool opened;
  try {
    opened = await launchUrl(url, mode: LaunchMode.externalApplication);
  } on PlatformException catch (failure, stack) {
    AppDiagnostics.instance.error('打开外部链接', failure, stack);
    opened = false;
  }

  if (opened || !context.mounted) return opened;

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(failureTitle),
      content: SelectableText('请在浏览器中打开：\n$url'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

  return false;
}
