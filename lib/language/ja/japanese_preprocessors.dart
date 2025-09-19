// Ported from
// https://github.com/yomidevs/yomitan/blob/master/ext/js/language/ja/japanese.js

import 'dart:math';
import 'package:kana_kit/kana_kit.dart';
import 'package:unorm_dart/unorm_dart.dart';
import '../cjk_util.dart';

enum DiacriticType {
  dakuten,
  handakuten,
}

typedef FuriganaGroup = ({
  bool isKana,
  String text,
  String? textNormalized,
});

typedef FuriganaSegment = ({
  String text,
  String reading,
});

enum PitchCategory { heiban, kifuku, atamadaka, odaka, nakadaka }

const HIRAGANA_SMALL_TSU_CODE_POINT = 0x3063;
const KATAKANA_SMALL_TSU_CODE_POINT = 0x30c3;
const KATAKANA_SMALL_KA_CODE_POINT = 0x30f5;
const KATAKANA_SMALL_KE_CODE_POINT = 0x30f6;
const KANA_PROLONGED_SOUND_MARK_CODE_POINT = 0x30fc;

const HIRAGANA_RANGE = (0x3040, 0x309f);
const KATAKANA_RANGE = (0x30a0, 0x30ff);

const HIRAGANA_CONVERSION_RANGE = (0x3041, 0x3096);
const KATAKANA_CONVERSION_RANGE = (0x30a1, 0x30f6);

const KANA_RANGES = [HIRAGANA_RANGE, KATAKANA_RANGE];

/**
 * Japanese character ranges, roughly ordered in order of expected frequency.
 * @type {import('CJK-util').CodepointRange[]}
 */
//
const JAPANESE_RANGES = [
  HIRAGANA_RANGE,
  KATAKANA_RANGE,

  ...CJK_IDEOGRAPH_RANGES,

  (0xff66, 0xff9f), // Halfwidth katakana

  (0x30fb, 0x30fc), // Katakana punctuation
  (0xff61, 0xff65), // Kana punctuation
  (0x3000, 0x303f), // CJK punctuation

  (0xff10, 0xff19), // Fullwidth numbers
  (0xff21, 0xff3a), // Fullwidth upper case Latin letters
  (0xff41, 0xff5a), // Fullwidth lower case Latin letters

  (0xff01, 0xff0f), // Fullwidth punctuation 1
  (0xff1a, 0xff1f), // Fullwidth punctuation 2
  (0xff3b, 0xff3f), // Fullwidth punctuation 3
  (0xff5b, 0xff60), // Fullwidth punctuation 4
  (0xffe0, 0xffee), // Currency markers
];

const SMALL_KANA_SET = {
  'ぁ',
  'ぃ',
  'ぅ',
  'ぇ',
  'ぉ',
  'ゃ',
  'ゅ',
  'ょ',
  'ゎ',
  'ァ',
  'ィ',
  'ゥ',
  'ェ',
  'ォ',
  'ャ',
  'ュ',
  'ョ',
  'ヮ'
};

const HALFWIDTH_KATAKANA_MAPPING = {
  '･': '・--',
  'ｦ': 'ヲヺ-',
  'ｧ': 'ァ--',
  'ｨ': 'ィ--',
  'ｩ': 'ゥ--',
  'ｪ': 'ェ--',
  'ｫ': 'ォ--',
  'ｬ': 'ャ--',
  'ｭ': 'ュ--',
  'ｮ': 'ョ--',
  'ｯ': 'ッ--',
  'ｰ': 'ー--',
  'ｱ': 'ア--',
  'ｲ': 'イ--',
  'ｳ': 'ウヴ-',
  'ｴ': 'エ--',
  'ｵ': 'オ--',
  'ｶ': 'カガ-',
  'ｷ': 'キギ-',
  'ｸ': 'クグ-',
  'ｹ': 'ケゲ-',
  'ｺ': 'コゴ-',
  'ｻ': 'サザ-',
  'ｼ': 'シジ-',
  'ｽ': 'スズ-',
  'ｾ': 'セゼ-',
  'ｿ': 'ソゾ-',
  'ﾀ': 'タダ-',
  'ﾁ': 'チヂ-',
  'ﾂ': 'ツヅ-',
  'ﾃ': 'テデ-',
  'ﾄ': 'トド-',
  'ﾅ': 'ナ--',
  'ﾆ': 'ニ--',
  'ﾇ': 'ヌ--',
  'ﾈ': 'ネ--',
  'ﾉ': 'ノ--',
  'ﾊ': 'ハバパ',
  'ﾋ': 'ヒビピ',
  'ﾌ': 'フブプ',
  'ﾍ': 'ヘベペ',
  'ﾎ': 'ホボポ',
  'ﾏ': 'マ--',
  'ﾐ': 'ミ--',
  'ﾑ': 'ム--',
  'ﾒ': 'メ--',
  'ﾓ': 'モ--',
  'ﾔ': 'ヤ--',
  'ﾕ': 'ユ--',
  'ﾖ': 'ヨ--',
  'ﾗ': 'ラ--',
  'ﾘ': 'リ--',
  'ﾙ': 'ル--',
  'ﾚ': 'レ--',
  'ﾛ': 'ロ--',
  'ﾜ': 'ワ--',
  'ﾝ': 'ン--',
};

const VOWEL_TO_KANA_MAPPING = {
  'a': 'ぁあかがさざただなはばぱまゃやらゎわヵァアカガサザタダナハバパマャヤラヮワヵヷ',
  'i': 'ぃいきぎしじちぢにひびぴみりゐィイキギシジチヂニヒビピミリヰヸ',
  'u': 'ぅうくぐすずっつづぬふぶぷむゅゆるゥウクグスズッツヅヌフブプムュユルヴ',
  'e': 'ぇえけげせぜてでねへべぺめれゑヶェエケゲセゼテデネヘベペメレヱヶヹ',
  'o': 'ぉおこごそぞとどのほぼぽもょよろをォオコゴソゾトドノホボポモョヨロヲヺ',
  '': 'のノ',
};

// TODO: Test
final KANA_TO_VOWEL_MAPPING = Map.fromEntries(
    VOWEL_TO_KANA_MAPPING.entries.expand((entry) => entry.value.split('').map(
          (char) => MapEntry(char, entry.key),
        )));

// TODO: Test
const kana =
    'うゔ-かが-きぎ-くぐ-けげ-こご-さざ-しじ-すず-せぜ-そぞ-ただ-ちぢ-つづ-てで-とど-はばぱひびぴふぶぷへべぺほぼぽワヷ-ヰヸ-ウヴ-ヱヹ-ヲヺ-カガ-キギ-クグ-ケゲ-コゴ-サザ-シジ-スズ-セゼ-ソゾ-タダ-チヂ-ツヅ-テデ-トド-ハバパヒビピフブプヘベペホボポ';
final DIACRITIC_MAPPING =
    Map.fromEntries(kana.split(RegExp('...')).expand((triple) {
  final character = triple[0];
  final dakuten = triple[1];
  final handakuten = triple[2];
  return [
    MapEntry(dakuten, (character: character, type: DiacriticType.dakuten)),
    if (handakuten != '-')
      MapEntry(
          handakuten, (character: character, type: DiacriticType.handakuten)),
  ];
}));

String? getProlongedHiragana(String previousCharacter) =>
    switch (KANA_TO_VOWEL_MAPPING[previousCharacter]) {
      'a' => 'あ',
      'i' => 'い',
      'u' => 'う',
      'e' => 'え',
      'o' => 'う',
      _ => null,
    };

FuriganaSegment createFuriganaSegment(String text, String reading) =>
    (text: text, reading: reading);

List<FuriganaSegment>? segmentizeFurigana(String reading,
    String readingNormalized, List<FuriganaGroup> groups, int groupsStart) {
  final groupCount = groups.length - groupsStart;
  if (groupCount <= 0) {
    return reading.isEmpty ? [] : null;
  }

  final group = groups[groupsStart];
  final (:bool isKana, :String text, :String? textNormalized) = group;
  final textLength = text.length;
  if (isKana) {
    if (textNormalized != null &&
        readingNormalized.startsWith(textNormalized)) {
      final segments = segmentizeFurigana(reading.substring(text.length),
          readingNormalized.substring(textLength), groups, groupsStart + 1);
      if (segments != null) {
        segments.insertAll(
          0,
          reading.startsWith(text)
              ? [createFuriganaSegment(text, '')]
              : getFuriganaKanaSegments(text, reading),
        );
        return segments;
      }
    }
    return null;
  } else {
    List<FuriganaSegment>? result;
    for (int i = reading.length; i >= textLength; i--) {
      final segments = segmentizeFurigana(
        reading.substring(i),
        readingNormalized.substring(i),
        groups,
        groupsStart + 1,
      );
      if (segments != null) {
        if (result != null) {
          // More than one way to segmentize the tail; mark as ambiguous
          return null;
        }
        final segmentReading = reading.substring(0, i);
        segments.insert(0, createFuriganaSegment(text, segmentReading));
        result = segments;
      }
      // There is only one way to segmentize the last non-kana group
      if (groupCount == 1) {
        break;
      }
    }
    return result;
  }
}

List<FuriganaSegment> getFuriganaKanaSegments(String text, String reading) {
  final textLength = text.length;
  final newSegments = <FuriganaSegment>[];
  int start = 0;
  bool state = (reading[0] == text[0]);
  for (int i = 0; i < textLength; i++) {
    final newState = (reading[i] == text[i]);
    if (state == newState) {
      continue;
    }
    newSegments.add(createFuriganaSegment(
        text.substring(start, i), state ? '' : reading.substring(start, i)));
    state = newState;
    start = i;
  }
  newSegments.add(createFuriganaSegment(text.substring(start, textLength),
      state ? '' : reading.substring(start, textLength)));
  return newSegments;
}

int getStemLength(String text1, String text2) {
  final minLength = min(text1.length, text2.length);
  if (minLength == 0) {
    return 0;
  }

  int i = 0;
  while (true) {
    final char1 = text1.codeUnitAt(i);
    final char2 = text2.codeUnitAt(i);
    if (char1 != char2) {
      break;
    }
    final charLength = String.fromCharCode(char1).length;
    i += charLength;
    if (i == minLength) {
      break;
    }
    if (i > minLength) {
      // Don't consume partial UTF16 surrogate characters
      i -= charLength;
    }
  }
  return i;
}

bool isCodePointKanji(int codePoint) =>
    isCodePointInRanges(codePoint, CJK_IDEOGRAPH_RANGES);

bool isCodePointKana(int codePoint) =>
    isCodePointInRanges(codePoint, KANA_RANGES);

bool isCodePointJapanese(int codePoint) =>
    isCodePointInRanges(codePoint, JAPANESE_RANGES);

bool isStringEntirelyKana(String str) {
  if (str.isEmpty) {
    return false;
  }
  for (final c in str.split('')) {
    if (!isCodePointInRanges((c.codeUnitAt(0)), KANA_RANGES)) {
      return false;
    }
  }
  return true;
}

bool isStringPartiallyJapanese(String str) {
  if (str.isEmpty) {
    return false;
  }
  for (final c in str.split('')) {
    if (isCodePointInRanges((c.codeUnitAt(0)), JAPANESE_RANGES)) {
      return true;
    }
  }
  return false;
}

// TODO: Pitch accent, has nothing to do with parsing

bool isMoraPitchHigh(int moraIndex, int pitchAccentDownstepPosition) =>
    switch (pitchAccentDownstepPosition) {
      0 => moraIndex > 0,
      1 => moraIndex < 1,
      _ => moraIndex > 0 && moraIndex < pitchAccentDownstepPosition
    };

PitchCategory? getPitchCategory(
    String text, int pitchAccentDownstepPosition, bool isVerbOrAdjective) {
  if (pitchAccentDownstepPosition == 0) {
    return PitchCategory.heiban;
  }
  if (isVerbOrAdjective) {
    return pitchAccentDownstepPosition > 0 ? PitchCategory.kifuku : null;
  }
  if (pitchAccentDownstepPosition == 1) {
    return PitchCategory.atamadaka;
  }
  if (pitchAccentDownstepPosition > 1) {
    return pitchAccentDownstepPosition >= getKanaMoraCount(text)
        ? PitchCategory.odaka
        : PitchCategory.nakadaka;
  }
  return null;
}

List<String> getKanaMorae(String text) {
  final morae = <String>[];
  int i;
  for (final c in text.split('')) {
    if (SMALL_KANA_SET.contains(c) && (i = morae.length) > 0) {
      morae[i - 1] += c;
    } else {
      morae.add(c);
    }
  }
  return morae;
}

int getKanaMoraCount(String text) {
  int moraCount = 0;
  for (final c in text.split('')) {
    if (!(SMALL_KANA_SET.contains(c) && moraCount > 0)) {
      moraCount++;
    }
  }
  return moraCount;
}

// Preprocessor conversion functions

String convertKatakanaToHiragana(String text,
    [bool keepProlongedSoundMarks = false]) {
  String result = '';
  final offset = (HIRAGANA_CONVERSION_RANGE.$1 - KATAKANA_CONVERSION_RANGE.$1);
  for (var char in text.split('')) {
    final codePoint = (char.codeUnitAt(0));
    switch (codePoint) {
      case KATAKANA_SMALL_KA_CODE_POINT:
      case KATAKANA_SMALL_KE_CODE_POINT:
        // No change
        break;
      case KANA_PROLONGED_SOUND_MARK_CODE_POINT:
        if (!keepProlongedSoundMarks && result.isNotEmpty) {
          final char2 = getProlongedHiragana(result[result.length - 1]);
          if (char2 != null) {
            char = char2;
          }
        }
        break;
      default:
        if (isCodePointInRange(codePoint, KATAKANA_CONVERSION_RANGE)) {
          char = String.fromCharCode(codePoint + offset);
        }
        break;
    }
    result += char;
  }
  return result;
}

String convertHiraganaToKatakana(String text) {
  String result = '';
  final offset = (KATAKANA_CONVERSION_RANGE.$1 - HIRAGANA_CONVERSION_RANGE.$1);
  for (String char in text.split('')) {
    final codePoint = (char.codeUnitAt(0));
    if (isCodePointInRange(codePoint, HIRAGANA_CONVERSION_RANGE)) {
      char = String.fromCharCode(codePoint + offset);
    }
    result += char;
  }
  return result;
}

String convertAlphanumericToFullWidth(String text) {
  String result = '';
  for (final char in text.split('')) {
    int c = (char.codeUnitAt(0));
    if (c >= 0x30 && c <= 0x39) {
      // ['0', '9']
      c += 0xff10 - 0x30; // 0xff10 = '0' full width
    } else if (c >= 0x41 && c <= 0x5a) {
      // ['A', 'Z']
      c += 0xff21 - 0x41; // 0xff21 = 'A' full width
    } else if (c >= 0x61 && c <= 0x7a) {
      // ['a', 'z']
      c += 0xff41 - 0x61; // 0xff41 = 'a' full width
    }
    result += String.fromCharCode(c);
  }
  return result;
}

String convertFullWidthAlphanumericToNormal(String text) {
  String result = '';
  final length = text.length;
  for (int i = 0; i < length; i++) {
    int c = (text[i].codeUnitAt(0));
    if (c >= 0xff10 && c <= 0xff19) {
      // ['０', '９']
      c -= 0xff10 - 0x30; // 0x30 = '0'
    } else if (c >= 0xff21 && c <= 0xff3a) {
      // ['Ａ', 'Ｚ']
      c -= 0xff21 - 0x41; // 0x41 = 'A'
    } else if (c >= 0xff41 && c <= 0xff5a) {
      // ['ａ', 'ｚ']
      c -= 0xff41 - 0x61; // 0x61 = 'a'
    }
    result += String.fromCharCode(c);
  }
  return result;
}

String convertHalfWidthKanaToFullWidth(String text) {
  String result = '';

  // This function is safe to use charCodeAt instead of codePointAt, since all
  // the relevant characters are represented with a single UTF-16 character code.
  for (int i = 0, ii = text.length; i < ii; ++i) {
    final c = text[i];
    final mapping = HALFWIDTH_KATAKANA_MAPPING[c];
    if (mapping == null) {
      result += c;
      continue;
    }

    int index = 0;
    switch (text.codeUnitAt(i + 1)) {
      case 0xff9e: // Dakuten
        index = 1;
        break;
      case 0xff9f: // Handakuten
        index = 2;
        break;
    }

    String c2 = mapping[index];
    if (index > 0) {
      if (c2 == '-') {
        // Invalid
        index = 0;
        c2 = mapping[0];
      } else {
        ++i;
      }
    }

    result += c2;
  }

  return result;
}

// from './japanese-wanakana.js'

String convertAlphabeticPartToKana(String text) => KanaKit().toHiragana(text);

String convertAlphabeticToKana(String text) {
  String part = '';
  String result = '';

  for (final char in text.split('')) {
    // Note: 0x61 is the character code for 'a'
    int c =  (char.codeUnitAt(0));
    if (c >= 0x41 && c <= 0x5a) { // ['A', 'Z']
      c += (0x61 - 0x41);
    } else if (c >= 0x61 && c <= 0x7a) { // ['a', 'z']
      // NOP; c += (0x61 - 0x61);
    } else if (c >= 0xff21 && c <= 0xff3a) { // ['A', 'Z'] fullwidth
      c += (0x61 - 0xff21);
    } else if (c >= 0xff41 && c <= 0xff5a) { // ['a', 'z'] fullwidth
      c += (0x61 - 0xff41);
    } else if (c == 0x2d || c == 0xff0d) { // '-' or fullwidth dash
      c = 0x2d; // '-'
    } else {
      if (part.length > 0) {
        result += convertAlphabeticPartToKana(part);
        part = '';
      }
      result += char;
      continue;
    }
    part += String.fromCharCode(c);
  }

  if (part.length > 0) {
    result += convertAlphabeticPartToKana(part);
  }
  return result;
}

DiacriticType? getKanaDiacriticInfo(String character) {
  final info = DIACRITIC_MAPPING[character];
  return info?.type;
}

bool dakutenAllowed(int codePoint) {
  // To reduce processing time some characters which shouldn't have dakuten but are highly unlikely to have a combining character attached are included
  // かがきぎくぐけげこごさざしじすずせぜそぞただちぢっつづてでとはばぱひびぴふぶぷへべぺほ
  // カガキギクグケゲコゴサザシジスズセゼソゾタダチヂッツヅテデトハバパヒビピフブプヘベペホ
  return ((codePoint >= 0x304B && codePoint <= 0x3068) ||
      (codePoint >= 0x306F && codePoint <= 0x307B) ||
      (codePoint >= 0x30AB && codePoint <= 0x30C8) ||
      (codePoint >= 0x30CF && codePoint <= 0x30DB));
}

bool handakutenAllowed(int codePoint) {
  // To reduce processing time some characters which shouldn't have handakuten but are highly unlikely to have a combining character attached are included
  // はばぱひびぴふぶぷへべぺほ
  // ハバパヒビピフブプヘベペホ
  return ((codePoint >= 0x306F && codePoint <= 0x307B) ||
      (codePoint >= 0x30CF && codePoint <= 0x30DB));
}

String normalizeCombiningCharacters(String text) {
  String result = '';
  int i = text.length - 1;
  // Ignoring the first character is intentional, it cannot combine with anything
  while (i > 0) {
    if (text[i] == '\u3099') {
      final dakutenCombinee = text[i - 1].codeUnitAt(0);
      if ((dakutenCombinee != 0) && dakutenAllowed(dakutenCombinee)) {
        result = String.fromCharCode(dakutenCombinee + 1) + result;
        i -= 2;
        continue;
      }
    } else if (text[i] == '\u309A') {
      final handakutenCombinee = text[i - 1].codeUnitAt(0);
      if ((handakutenCombinee != 0) && handakutenAllowed(handakutenCombinee)) {
        result = String.fromCharCode(handakutenCombinee + 2) + result;
        i -= 2;
        continue;
      }
    }
    result = text[i] + result;
    i--;
  }
  // i == -1 when first two characters are combined
  if (i == 0) {
    result = text[0] + result;
  }
  return result;
}

// TODO: Test
String normalizeCJKCompatibilityCharacters(String text) {
  String result = '';
  for (int i = 0; i < text.length; i++) {
    final codePoint = text[i].codeUnitAt(0);
    result +=
        (codePoint != 0) && isCodePointInRange(codePoint, CJK_COMPATIBILITY)
            ? nfkd(text[i])
            : text[i];
  }
  return result;
}

// Furigana distribution

// TODO: Test
List<FuriganaSegment> distributeFurigana(String term, String reading) {
  if (reading == term) {
    // Same
    return [createFuriganaSegment(term, '')];
  }

  final groups = <FuriganaGroup>[];
  FuriganaGroup? groupPre = null;
  bool? isKanaPre = null;
  for (final c in term.split('')) {
    final codePoint = (c.codeUnitAt(0));
    final isKana = isCodePointKana(codePoint);
    if (isKana == isKanaPre) {
      groupPre = (
        isKana: groupPre!.isKana,
        text: groupPre.text + c,
        textNormalized: groupPre.textNormalized
      );
    } else {
      groupPre = (isKana: isKana, text: c, textNormalized: null);
      groups.add(groupPre);
      isKanaPre = isKana;
    }
  }
  groups.map((group) => group.isKana
      ? (
          isKana: group.isKana,
          text: group.text,
          textNormalized: convertHiraganaToKatakana(group.text)
        )
      : group);
  // for (final group in groups) {
  //   if (group.isKana) {
  //     group.textNormalized = convertKatakanaToHiragana(group.text);
  //   }
  // }

  final readingNormalized = convertKatakanaToHiragana(reading);
  final segments = segmentizeFurigana(reading, readingNormalized, groups, 0);
  if (segments != null) {
    return segments;
  }

  // Fallback
  return [createFuriganaSegment(term, reading)];
}

List<FuriganaSegment> distributeFuriganaInflected(
    String term, String reading, String source) {
  final termNormalized = convertKatakanaToHiragana(term);
  final readingNormalized = convertKatakanaToHiragana(reading);
  final sourceNormalized = convertKatakanaToHiragana(source);

  String mainText = term;
  int stemLength = getStemLength(termNormalized, sourceNormalized);

  // Check if source is derived from the reading instead of the term
  final readingStemLength = getStemLength(readingNormalized, sourceNormalized);
  if (readingStemLength > 0 && readingStemLength >= stemLength) {
    mainText = reading;
    stemLength = readingStemLength;
    reading =
        '${source.substring(0, stemLength)}${reading.substring(stemLength)}';
  }

  final segments = <FuriganaSegment>[];
  if (stemLength > 0) {
    mainText =
        '${source.substring(0, stemLength)}${mainText.substring(stemLength)}';
    final segments2 = distributeFurigana(mainText, reading);
    int consumed = 0;
    for (final segment in segments2) {
      final (:text, :reading) = segment;
      final start = consumed;
      consumed += text.length;
      if (consumed < stemLength) {
        segments.add(segment);
      } else if (consumed == stemLength) {
        segments.add(segment);
        break;
      } else {
        if (start < stemLength) {
          segments.add(
              createFuriganaSegment(mainText.substring(start, stemLength), ''));
        }
        break;
      }
    }
  }

  if (stemLength < source.length) {
    final remainder = source.substring(stemLength);
    final segmentCount = segments.length;
    if (segmentCount > 0 && segments[segmentCount - 1].reading.length == 0) {
      // Append to the last segment if it has an empty reading
      final lastSegment = segments[segmentCount - 1];
      segments[segmentCount - 1] =
          (text: lastSegment.text + remainder, reading: lastSegment.reading);
      // segments[segmentCount - 1].text += remainder;
    } else {
      // Otherwise, create a new segment
      segments.add(createFuriganaSegment(remainder, ''));
    }
  }

  return segments;
}

// Miscellaneous

bool isEmphaticCodePoint(int codePoint) {
  return (
      codePoint == HIRAGANA_SMALL_TSU_CODE_POINT ||
      codePoint == KATAKANA_SMALL_TSU_CODE_POINT ||
      codePoint == KANA_PROLONGED_SOUND_MARK_CODE_POINT
  );
}

String collapseEmphaticSequences(String text, bool fullCollapse) {
  int left = 0;
  while (left < text.length && isEmphaticCodePoint((text.codeUnitAt(left)))) {
    ++left;
  }
  int right = text.length - 1;
  while (right >= 0 && isEmphaticCodePoint((text.codeUnitAt(right)))) {
    --right;
  }
  // Whole string is emphatic
  if (left > right) {
    return text;
  }

  final leadingEmphatics = text.substring(0, left);
  final trailingEmphatics = text.substring(right + 1);
  String middle = '';
  int currentCollapsedCodePoint = -1;

  for (int i = left; i <= right; ++i) {
    final char = text[i];
    final codePoint = (char.codeUnitAt(0));
    if (isEmphaticCodePoint(codePoint)) {
      if (currentCollapsedCodePoint != codePoint) {
        currentCollapsedCodePoint = codePoint;
        if (!fullCollapse) {
          middle += char;
          continue;
        }
      }
    } else {
      currentCollapsedCodePoint = -1;
      middle += char;
    }
  }

  return leadingEmphatics + middle + trailingEmphatics;
}
