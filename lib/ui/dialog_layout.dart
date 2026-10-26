import 'dart:math' as math;

import 'package:flutter/material.dart';

Widget appPickerDialogBuilder(BuildContext context, Widget? child) {
  final media = MediaQuery.of(context);
  final theme = DialogTheme.of(context);
  final inset = theme.insetPadding!;
  final width = math.min(
    theme.constraints!.maxWidth,
    media.size.width - inset.horizontal,
  );

  // Native pickers reserve 16px per side. Their orientation should follow
  // the dialog width rather than the full desktop window.
  return Padding(
    padding: EdgeInsets.only(left: inset.left - 16, right: inset.right - 16),
    child: MediaQuery(
      data: media.copyWith(size: Size(width, media.size.height)),
      child: child!,
    ),
  );
}
