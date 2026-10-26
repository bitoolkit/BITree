import '../schedule/building_palette.dart';
import '../schedule/location.dart';

enum WencuiWing {
  a('A', 3, 7),
  b('B', 1, 2),
  c('C', 1, 10),
  d('D', 1, 7),
  e('E', 1, 10),
  f('F', 1, 7),
  g('G', 1, 2),
  h('H', 1, 2),
  i('I', 1, 7),
  j('J', 1, 10),
  k('K', 1, 7),
  l('L', 1, 10),
  m('M', 1, 2);

  const WencuiWing(this.letter, this.firstFloor, this.lastFloor);

  final String letter;
  final int firstFloor;
  final int lastFloor;

  String get name => '$letter栋';
  String get floorLabel => '$firstFloor–$lastFloor层';
  bool hasFloor(int floor) => floor >= firstFloor && floor <= lastFloor;
}

class WencuiPlace {
  const WencuiPlace(this.wing, {this.room});

  final WencuiWing wing;
  final String? room;

  int? get floor =>
      room == null ? null : int.parse(room!.substring(0, room!.length - 2));
  String get label => '${wing.letter}${room ?? '栋'}';

  /// Accept short room numbers in this WenCui-only search, while using the same
  /// building aliases and campus disambiguation as the timetable.
  static WencuiPlace? parse(String value, {String campus = ''}) {
    final normalized = normalizeCampusLocation(value);
    final short = RegExp(r'^[A-M](?:[0-9]{3,4})?$').hasMatch(normalized);
    final palette = matchCampusBuilding(
      short ? '文萃楼$normalized' : value,
      campus: campus,
    );
    if (palette == null) return null;
    final wings = WencuiWing.values.where(
      (wing) => palette.name == '文萃楼${wing.letter}',
    );
    if (wings.isEmpty) return null;
    final wing = wings.single;
    final rooms = RegExp('${wing.letter}(?:楼|栋|座|区)?([0-9]{3,4})(?![0-9])')
        .allMatches(normalized)
        .map((match) => match.group(1)!)
        .toSet();
    if (rooms.length > 1) return null;
    final room = rooms.singleOrNull;
    // A partial or unsupported room number must not silently become a wing.
    if (room == null && RegExp(r'[0-9]').hasMatch(normalized)) return null;
    final place = WencuiPlace(wing, room: room);
    if (place.floor != null && !wing.hasFloor(place.floor!)) return null;
    return place;
  }
}
