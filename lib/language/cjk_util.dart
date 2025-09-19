import 'package:unorm_dart/unorm_dart.dart';

// Derived from the following file:
// https://github.com/yomidevs/yomitan/blob/master/ext/js/language/CJK-util.js

typedef CodepointRange = (int minInclusive, int maxInclusive);

const CodepointRange CJK_UNIFIED_IDEOGRAPHS_RANGE = (0x4e00, 0x9fff);
const CodepointRange CJK_UNIFIED_IDEOGRAPHS_EXTENSION_A_RANGE = (0x3400, 0x4dbf);
const CodepointRange CJK_UNIFIED_IDEOGRAPHS_EXTENSION_B_RANGE = (0x20000, 0x2a6df);
const CodepointRange CJK_UNIFIED_IDEOGRAPHS_EXTENSION_C_RANGE = (0x2a700, 0x2b73f);
const CodepointRange CJK_UNIFIED_IDEOGRAPHS_EXTENSION_D_RANGE = (0x2b740, 0x2b81f);
const CodepointRange CJK_UNIFIED_IDEOGRAPHS_EXTENSION_E_RANGE = (0x2b820, 0x2ceaf);
const CodepointRange CJK_UNIFIED_IDEOGRAPHS_EXTENSION_F_RANGE = (0x2ceb0, 0x2ebef);
const CodepointRange CJK_UNIFIED_IDEOGRAPHS_EXTENSION_G_RANGE = (0x30000, 0x3134f);
const CodepointRange CJK_UNIFIED_IDEOGRAPHS_EXTENSION_H_RANGE = (0x31350, 0x323af);
const CodepointRange CJK_UNIFIED_IDEOGRAPHS_EXTENSION_I_RANGE = (0x2ebf0, 0x2ee5f);
const CodepointRange CJK_COMPATIBILITY_IDEOGRAPHS_RANGE = (0xf900, 0xfaff);
const CodepointRange CJK_COMPATIBILITY_IDEOGRAPHS_SUPPLEMENT_RANGE = (0x2f800, 0x2fa1f);

const List<CodepointRange> CJK_IDEOGRAPH_RANGES = [
  CJK_UNIFIED_IDEOGRAPHS_RANGE,
  CJK_UNIFIED_IDEOGRAPHS_EXTENSION_A_RANGE,
  CJK_UNIFIED_IDEOGRAPHS_EXTENSION_B_RANGE,
  CJK_UNIFIED_IDEOGRAPHS_EXTENSION_C_RANGE,
  CJK_UNIFIED_IDEOGRAPHS_EXTENSION_D_RANGE,
  CJK_UNIFIED_IDEOGRAPHS_EXTENSION_E_RANGE,
  CJK_UNIFIED_IDEOGRAPHS_EXTENSION_F_RANGE,
  CJK_UNIFIED_IDEOGRAPHS_EXTENSION_G_RANGE,
  CJK_UNIFIED_IDEOGRAPHS_EXTENSION_H_RANGE,
  CJK_UNIFIED_IDEOGRAPHS_EXTENSION_I_RANGE,
  CJK_COMPATIBILITY_IDEOGRAPHS_RANGE,
  CJK_COMPATIBILITY_IDEOGRAPHS_SUPPLEMENT_RANGE,
];

const List<CodepointRange> FULLWIDTH_CHARACTER_RANGES = [
  (0xff10, 0xff19), // Fullwidth numbers
  (0xff21, 0xff3a), // Fullwidth upper case Latin letters
  (0xff41, 0xff5a), // Fullwidth lower case Latin letters

  (0xff01, 0xff0f), // Fullwidth punctuation 1
  (0xff1a, 0xff1f), // Fullwidth punctuation 2
  (0xff3b, 0xff3f), // Fullwidth punctuation 3
  (0xff5b, 0xff60), // Fullwidth punctuation 4
  (0xffe0, 0xffee), // Currency markers
];

const CodepointRange CJK_PUNCTUATION_RANGE = (0x3000, 0x303f);

const CodepointRange CJK_COMPATIBILITY = (0x3300, 0x33ff);

bool isCodePointInRange(int codePoint, CodepointRange range) => (codePoint >= range.$1 && codePoint <= range.$2);

bool isCodePointInRanges(int codePoint, List<CodepointRange> ranges) {
  for (final (int min, int max) in ranges) {
    if (codePoint >= min && codePoint <= max) {
      return true;
    }
  }
  return false;
}

const CodepointRange KANGXI_RADICALS_RANGE = (0x2f00, 0x2fdf);

const CodepointRange CJK_RADICALS_SUPPLEMENT_RANGE = (0x2e80, 0x2eff);

const CodepointRange CJK_STROKES_RANGE = (0x31c0, 0x31ef);

const List<CodepointRange> CJK_RADICALS_RANGES = [
  KANGXI_RADICALS_RANGE,
  CJK_RADICALS_SUPPLEMENT_RANGE,
  CJK_STROKES_RANGE,
];

// TODO: Test normalization
String normalizeRadicals(String text) {
  String result = '';
  for (int i = 0; i < text.length; i++) {
    final codePoint = text[i].codeUnitAt(0);
    result += (codePoint != 0) && (isCodePointInRanges(codePoint, CJK_RADICALS_RANGES)) ? nfkd(text[i]) : text[i];
  }
  return result;
}
