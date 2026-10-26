import 'location.dart';

part 'building_palette.g.dart';

typedef BuildingColorValues = ({int fill, int text, int accent});

class BuildingPalette {
  const BuildingPalette({
    required this.name,
    required this.light,
    required this.dark,
  });

  final String name;
  final BuildingColorValues light;
  final BuildingColorValues dark;
}

final _rules = [
  for (final (pattern, palette) in _buildingData) (RegExp(pattern), palette),
];
final _otherCampuses = RegExp(r'中关村|西山|珠海|雄安|怀来');

BuildingPalette? matchCampusBuilding(String room, {String campus = ''}) {
  if (_otherCampuses.hasMatch('$campus $room')) return null;

  final normalized = normalizeCampusLocation(room);
  final matches = [
    for (final (pattern, palette) in _rules)
      for (final match in pattern.allMatches(normalized))
        (start: match.start, end: match.end, palette: palette),
  ];
  // Prefer a named wing over its containing building group. Separate building
  // names in one location remain ambiguous rather than choosing one arbitrarily.
  final buildings = {
    for (final match in matches)
      if (!matches.any(
        (other) =>
            other.start <= match.start &&
            other.end >= match.end &&
            other.end - other.start > match.end - match.start,
      ))
        match.palette,
  };
  return buildings.length == 1 ? buildings.single : null;
}
