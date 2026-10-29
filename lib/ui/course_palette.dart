import 'package:flutter/material.dart';

import '../schedule/building_palette.dart';

enum DarkCoursePalette {
  standard('默认'),
  mocha('Mocha'),
  macchiato('Macchiato'),
  frappe('Frappé');

  const DarkCoursePalette(this.label);

  final String label;

  BuildingColorValues colorsFor(BuildingPalette building) =>
      _colorsForArea(building.area) ?? building.dark;

  /// Opaque colour pairs for native courses by area, plus a surface pair.
  /// An empty map restores the widget's default colours.
  Map<String, List<int>> get widgetColors {
    final surface = _colorsForArea(null);
    if (surface == null) return {};
    final result = <String, List<int>>{
      'surface': [surface.fill, surface.text],
    };
    for (final area in <CampusArea?>[...CampusArea.values, null]) {
      final colors = _colorsForArea(area);
      if (colors == null) continue;
      result[area?.name ?? 'neutral'] = [
        Color.lerp(Color(colors.fill), Color(colors.accent), 0.24)!.toARGB32(),
        colors.text,
      ];
    }
    return result;
  }

  BuildingColorValues? _colorsForArea(CampusArea? area) {
    // Catppuccin's Base, Text and area accents. Keep the generated building
    // table intact so both renderers can restore their default colours.
    final colors = switch (this) {
      standard => null,
      mocha => (
        base: 0xFF1E1E2E,
        text: 0xFFCDD6F4,
        blue: 0xFF89B4FA,
        green: 0xFFA6E3A1,
        yellow: 0xFFF9E2AF,
        mauve: 0xFFCBA6F7,
        peach: 0xFFFAB387,
        neutral: 0xFFBAC2DE,
      ),
      macchiato => (
        base: 0xFF24273A,
        text: 0xFFCAD3F5,
        blue: 0xFF8AADF4,
        green: 0xFFA6DA95,
        yellow: 0xFFEED49F,
        mauve: 0xFFC6A0F6,
        peach: 0xFFF5A97F,
        neutral: 0xFFB8C0E0,
      ),
      frappe => (
        base: 0xFF303446,
        text: 0xFFC6D0F5,
        blue: 0xFF8CAAEE,
        green: 0xFFA6D189,
        yellow: 0xFFE5C890,
        mauve: 0xFFCA9EE6,
        peach: 0xFFEF9F76,
        neutral: 0xFFB5BFE2,
      ),
    };
    if (colors == null) return null;
    return (
      fill: colors.base,
      text: colors.text,
      accent: switch (area) {
        CampusArea.northTeaching => colors.blue,
        CampusArea.wencui => colors.green,
        CampusArea.southScience => colors.yellow,
        CampusArea.eastFacilities => colors.mauve,
        CampusArea.southEngineering => colors.peach,
        null => colors.neutral,
      },
    );
  }
}

class CoursePaletteTheme extends ThemeExtension<CoursePaletteTheme> {
  const CoursePaletteTheme(this.darkPalette);

  final DarkCoursePalette darkPalette;

  @override
  CoursePaletteTheme copyWith({DarkCoursePalette? darkPalette}) =>
      CoursePaletteTheme(darkPalette ?? this.darkPalette);

  @override
  CoursePaletteTheme lerp(CoursePaletteTheme? other, double t) =>
      other == null || t < 0.5 ? this : other;
}
