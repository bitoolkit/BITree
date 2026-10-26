final _locationSpacing = RegExp(r'[\s\u00A0\u3000·._\-—–（）()\[\]【】]');

String normalizeCampusLocation(String value) => String.fromCharCodes(
  value.runes.map(
    (rune) => rune >= 0xFF01 && rune <= 0xFF5E ? rune - 0xFEE0 : rune,
  ),
).toUpperCase().replaceAll(_locationSpacing, '');
