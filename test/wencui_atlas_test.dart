import 'package:bitree/wencui/atlas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Offline room geometry covers each floor and points stay inside hit regions', () async {
    final atlas = await WencuiAtlas.load();
    expect(await WencuiAtlas.load(), same(atlas));
    for (final label in [
      'F102',
      'F202',
      'F303',
      'F404',
      'F504',
      'F604',
      'F704',
      'J801',
      'J901',
      'J1006',
    ]) {
      expect(atlas.room(label), isNotNull, reason: label);
    }
    final roomKeys = <String>{};
    for (final feature in atlas.features) {
      expect(
        feature.path.contains(feature.anchor),
        isTrue,
        reason: '${feature.floor} ${feature.title}',
      );
      expect(feature.floor, inInclusiveRange(1, 10));
      for (final point in feature.outline) {
        expect(point.dx, inInclusiveRange(0, 1));
        expect(point.dy, inInclusiveRange(0, 1));
      }
      if (feature.kind == WencuiFeatureKind.room) {
        expect(
          roomKeys.add('${feature.floor}:${feature.label}'),
          isTrue,
          reason: feature.label,
        );
      }
    }
    final f704 = atlas.room('F704')!;
    expect(atlas.room('J701')!.anchor.dy, greaterThan(.5));
    expect(atlas.room('L701'), isNull);
    expect(f704.anchor.dx, closeTo(.709, .002));
    expect(f704.anchor.dy, closeTo(.556, .002));
  });
}
