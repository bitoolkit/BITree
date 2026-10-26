import 'package:bitree/wencui/place.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Room search shares campus aliases and accepts short/full-width input',
    () {
      for (final value in [
        'F704',
        ' ｆ－７０４ ',
        '文萃楼 F704',
        '良乡校区 文萃F楼704',
        '文萃F栋704教室',
      ]) {
        final place = WencuiPlace.parse(value)!;
        expect(place.wing, WencuiWing.f, reason: value);
        expect(place.floor, 7);
        expect(place.label, 'F704');
      }
      expect(WencuiPlace.parse('文萃楼J1006')!.floor, 10);
      expect(WencuiPlace.parse('F')!.floor, isNull);
      expect(WencuiPlace.parse('文萃楼A')!.wing.firstFloor, 3);
    },
  );

  test(
    'Ambiguous locations and unsupported floors do not select a destination',
    () {
      for (final value in [
        '',
        '文萃楼',
        'F7',
        'F70',
        'F7040',
        'F801',
        'A101',
        'H301',
        'L1101',
        '文萃楼F704/F705',
        '文萃楼F704/文萃楼I704',
        '文萃楼FA704',
        '中关村文萃楼F704',
      ]) {
        expect(WencuiPlace.parse(value), isNull, reason: value);
      }
      expect(WencuiPlace.parse('文萃楼F704', campus: '中关村校区'), isNull);
    },
  );
}
