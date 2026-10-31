import 'package:flutter/material.dart';

abstract final class AppCorners {
  static const controlRadius = Radius.circular(10);
  static const _panelRadius = Radius.circular(20);
  static const compact = BorderRadius.all(Radius.circular(6));
  static const control = BorderRadius.all(controlRadius);
  static const panel = BorderRadius.all(_panelRadius);
  static const sheet = BorderRadius.vertical(top: _panelRadius);
}

const appControlShape = RoundedRectangleBorder(
  borderRadius: AppCorners.control,
);
const appPanelShape = RoundedRectangleBorder(borderRadius: AppCorners.panel);
const appControlSize = Size(48, 48);
const appControlPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
const appSheetContentPadding = EdgeInsets.fromLTRB(24, 8, 24, 16);
const appSheetActionPadding = EdgeInsets.symmetric(
  horizontal: 24,
  vertical: 12,
);
