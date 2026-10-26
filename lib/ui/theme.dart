import 'package:flutter/material.dart';

const copper = Color(0xFFA85E3E);

ThemeData bitreeTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: copper,
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.neutral,
      ).copyWith(
        primary: dark ? const Color(0xFFE5AE8F) : copper,
        onPrimary: dark ? const Color(0xFF301C12) : Colors.white,
        primaryContainer: dark
            ? const Color(0xFF3B302A)
            : const Color(0xFFEEE6E0),
        onPrimaryContainer: dark
            ? const Color(0xFFE9D8CC)
            : const Color(0xFF493224),
        secondaryContainer: dark
            ? const Color(0xFF343434)
            : const Color(0xFFE5E5E5),
        onSecondaryContainer: dark
            ? const Color(0xFFE8E8E8)
            : const Color(0xFF292929),
        surface: dark ? const Color(0xFF171717) : const Color(0xFFF8F8F8),
        onSurface: dark ? const Color(0xFFE8E8E8) : const Color(0xFF242424),
        onSurfaceVariant: dark
            ? const Color(0xFFAAAAAA)
            : const Color(0xFF666666),
        surfaceContainerLowest: dark ? const Color(0xFF111111) : Colors.white,
        surfaceContainerLow: dark ? const Color(0xFF202020) : Colors.white,
        surfaceContainer: dark
            ? const Color(0xFF282828)
            : const Color(0xFFF0F0F0),
        surfaceContainerHigh: dark
            ? const Color(0xFF303030)
            : const Color(0xFFE8E8E8),
        surfaceContainerHighest: dark
            ? const Color(0xFF383838)
            : const Color(0xFFE0E0E0),
        outline: dark ? const Color(0xFF808080) : const Color(0xFF858585),
        outlineVariant: dark
            ? const Color(0xFF3A3A3A)
            : const Color(0xFFDDDDDD),
        surfaceTint: Colors.transparent,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamilyFallback: const [
      'Noto Sans CJK SC',
      'Microsoft YaHei',
      'PingFang SC',
    ],
    visualDensity: VisualDensity.standard,
    textTheme: TextTheme(
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.5, color: scheme.onSurface),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.45,
        color: scheme.onSurface,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.4,
        color: scheme.onSurfaceVariant,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: scheme.primaryContainer,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          height: 1.3,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      minLeadingWidth: 24,
      horizontalTitleGap: 14,
      minVerticalPadding: 12,
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: TextStyle(fontSize: 15, color: scheme.onSurface),
      subtitleTextStyle: TextStyle(
        fontSize: 13,
        height: 1.45,
        color: scheme.onSurfaceVariant,
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: scheme.outlineVariant,
      dragHandleSize: const Size(32, 4),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    dialogTheme: DialogThemeData(
      constraints: const BoxConstraints.tightFor(width: 360),
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    timePickerTheme: const TimePickerThemeData(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}

({Color fill, Color text, Color accent}) courseColors(
  BuildContext context,
  int index,
) {
  const light = [
    (0xFFD9F0E2, 0xFF254D35, 0xFF5C9772),
    (0xFFF7E0D1, 0xFF79442C, 0xFFB57652),
    (0xFFDDE9FF, 0xFF304F7A, 0xFF6C92C7),
    (0xFFE9E0FA, 0xFF60447F, 0xFF9773BF),
    (0xFFF6EAC5, 0xFF705623, 0xFFB79B4B),
    (0xFFD7EFEF, 0xFF285E61, 0xFF589D9F),
  ];
  const dark = [
    (0xFF2D3C2D, 0xFFD0DFCA, 0xFF93AE86),
    (0xFF463329, 0xFFF0D0B9, 0xFFC69670),
    (0xFF293B4E, 0xFFCADCF1, 0xFF8DADD1),
    (0xFF3C3046, 0xFFE3D1F0, 0xFFB59DC8),
    (0xFF403B28, 0xFFE8DDAE, 0xFFC1AB6A),
    (0xFF253F39, 0xFFBFE1D7, 0xFF8BB8A8),
  ];
  final colors = (Theme.of(context).brightness == Brightness.dark
      ? dark
      : light)[index];
  return (
    fill: Color(colors.$1),
    text: Color(colors.$2),
    accent: Color(colors.$3),
  );
}
