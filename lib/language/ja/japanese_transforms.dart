import 'package:muchuu/language/cjk_util.dart';

import '../language_engine.dart';
import 'japanese_preprocessors.dart';

// Essentially everything here is ported from yomitan
// https://github.com/yomidevs/yomitan/blob/master/ext/js/language/ja/japanese-text-preprocessors.js

const shimauEnglishDescription =
    '1. Shows a sense of regret/surprise when you did have volition in doing something, but it turned out to be bad to do.\n' +
        '2. Shows perfective/punctual achievement. This shows that an action has been completed.\n' +
        '3. Shows unintentional action–“accidentally”.\n';

const passiveEnglishDescription =
    '1. Indicates an action received from an action performer.\n' +
        '2. Expresses respect for the subject of action performer.\n';

const ikuVerbs = ['いく', '行く', '逝く', '往く'];
const godanUSpecialVerbs = [
  'こう',
  'とう',
  '請う',
  '乞う',
  '恋う',
  '問う',
  '訪う',
  '宣う',
  '曰う',
  '給う',
  '賜う',
  '揺蕩う'
];
const fuVerbTeConjugations = [
  ['のたまう', 'のたもう'],
  ['たまう', 'たもう'],
  ['たゆたう', 'たゆとう'],
];

List<TransformRule> irregularVerbSuffixInflections(
    String suffix,
    List<TransformConditionTag> conditionsBeforeDeinflection,
    List<TransformConditionTag> conditionsAfterDeinflection) {
  List<TransformRule> inflections = [];
  for (var verb in ikuVerbs) {
    inflections.add(SuffixInflection('${verb[0]}っ${suffix}', verb,
        conditionsBeforeDeinflection, conditionsAfterDeinflection));
  }
  for (var verb in godanUSpecialVerbs) {
    inflections.add(SuffixInflection('${verb}${suffix}', verb,
        conditionsBeforeDeinflection, conditionsAfterDeinflection));
  }
  for (var [verb, teRoot] in fuVerbTeConjugations) {
    inflections.add(SuffixInflection('${teRoot}${suffix}', verb,
        conditionsBeforeDeinflection, conditionsAfterDeinflection));
  }
  return inflections;
}

class JapaneseEngine extends LanguageEngine {
  @override
  String getLanguageCode() => 'ja';

  // TODO: Do these examples in the description
  @override
  List<TextPreprocessor> textPreprocessors = [
    BasicTextPreprocessor(
      name: 'Convert half width Japanese characters to full width',
      description: 'ﾖﾐﾁｬﾝ → ヨミチャン',
      process: (String rawText, bool option) => option ? convertHalfWidthKanaToFullWidth(rawText) : rawText,
    ),
    BasicTextPreprocessor(
      name: 'Convert alphabetic characters to hiragana',
      description: 'yomichan → よみちゃん',
      process: (String rawText, bool option) => option ? convertAlphabeticToKana(rawText) : rawText,
    ),
    BasicTextPreprocessor(
      name: 'Normalize combining characters',
      description: 'ド → ド (U+30C8 U+3099 → U+30C9)',
      process: (String rawText, bool option) => option ? normalizeCombiningCharacters(rawText) : rawText,
    ),
    BasicTextPreprocessor(
      name: 'Normalize CJK compatibility characters',
      description: '㌀ → アパート',
      process: (String rawText, bool option) => option ? normalizeCJKCompatibilityCharacters(rawText) : rawText,
    ),
    BasicTextPreprocessor(
      name: 'Normalize radical characters',
      description: '⼀ → 一 (U+2F00 → U+4E00)',
      process: (String rawText, bool option) => option ? normalizeRadicals(rawText) : rawText,
    ),
    BidirectionalTextPreprocessor(
      name: 'Convert between alphabetic width variants',
      description: 'ｙｏｍｉｔａｎ → yomitan and vice versa',
      process: (String rawText, BidirectionalProcessorOption option) => switch (option) {
        BidirectionalProcessorOption.off => rawText,
  BidirectionalProcessorOption.forward => convertFullWidthAlphanumericToNormal(rawText),
  BidirectionalProcessorOption.inverse => convertAlphanumericToFullWidth(rawText),
  },
    ),
    BidirectionalTextPreprocessor(
      name: 'Convert between hiragana and katakana',
      description: 'hiragana -> katakana and vice versa',
      process: (String rawText, BidirectionalProcessorOption option) => switch (option) {
        BidirectionalProcessorOption.off => rawText,
        BidirectionalProcessorOption.forward => convertHiraganaToKatakana(rawText),
        BidirectionalProcessorOption.inverse => convertKatakanaToHiragana(rawText),
      },
    ),
    TextPreprocessor<(bool, bool)>(
      name: 'Collapse emphatic character sequences',
      description: 'すっっごーーい → すっごーい / すごい',
      options: [(false, false), (true, false), (true, true)],
      process: (String rawText, (bool, bool) option) {
        final (bool collapseEmphatic, bool collapseEmphaticFull) = option;
        if (collapseEmphatic) {
          rawText = collapseEmphaticSequences(rawText, collapseEmphaticFull);
        }
        return rawText;
      }
    ),
  ];

  @override
  bool isLookupWorthy(String text) => isStringPartiallyJapanese(text);

  @override
  LanguageTransformsDescriptor transformsDescriptor =
      LanguageTransformsDescriptor(
    language: 'ja',
    conditions: {
      'v': TransformCondition(
        name: 'Verb',
        i18n: [
          TransformConditionI18n(
            language: 'ja',
            name: '動詞',
          ),
        ],
        isDictionaryForm: false,
        subConditions: ['v1', 'v5', 'vk', 'vs', 'vz'],
      ),
      'v1': TransformCondition(
        name: 'Ichidan verb',
        i18n: [
          TransformConditionI18n(
            language: 'ja',
            name: '一段動詞',
          ),
        ],
        isDictionaryForm: true,
        subConditions: ['v1d', 'v1p'],
      ),
      'v1d': TransformCondition(
        name: 'Ichidan verb, dictionary form',
        i18n: [
          TransformConditionI18n(
            language: 'ja',
            name: '一段動詞、終止形',
          ),
        ],
        isDictionaryForm: false,
      ),
      'v1p': TransformCondition(
        name: 'Ichidan verb, progressive or perfect form',
        i18n: [
          TransformConditionI18n(
            language: 'ja',
            name: '一段動詞、～てる・でる',
          ),
        ],
        isDictionaryForm: false,
      ),
      'v5': TransformCondition(
        name: 'Godan verb',
        i18n: [
          TransformConditionI18n(
            language: 'ja',
            name: '五段動詞',
          ),
        ],
        isDictionaryForm: true,
        subConditions: ['v5d', 'v5s'],
      ),
      'v5d': TransformCondition(
        name: 'Godan verb, dictionary form',
        i18n: [
          TransformConditionI18n(
            language: 'ja',
            name: '五段動詞、終止形',
          ),
        ],
        isDictionaryForm: false,
      ),
      'v5s': TransformCondition(
        name: 'Godan verb, short causative form',
        i18n: [
          TransformConditionI18n(
            language: 'ja',
            name: '五段動詞、～す・さす',
          ),
        ],
        isDictionaryForm: false,
        subConditions: ['v5ss', 'v5sp'],
      ),
      'v5ss': TransformCondition(
        name:
            'Godan verb, short causative form having さす ending (cannot conjugate with passive form)',
        i18n: [
          TransformConditionI18n(
            language: 'ja',
            name: '五段動詞、～さす',
          ),
        ],
        isDictionaryForm: false,
      ),
      'v5sp': TransformCondition(
        name:
            'Godan verb, short causative form not having さす ending (can conjugate with passive form)',
        i18n: [
          TransformConditionI18n(
            language: 'ja',
            name: '五段動詞、～す',
          ),
        ],
        isDictionaryForm: false,
      ),
      'vk': TransformCondition(
        name: 'Kuru verb',
        i18n: [
          TransformConditionI18n(
            language: 'ja',
            name: '来る動詞',
          ),
        ],
        isDictionaryForm: true,
      ),
      'vs': TransformCondition(
        name: 'Suru verb',
        i18n: [
          TransformConditionI18n(
            language: 'ja',
            name: 'する動詞',
          ),
        ],
        isDictionaryForm: true,
      ),
      'vz': TransformCondition(
        name: 'Zuru verb',
        i18n: [
          TransformConditionI18n(
            language: 'ja',
            name: 'ずる動詞',
          ),
        ],
        isDictionaryForm: true,
      ),
      'adj-i': TransformCondition(
        name: 'Adjective with i ending',
        i18n: [
          TransformConditionI18n(
            language: 'ja',
            name: '形容詞',
          ),
        ],
        isDictionaryForm: true,
      ),
      '-ます': TransformCondition(
        name: 'Polite -ます ending',
        isDictionaryForm: false,
      ),
      '-ません': TransformCondition(
        name: 'Polite negative -ません ending',
        isDictionaryForm: false,
      ),
      '-て': TransformCondition(
        name: 'Intermediate -て endings for progressive or perfect tense',
        isDictionaryForm: false,
      ),
      '-ば': TransformCondition(
        name: 'Intermediate -ば endings for conditional contraction',
        isDictionaryForm: false,
      ),
      '-く': TransformCondition(
        name: 'Intermediate -く endings for adverbs',
        isDictionaryForm: false,
      ),
      '-た': TransformCondition(
        name: '-た form ending',
        isDictionaryForm: false,
      ),
      '-ん': TransformCondition(
        name: '-ん negative ending',
        isDictionaryForm: false,
      ),
      '-なさい': TransformCondition(
        name: 'Intermediate -なさい ending (polite imperative)',
        isDictionaryForm: false,
      ),
      '-ゃ': TransformCondition(
        name: 'Intermediate -や ending (conditional contraction)',
        isDictionaryForm: false,
      ),
    },
    transforms: {
      '-ば': TransformDescriptor(
        name: '-ば',
        description:
            '1. Conditional form; shows that the previous stated condition\'s establishment is the condition for the latter stated condition to occur.\n' +
                '2. Shows a trigger for a latter stated perception or judgment.\n' +
                'Usage: Attach ば to the hypothetical form (仮定形) of verbs and i-adjectives.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～ば',
          ),
        ],
        rules: [
          SuffixInflection('ければ', 'い', ['-ば'], ['adj-i']),
          SuffixInflection('えば', 'う', ['-ば'], ['v5']),
          SuffixInflection('けば', 'く', ['-ば'], ['v5']),
          SuffixInflection('げば', 'ぐ', ['-ば'], ['v5']),
          SuffixInflection('せば', 'す', ['-ば'], ['v5']),
          SuffixInflection('てば', 'つ', ['-ば'], ['v5']),
          SuffixInflection('ねば', 'ぬ', ['-ば'], ['v5']),
          SuffixInflection('べば', 'ぶ', ['-ば'], ['v5']),
          SuffixInflection('めば', 'む', ['-ば'], ['v5']),
          SuffixInflection('れば', 'る', ['-ば'], ['v1', 'v5', 'vk', 'vs', 'vz']),
          SuffixInflection('れば', '', ['-ば'], ['-ます']),
        ],
      ),
      '-ゃ': TransformDescriptor(
        name: '-ゃ',
        description: 'Contraction of -ば.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～ゃ',
            description: '「～ば」の短縮',
          ),
        ],
        rules: [
          SuffixInflection('けりゃ', 'ければ', ['-ゃ'], ['-ば']),
          SuffixInflection('きゃ', 'ければ', ['-ゃ'], ['-ば']),
          SuffixInflection('や', 'えば', ['-ゃ'], ['-ば']),
          SuffixInflection('きゃ', 'けば', ['-ゃ'], ['-ば']),
          SuffixInflection('ぎゃ', 'げば', ['-ゃ'], ['-ば']),
          SuffixInflection('しゃ', 'せば', ['-ゃ'], ['-ば']),
          SuffixInflection('ちゃ', 'てば', ['-ゃ'], ['-ば']),
          SuffixInflection('にゃ', 'ねば', ['-ゃ'], ['-ば']),
          SuffixInflection('びゃ', 'べば', ['-ゃ'], ['-ば']),
          SuffixInflection('みゃ', 'めば', ['-ゃ'], ['-ば']),
          SuffixInflection('りゃ', 'れば', ['-ゃ'], ['-ば']),
        ],
      ),
      '-ちゃ': TransformDescriptor(
        name: '-ちゃ',
        description: 'Contraction of ～ては.\n' +
            '1. Explains how something always happens under the condition that it marks.\n' +
            '2. Expresses the repetition (of a series of) actions.\n' +
            '3. Indicates a hypothetical situation in which the speaker gives a (negative) evaluation about the other party\'s intentions.\n' +
            '4. Used in "Must Not" patterns like ～てはいけない.\n' +
            'Usage: Attach は after the て-form of verbs, contract ては into ちゃ.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～ちゃ',
            description: '「～ては」の短縮',
          ),
        ],
        rules: [
          SuffixInflection('ちゃ', 'る', ['v5'], ['v1']),
          SuffixInflection('いじゃ', 'ぐ', ['v5'], ['v5']),
          SuffixInflection('いちゃ', 'く', ['v5'], ['v5']),
          SuffixInflection('しちゃ', 'す', ['v5'], ['v5']),
          SuffixInflection('っちゃ', 'う', ['v5'], ['v5']),
          SuffixInflection('っちゃ', 'く', ['v5'], ['v5']),
          SuffixInflection('っちゃ', 'つ', ['v5'], ['v5']),
          SuffixInflection('っちゃ', 'る', ['v5'], ['v5']),
          SuffixInflection('んじゃ', 'ぬ', ['v5'], ['v5']),
          SuffixInflection('んじゃ', 'ぶ', ['v5'], ['v5']),
          SuffixInflection('んじゃ', 'む', ['v5'], ['v5']),
          SuffixInflection('じちゃ', 'ずる', ['v5'], ['vz']),
          SuffixInflection('しちゃ', 'する', ['v5'], ['vs']),
          SuffixInflection('為ちゃ', '為る', ['v5'], ['vs']),
          SuffixInflection('きちゃ', 'くる', ['v5'], ['vk']),
          SuffixInflection('来ちゃ', '来る', ['v5'], ['vk']),
          SuffixInflection('來ちゃ', '來る', ['v5'], ['vk']),
        ],
      ),
      '-ちゃう': TransformDescriptor(
        name: '-ちゃう',
        description: 'Contraction of -しまう.\n' +
            shimauEnglishDescription +
            'Usage: Attach しまう after the て-form of verbs, contract てしまう into ちゃう.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～ちゃう',
            description: '「～てしまう」のややくだけた口頭語的表現',
          ),
        ],
        rules: [
          SuffixInflection('ちゃう', 'る', ['v5'], ['v1']),
          SuffixInflection('いじゃう', 'ぐ', ['v5'], ['v5']),
          SuffixInflection('いちゃう', 'く', ['v5'], ['v5']),
          SuffixInflection('しちゃう', 'す', ['v5'], ['v5']),
          SuffixInflection('っちゃう', 'う', ['v5'], ['v5']),
          SuffixInflection('っちゃう', 'く', ['v5'], ['v5']),
          SuffixInflection('っちゃう', 'つ', ['v5'], ['v5']),
          SuffixInflection('っちゃう', 'る', ['v5'], ['v5']),
          SuffixInflection('んじゃう', 'ぬ', ['v5'], ['v5']),
          SuffixInflection('んじゃう', 'ぶ', ['v5'], ['v5']),
          SuffixInflection('んじゃう', 'む', ['v5'], ['v5']),
          SuffixInflection('じちゃう', 'ずる', ['v5'], ['vz']),
          SuffixInflection('しちゃう', 'する', ['v5'], ['vs']),
          SuffixInflection('為ちゃう', '為る', ['v5'], ['vs']),
          SuffixInflection('きちゃう', 'くる', ['v5'], ['vk']),
          SuffixInflection('来ちゃう', '来る', ['v5'], ['vk']),
          SuffixInflection('來ちゃう', '來る', ['v5'], ['vk']),
        ],
      ),
      '-ちまう': TransformDescriptor(
        name: '-ちまう',
        description: 'Contraction of -しまう.\n' +
            shimauEnglishDescription +
            'Usage: Attach しまう after the て-form of verbs, contract てしまう into ちまう.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～ちまう',
            description: '「～てしまう」の音変化',
          ),
        ],
        rules: [
          SuffixInflection('ちまう', 'る', ['v5'], ['v1']),
          SuffixInflection('いじまう', 'ぐ', ['v5'], ['v5']),
          SuffixInflection('いちまう', 'く', ['v5'], ['v5']),
          SuffixInflection('しちまう', 'す', ['v5'], ['v5']),
          SuffixInflection('っちまう', 'う', ['v5'], ['v5']),
          SuffixInflection('っちまう', 'く', ['v5'], ['v5']),
          SuffixInflection('っちまう', 'つ', ['v5'], ['v5']),
          SuffixInflection('っちまう', 'る', ['v5'], ['v5']),
          SuffixInflection('んじまう', 'ぬ', ['v5'], ['v5']),
          SuffixInflection('んじまう', 'ぶ', ['v5'], ['v5']),
          SuffixInflection('んじまう', 'む', ['v5'], ['v5']),
          SuffixInflection('じちまう', 'ずる', ['v5'], ['vz']),
          SuffixInflection('しちまう', 'する', ['v5'], ['vs']),
          SuffixInflection('為ちまう', '為る', ['v5'], ['vs']),
          SuffixInflection('きちまう', 'くる', ['v5'], ['vk']),
          SuffixInflection('来ちまう', '来る', ['v5'], ['vk']),
          SuffixInflection('來ちまう', '來る', ['v5'], ['vk']),
        ],
      ),
      '-しまう': TransformDescriptor(
        name: '-しまう',
        description: shimauEnglishDescription +
            'Usage: Attach しまう after the て-form of verbs.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～しまう',
            description:
                'その動作がすっかり終わる、その状態が完成することを表す。終わったことを強調したり、不本意である、困ったことになった、などの気持ちを添えたりすることもある。',
          ),
        ],
        rules: [
          SuffixInflection('てしまう', 'て', ['v5'], ['-て']),
          SuffixInflection('でしまう', 'で', ['v5'], ['-て']),
        ],
      ),
      '-なさい': TransformDescriptor(
        name: '-なさい',
        description: 'Polite imperative suffix.\n' +
            'Usage: Attach なさい after the continuative form (連用形) of verbs.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～なさい',
            description: '動詞「なさる」の命令形',
          ),
        ],
        rules: [
          SuffixInflection('なさい', 'る', ['-なさい'], ['v1']),
          SuffixInflection('いなさい', 'う', ['-なさい'], ['v5']),
          SuffixInflection('きなさい', 'く', ['-なさい'], ['v5']),
          SuffixInflection('ぎなさい', 'ぐ', ['-なさい'], ['v5']),
          SuffixInflection('しなさい', 'す', ['-なさい'], ['v5']),
          SuffixInflection('ちなさい', 'つ', ['-なさい'], ['v5']),
          SuffixInflection('になさい', 'ぬ', ['-なさい'], ['v5']),
          SuffixInflection('びなさい', 'ぶ', ['-なさい'], ['v5']),
          SuffixInflection('みなさい', 'む', ['-なさい'], ['v5']),
          SuffixInflection('りなさい', 'る', ['-なさい'], ['v5']),
          SuffixInflection('じなさい', 'ずる', ['-なさい'], ['vz']),
          SuffixInflection('しなさい', 'する', ['-なさい'], ['vs']),
          SuffixInflection('為なさい', '為る', ['-なさい'], ['vs']),
          SuffixInflection('きなさい', 'くる', ['-なさい'], ['vk']),
          SuffixInflection('来なさい', '来る', ['-なさい'], ['vk']),
          SuffixInflection('來なさい', '來る', ['-なさい'], ['vk']),
        ],
      ),
      '-そう': TransformDescriptor(
        name: '-そう',
        description: 'Appearing that; looking like.\n' +
            'Usage: Attach そう to the continuative form (連用形) of verbs, or to the stem of adjectives.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～そう',
            description: 'そういう様子だ、そうなる様子だということ、すなわち様態を表す助動詞。',
          ),
        ],
        rules: [
          SuffixInflection('そう', 'い', [], ['adj-i']),
          SuffixInflection('そう', 'る', [], ['v1']),
          SuffixInflection('いそう', 'う', [], ['v5']),
          SuffixInflection('きそう', 'く', [], ['v5']),
          SuffixInflection('ぎそう', 'ぐ', [], ['v5']),
          SuffixInflection('しそう', 'す', [], ['v5']),
          SuffixInflection('ちそう', 'つ', [], ['v5']),
          SuffixInflection('にそう', 'ぬ', [], ['v5']),
          SuffixInflection('びそう', 'ぶ', [], ['v5']),
          SuffixInflection('みそう', 'む', [], ['v5']),
          SuffixInflection('りそう', 'る', [], ['v5']),
          SuffixInflection('じそう', 'ずる', [], ['vz']),
          SuffixInflection('しそう', 'する', [], ['vs']),
          SuffixInflection('為そう', '為る', [], ['vs']),
          SuffixInflection('きそう', 'くる', [], ['vk']),
          SuffixInflection('来そう', '来る', [], ['vk']),
          SuffixInflection('來そう', '來る', [], ['vk']),
        ],
      ),
      '-すぎる': TransformDescriptor(
        name: '-すぎる',
        description:
            'Shows something "is too..." or someone is doing something "too much".\n' +
                'Usage: Attach すぎる to the continuative form (連用形) of verbs, or to the stem of adjectives.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～すぎる',
            description: '程度や限度を超える',
          ),
        ],
        rules: [
          SuffixInflection('すぎる', 'い', ['v1'], ['adj-i']),
          SuffixInflection('すぎる', 'る', ['v1'], ['v1']),
          SuffixInflection('いすぎる', 'う', ['v1'], ['v5']),
          SuffixInflection('きすぎる', 'く', ['v1'], ['v5']),
          SuffixInflection('ぎすぎる', 'ぐ', ['v1'], ['v5']),
          SuffixInflection('しすぎる', 'す', ['v1'], ['v5']),
          SuffixInflection('ちすぎる', 'つ', ['v1'], ['v5']),
          SuffixInflection('にすぎる', 'ぬ', ['v1'], ['v5']),
          SuffixInflection('びすぎる', 'ぶ', ['v1'], ['v5']),
          SuffixInflection('みすぎる', 'む', ['v1'], ['v5']),
          SuffixInflection('りすぎる', 'る', ['v1'], ['v5']),
          SuffixInflection('じすぎる', 'ずる', ['v1'], ['vz']),
          SuffixInflection('しすぎる', 'する', ['v1'], ['vs']),
          SuffixInflection('為すぎる', '為る', ['v1'], ['vs']),
          SuffixInflection('きすぎる', 'くる', ['v1'], ['vk']),
          SuffixInflection('来すぎる', '来る', ['v1'], ['vk']),
          SuffixInflection('來すぎる', '來る', ['v1'], ['vk']),
        ],
      ),
      '-過ぎる': TransformDescriptor(
        name: '-過ぎる',
        description:
            'Shows something "is too..." or someone is doing something "too much".\n' +
                'Usage: Attach 過ぎる to the continuative form (連用形) of verbs, or to the stem of adjectives.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～過ぎる',
            description: '程度や限度を超える',
          ),
        ],
        rules: [
          SuffixInflection('過ぎる', 'い', ['v1'], ['adj-i']),
          SuffixInflection('過ぎる', 'る', ['v1'], ['v1']),
          SuffixInflection('い過ぎる', 'う', ['v1'], ['v5']),
          SuffixInflection('き過ぎる', 'く', ['v1'], ['v5']),
          SuffixInflection('ぎ過ぎる', 'ぐ', ['v1'], ['v5']),
          SuffixInflection('し過ぎる', 'す', ['v1'], ['v5']),
          SuffixInflection('ち過ぎる', 'つ', ['v1'], ['v5']),
          SuffixInflection('に過ぎる', 'ぬ', ['v1'], ['v5']),
          SuffixInflection('び過ぎる', 'ぶ', ['v1'], ['v5']),
          SuffixInflection('み過ぎる', 'む', ['v1'], ['v5']),
          SuffixInflection('り過ぎる', 'る', ['v1'], ['v5']),
          SuffixInflection('じ過ぎる', 'ずる', ['v1'], ['vz']),
          SuffixInflection('し過ぎる', 'する', ['v1'], ['vs']),
          SuffixInflection('為過ぎる', '為る', ['v1'], ['vs']),
          SuffixInflection('き過ぎる', 'くる', ['v1'], ['vk']),
          SuffixInflection('来過ぎる', '来る', ['v1'], ['vk']),
          SuffixInflection('來過ぎる', '來る', ['v1'], ['vk']),
        ],
      ),
      '-たい': TransformDescriptor(
        name: '-たい',
        description: '1. Expresses the feeling of desire or hope.\n' +
            '2. Used in ...たいと思います, an indirect way of saying what the speaker intends to do.\n' +
            'Usage: Attach たい to the continuative form (連用形) of verbs. たい itself conjugates as i-adjective.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～たい',
            description: 'することをのぞんでいる、という、希望や願望の気持ちをあらわす。',
          ),
        ],
        rules: [
          SuffixInflection('たい', 'る', ['adj-i'], ['v1']),
          SuffixInflection('いたい', 'う', ['adj-i'], ['v5']),
          SuffixInflection('きたい', 'く', ['adj-i'], ['v5']),
          SuffixInflection('ぎたい', 'ぐ', ['adj-i'], ['v5']),
          SuffixInflection('したい', 'す', ['adj-i'], ['v5']),
          SuffixInflection('ちたい', 'つ', ['adj-i'], ['v5']),
          SuffixInflection('にたい', 'ぬ', ['adj-i'], ['v5']),
          SuffixInflection('びたい', 'ぶ', ['adj-i'], ['v5']),
          SuffixInflection('みたい', 'む', ['adj-i'], ['v5']),
          SuffixInflection('りたい', 'る', ['adj-i'], ['v5']),
          SuffixInflection('じたい', 'ずる', ['adj-i'], ['vz']),
          SuffixInflection('したい', 'する', ['adj-i'], ['vs']),
          SuffixInflection('為たい', '為る', ['adj-i'], ['vs']),
          SuffixInflection('きたい', 'くる', ['adj-i'], ['vk']),
          SuffixInflection('来たい', '来る', ['adj-i'], ['vk']),
          SuffixInflection('來たい', '來る', ['adj-i'], ['vk']),
        ],
      ),
      '-たら': TransformDescriptor(
        name: '-たら',
        description:
            '1. Denotes the latter stated event is a continuation of the previous stated event.\n' +
                '2. Assumes that a matter has been completed or concluded.\n' +
                'Usage: Attach たら to the continuative form (連用形) of verbs after euphonic change form, かったら to the stem of i-adjectives.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～たら',
            description: '仮定をあらわす・…すると・したあとに',
          ),
        ],
        rules: [
          SuffixInflection('かったら', 'い', [], ['adj-i']),
          SuffixInflection('たら', 'る', [], ['v1']),
          SuffixInflection('いたら', 'く', [], ['v5']),
          SuffixInflection('いだら', 'ぐ', [], ['v5']),
          SuffixInflection('したら', 'す', [], ['v5']),
          SuffixInflection('ったら', 'う', [], ['v5']),
          SuffixInflection('ったら', 'つ', [], ['v5']),
          SuffixInflection('ったら', 'る', [], ['v5']),
          SuffixInflection('んだら', 'ぬ', [], ['v5']),
          SuffixInflection('んだら', 'ぶ', [], ['v5']),
          SuffixInflection('んだら', 'む', [], ['v5']),
          SuffixInflection('じたら', 'ずる', [], ['vz']),
          SuffixInflection('したら', 'する', [], ['vs']),
          SuffixInflection('為たら', '為る', [], ['vs']),
          SuffixInflection('きたら', 'くる', [], ['vk']),
          SuffixInflection('来たら', '来る', [], ['vk']),
          SuffixInflection('來たら', '來る', [], ['vk']),
          ...irregularVerbSuffixInflections('たら', [], ['v5']),
          SuffixInflection('ましたら', 'ます', [], ['-ます']),
        ],
      ),
      '-たり': TransformDescriptor(
        name: '-たり',
        description:
            '1. Shows two actions occurring back and forth (when used with two verbs).\n' +
                '2. Shows examples of actions and states (when used with multiple verbs and adjectives).\n' +
                'Usage: Attach たり to the continuative form (連用形) of verbs after euphonic change form, かったり to the stem of i-adjectives',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～たり',
            description: 'ある動作を例示的にあげることを表わす。',
          ),
        ],
        rules: [
          SuffixInflection('かったり', 'い', [], ['adj-i']),
          SuffixInflection('たり', 'る', [], ['v1']),
          SuffixInflection('いたり', 'く', [], ['v5']),
          SuffixInflection('いだり', 'ぐ', [], ['v5']),
          SuffixInflection('したり', 'す', [], ['v5']),
          SuffixInflection('ったり', 'う', [], ['v5']),
          SuffixInflection('ったり', 'つ', [], ['v5']),
          SuffixInflection('ったり', 'る', [], ['v5']),
          SuffixInflection('んだり', 'ぬ', [], ['v5']),
          SuffixInflection('んだり', 'ぶ', [], ['v5']),
          SuffixInflection('んだり', 'む', [], ['v5']),
          SuffixInflection('じたり', 'ずる', [], ['vz']),
          SuffixInflection('したり', 'する', [], ['vs']),
          SuffixInflection('為たり', '為る', [], ['vs']),
          SuffixInflection('きたり', 'くる', [], ['vk']),
          SuffixInflection('来たり', '来る', [], ['vk']),
          SuffixInflection('來たり', '來る', [], ['vk']),
          ...irregularVerbSuffixInflections('たり', [], ['v5']),
        ],
      ),
      '-て': TransformDescriptor(
        name: '-て',
        description: 'て-form.\n' +
            'It has a myriad of meanings. Primarily, it is a conjunctive particle that connects two clauses together.\n' +
            'Usage: Attach て to the continuative form (連用形) of verbs after euphonic change form, くて to the stem of i-adjectives.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～て',
          ),
        ],
        rules: [
          SuffixInflection('くて', 'い', ['-て'], ['adj-i']),
          SuffixInflection('て', 'る', ['-て'], ['v1']),
          SuffixInflection('いて', 'く', ['-て'], ['v5']),
          SuffixInflection('いで', 'ぐ', ['-て'], ['v5']),
          SuffixInflection('して', 'す', ['-て'], ['v5']),
          SuffixInflection('って', 'う', ['-て'], ['v5']),
          SuffixInflection('って', 'つ', ['-て'], ['v5']),
          SuffixInflection('って', 'る', ['-て'], ['v5']),
          SuffixInflection('んで', 'ぬ', ['-て'], ['v5']),
          SuffixInflection('んで', 'ぶ', ['-て'], ['v5']),
          SuffixInflection('んで', 'む', ['-て'], ['v5']),
          SuffixInflection('じて', 'ずる', ['-て'], ['vz']),
          SuffixInflection('して', 'する', ['-て'], ['vs']),
          SuffixInflection('為て', '為る', ['-て'], ['vs']),
          SuffixInflection('きて', 'くる', ['-て'], ['vk']),
          SuffixInflection('来て', '来る', ['-て'], ['vk']),
          SuffixInflection('來て', '來る', ['-て'], ['vk']),
          ...irregularVerbSuffixInflections('て', ['-て'], ['v5']),
          SuffixInflection('まして', 'ます', [], ['-ます']),
        ],
      ),
      '-ず': TransformDescriptor(
        name: '-ず',
        description: '1. Negative form of verbs.\n' +
            '2. Continuative form (連用形) of the particle ぬ (nu).\n' +
            'Usage: Attach ず to the irrealis form (未然形) of verbs.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～ず',
            description: '～ない',
          ),
        ],
        rules: [
          SuffixInflection('ず', 'る', [], ['v1']),
          SuffixInflection('かず', 'く', [], ['v5']),
          SuffixInflection('がず', 'ぐ', [], ['v5']),
          SuffixInflection('さず', 'す', [], ['v5']),
          SuffixInflection('たず', 'つ', [], ['v5']),
          SuffixInflection('なず', 'ぬ', [], ['v5']),
          SuffixInflection('ばず', 'ぶ', [], ['v5']),
          SuffixInflection('まず', 'む', [], ['v5']),
          SuffixInflection('らず', 'る', [], ['v5']),
          SuffixInflection('わず', 'う', [], ['v5']),
          SuffixInflection('ぜず', 'ずる', [], ['vz']),
          SuffixInflection('せず', 'する', [], ['vs']),
          SuffixInflection('為ず', '為る', [], ['vs']),
          SuffixInflection('こず', 'くる', [], ['vk']),
          SuffixInflection('来ず', '来る', [], ['vk']),
          SuffixInflection('來ず', '來る', [], ['vk']),
        ],
      ),
      '-ぬ': TransformDescriptor(
        name: '-ぬ',
        description: 'Negative form of verbs.\n' +
            'Usage: Attach ぬ to the irrealis form (未然形) of verbs.\n' +
            'する becomes せぬ',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～ぬ',
            description: '～ない',
          ),
        ],
        rules: [
          SuffixInflection('ぬ', 'る', [], ['v1']),
          SuffixInflection('かぬ', 'く', [], ['v5']),
          SuffixInflection('がぬ', 'ぐ', [], ['v5']),
          SuffixInflection('さぬ', 'す', [], ['v5']),
          SuffixInflection('たぬ', 'つ', [], ['v5']),
          SuffixInflection('なぬ', 'ぬ', [], ['v5']),
          SuffixInflection('ばぬ', 'ぶ', [], ['v5']),
          SuffixInflection('まぬ', 'む', [], ['v5']),
          SuffixInflection('らぬ', 'る', [], ['v5']),
          SuffixInflection('わぬ', 'う', [], ['v5']),
          SuffixInflection('ぜぬ', 'ずる', [], ['vz']),
          SuffixInflection('せぬ', 'する', [], ['vs']),
          SuffixInflection('為ぬ', '為る', [], ['vs']),
          SuffixInflection('こぬ', 'くる', [], ['vk']),
          SuffixInflection('来ぬ', '来る', [], ['vk']),
          SuffixInflection('來ぬ', '來る', [], ['vk']),
        ],
      ),
      '-ん': TransformDescriptor(
        name: '-ん',
        description: 'Negative form of verbs; a sound change of ぬ.\n' +
            'Usage: Attach ん to the irrealis form (未然形) of verbs.\n' +
            'する becomes せん',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～ん',
            description: '～ない',
          ),
        ],
        rules: [
          SuffixInflection('ん', 'る', ['-ん'], ['v1']),
          SuffixInflection('かん', 'く', ['-ん'], ['v5']),
          SuffixInflection('がん', 'ぐ', ['-ん'], ['v5']),
          SuffixInflection('さん', 'す', ['-ん'], ['v5']),
          SuffixInflection('たん', 'つ', ['-ん'], ['v5']),
          SuffixInflection('なん', 'ぬ', ['-ん'], ['v5']),
          SuffixInflection('ばん', 'ぶ', ['-ん'], ['v5']),
          SuffixInflection('まん', 'む', ['-ん'], ['v5']),
          SuffixInflection('らん', 'る', ['-ん'], ['v5']),
          SuffixInflection('わん', 'う', ['-ん'], ['v5']),
          SuffixInflection('ぜん', 'ずる', ['-ん'], ['vz']),
          SuffixInflection('せん', 'する', ['-ん'], ['vs']),
          SuffixInflection('為ん', '為る', ['-ん'], ['vs']),
          SuffixInflection('こん', 'くる', ['-ん'], ['vk']),
          SuffixInflection('来ん', '来る', ['-ん'], ['vk']),
          SuffixInflection('來ん', '來る', ['-ん'], ['vk']),
        ],
      ),
      '-んばかり': TransformDescriptor(
        name: '-んばかり',
        description:
            'Shows an action or condition is on the verge of occurring, or an excessive/extreme degree.\n' +
                'Usage: Attach んばかり to the irrealis form (未然形) of verbs.\n' +
                'する becomes せんばかり',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～んばかり',
            description: '今にもそうなりそうな、しかし辛うじてそうなっていないようなさまを指す表現',
          ),
        ],
        rules: [
          SuffixInflection('んばかり', 'る', [], ['v1']),
          SuffixInflection('かんばかり', 'く', [], ['v5']),
          SuffixInflection('がんばかり', 'ぐ', [], ['v5']),
          SuffixInflection('さんばかり', 'す', [], ['v5']),
          SuffixInflection('たんばかり', 'つ', [], ['v5']),
          SuffixInflection('なんばかり', 'ぬ', [], ['v5']),
          SuffixInflection('ばんばかり', 'ぶ', [], ['v5']),
          SuffixInflection('まんばかり', 'む', [], ['v5']),
          SuffixInflection('らんばかり', 'る', [], ['v5']),
          SuffixInflection('わんばかり', 'う', [], ['v5']),
          SuffixInflection('ぜんばかり', 'ずる', [], ['vz']),
          SuffixInflection('せんばかり', 'する', [], ['vs']),
          SuffixInflection('為んばかり', '為る', [], ['vs']),
          SuffixInflection('こんばかり', 'くる', [], ['vk']),
          SuffixInflection('来んばかり', '来る', [], ['vk']),
          SuffixInflection('來んばかり', '來る', [], ['vk']),
        ],
      ),
      '-んとする': TransformDescriptor(
        name: '-んとする',
        description: '1. Shows the speaker\'s will or intention.\n' +
            '2. Shows an action or condition is on the verge of occurring.\n' +
            'Usage: Attach んとする to the irrealis form (未然形) of verbs.\n' +
            'する becomes せんとする',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～んとする',
            description: '…しようとする、…しようとしている',
          ),
        ],
        rules: [
          SuffixInflection('んとする', 'る', ['vs'], ['v1']),
          SuffixInflection('かんとする', 'く', ['vs'], ['v5']),
          SuffixInflection('がんとする', 'ぐ', ['vs'], ['v5']),
          SuffixInflection('さんとする', 'す', ['vs'], ['v5']),
          SuffixInflection('たんとする', 'つ', ['vs'], ['v5']),
          SuffixInflection('なんとする', 'ぬ', ['vs'], ['v5']),
          SuffixInflection('ばんとする', 'ぶ', ['vs'], ['v5']),
          SuffixInflection('まんとする', 'む', ['vs'], ['v5']),
          SuffixInflection('らんとする', 'る', ['vs'], ['v5']),
          SuffixInflection('わんとする', 'う', ['vs'], ['v5']),
          SuffixInflection('ぜんとする', 'ずる', ['vs'], ['vz']),
          SuffixInflection('せんとする', 'する', ['vs'], ['vs']),
          SuffixInflection('為んとする', '為る', ['vs'], ['vs']),
          SuffixInflection('こんとする', 'くる', ['vs'], ['vk']),
          SuffixInflection('来んとする', '来る', ['vs'], ['vk']),
          SuffixInflection('來んとする', '來る', ['vs'], ['vk']),
        ],
      ),
      '-む': TransformDescriptor(
        name: '-む',
        description: 'Archaic.\n' +
            '1. Shows an inference of a certain matter.\n' +
            '2. Shows speaker\'s intention.\n' +
            'Usage: Attach む to the irrealis form (未然形) of verbs.\n' +
            'する becomes せむ',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～む',
            description: '…だろう',
          ),
        ],
        rules: [
          SuffixInflection('む', 'る', [], ['v1']),
          SuffixInflection('かむ', 'く', [], ['v5']),
          SuffixInflection('がむ', 'ぐ', [], ['v5']),
          SuffixInflection('さむ', 'す', [], ['v5']),
          SuffixInflection('たむ', 'つ', [], ['v5']),
          SuffixInflection('なむ', 'ぬ', [], ['v5']),
          SuffixInflection('ばむ', 'ぶ', [], ['v5']),
          SuffixInflection('まむ', 'む', [], ['v5']),
          SuffixInflection('らむ', 'る', [], ['v5']),
          SuffixInflection('わむ', 'う', [], ['v5']),
          SuffixInflection('ぜむ', 'ずる', [], ['vz']),
          SuffixInflection('せむ', 'する', [], ['vs']),
          SuffixInflection('為む', '為る', [], ['vs']),
          SuffixInflection('こむ', 'くる', [], ['vk']),
          SuffixInflection('来む', '来る', [], ['vk']),
          SuffixInflection('來む', '來る', [], ['vk']),
        ],
      ),
      '-ざる': TransformDescriptor(
        name: '-ざる',
        description: 'Negative form of verbs.\n' +
            'Usage: Attach ざる to the irrealis form (未然形) of verbs.\n' +
            'する becomes せざる',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～ざる',
            description: '…ない…',
          ),
        ],
        rules: [
          SuffixInflection('ざる', 'る', [], ['v1']),
          SuffixInflection('かざる', 'く', [], ['v5']),
          SuffixInflection('がざる', 'ぐ', [], ['v5']),
          SuffixInflection('さざる', 'す', [], ['v5']),
          SuffixInflection('たざる', 'つ', [], ['v5']),
          SuffixInflection('なざる', 'ぬ', [], ['v5']),
          SuffixInflection('ばざる', 'ぶ', [], ['v5']),
          SuffixInflection('まざる', 'む', [], ['v5']),
          SuffixInflection('らざる', 'る', [], ['v5']),
          SuffixInflection('わざる', 'う', [], ['v5']),
          SuffixInflection('ぜざる', 'ずる', [], ['vz']),
          SuffixInflection('せざる', 'する', [], ['vs']),
          SuffixInflection('為ざる', '為る', [], ['vs']),
          SuffixInflection('こざる', 'くる', [], ['vk']),
          SuffixInflection('来ざる', '来る', [], ['vk']),
          SuffixInflection('來ざる', '來る', [], ['vk']),
        ],
      ),
      '-ねば': TransformDescriptor(
        name: '-ねば',
        description: '1. Shows a hypothetical negation; if not ...\n' +
            '2. Shows a must. Used with or without ならぬ.\n' +
            'Usage: Attach ねば to the irrealis form (未然形) of verbs.\n' +
            'する becomes せねば',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～ねば',
            description: 'もし…ないなら。…なければならない。',
          ),
        ],
        rules: [
          SuffixInflection('ねば', 'る', ['-ば'], ['v1']),
          SuffixInflection('かねば', 'く', ['-ば'], ['v5']),
          SuffixInflection('がねば', 'ぐ', ['-ば'], ['v5']),
          SuffixInflection('さねば', 'す', ['-ば'], ['v5']),
          SuffixInflection('たねば', 'つ', ['-ば'], ['v5']),
          SuffixInflection('なねば', 'ぬ', ['-ば'], ['v5']),
          SuffixInflection('ばねば', 'ぶ', ['-ば'], ['v5']),
          SuffixInflection('まねば', 'む', ['-ば'], ['v5']),
          SuffixInflection('らねば', 'る', ['-ば'], ['v5']),
          SuffixInflection('わねば', 'う', ['-ば'], ['v5']),
          SuffixInflection('ぜねば', 'ずる', ['-ば'], ['vz']),
          SuffixInflection('せねば', 'する', ['-ば'], ['vs']),
          SuffixInflection('為ねば', '為る', ['-ば'], ['vs']),
          SuffixInflection('こねば', 'くる', ['-ば'], ['vk']),
          SuffixInflection('来ねば', '来る', ['-ば'], ['vk']),
          SuffixInflection('來ねば', '來る', ['-ば'], ['vk']),
        ],
      ),
      '-く': TransformDescriptor(
        name: '-く',
        description: 'Adverbial form of i-adjectives.\n',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～く',
            description: '〔形容詞で〕用言へ続く。例、「大きく育つ」の「大きく」。',
          ),
        ],
        rules: [
          SuffixInflection('く', 'い', ['-く'], ['adj-i']),
        ],
      ),
      'causative': TransformDescriptor(
        name: 'causative',
        description: 'Describes the intention to make someone do something.\n' +
            'Usage: Attach させる to the irrealis form (未然形) of ichidan verbs and くる.\n' +
            'Attach せる to the irrealis form (未然形) of godan verbs and する.\n' +
            'It itself conjugates as an ichidan verb.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～せる・させる',
            description: 'だれかにある行為をさせる意を表わす時の言い方。例、「行かせる」の「せる」。',
          ),
        ],
        rules: [
          SuffixInflection('させる', 'る', ['v1'], ['v1']),
          SuffixInflection('かせる', 'く', ['v1'], ['v5']),
          SuffixInflection('がせる', 'ぐ', ['v1'], ['v5']),
          SuffixInflection('させる', 'す', ['v1'], ['v5']),
          SuffixInflection('たせる', 'つ', ['v1'], ['v5']),
          SuffixInflection('なせる', 'ぬ', ['v1'], ['v5']),
          SuffixInflection('ばせる', 'ぶ', ['v1'], ['v5']),
          SuffixInflection('ませる', 'む', ['v1'], ['v5']),
          SuffixInflection('らせる', 'る', ['v1'], ['v5']),
          SuffixInflection('わせる', 'う', ['v1'], ['v5']),
          SuffixInflection('じさせる', 'ずる', ['v1'], ['vz']),
          SuffixInflection('ぜさせる', 'ずる', ['v1'], ['vz']),
          SuffixInflection('させる', 'する', ['v1'], ['vs']),
          SuffixInflection('為せる', '為る', ['v1'], ['vs']),
          SuffixInflection('せさせる', 'する', ['v1'], ['vs']),
          SuffixInflection('為させる', '為る', ['v1'], ['vs']),
          SuffixInflection('こさせる', 'くる', ['v1'], ['vk']),
          SuffixInflection('来させる', '来る', ['v1'], ['vk']),
          SuffixInflection('來させる', '來る', ['v1'], ['vk']),
        ],
      ),
      'short causative': TransformDescriptor(
        name: 'short causative',
        description: 'Contraction of the causative form.\n' +
            'Describes the intention to make someone do something.\n' +
            'Usage: Attach す to the irrealis form (未然形) of godan verbs.\n' +
            'Attach さす to the dictionary form (終止形) of ichidan verbs.\n' +
            'する becomes さす, くる becomes こさす.\n' +
            'It itself conjugates as an godan verb.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～す・さす',
            description: 'だれかにある行為をさせる意を表わす時の言い方。例、「食べさす」の「さす」。',
          ),
        ],
        rules: [
          SuffixInflection('さす', 'る', ['v5ss'], ['v1']),
          SuffixInflection('かす', 'く', ['v5sp'], ['v5']),
          SuffixInflection('がす', 'ぐ', ['v5sp'], ['v5']),
          SuffixInflection('さす', 'す', ['v5ss'], ['v5']),
          SuffixInflection('たす', 'つ', ['v5sp'], ['v5']),
          SuffixInflection('なす', 'ぬ', ['v5sp'], ['v5']),
          SuffixInflection('ばす', 'ぶ', ['v5sp'], ['v5']),
          SuffixInflection('ます', 'む', ['v5sp'], ['v5']),
          SuffixInflection('らす', 'る', ['v5sp'], ['v5']),
          SuffixInflection('わす', 'う', ['v5sp'], ['v5']),
          SuffixInflection('じさす', 'ずる', ['v5ss'], ['vz']),
          SuffixInflection('ぜさす', 'ずる', ['v5ss'], ['vz']),
          SuffixInflection('さす', 'する', ['v5ss'], ['vs']),
          SuffixInflection('為す', '為る', ['v5ss'], ['vs']),
          SuffixInflection('こさす', 'くる', ['v5ss'], ['vk']),
          SuffixInflection('来さす', '来る', ['v5ss'], ['vk']),
          SuffixInflection('來さす', '來る', ['v5ss'], ['vk']),
        ],
      ),
      'imperative': TransformDescriptor(
        name: 'imperative',
        description: '1. To give orders.\n' +
            '2. (As あれ) Represents the fact that it will never change no matter the circumstances.\n' +
            '3. Express a feeling of hope.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '命令形',
            description: '命令の意味を表わすときの形。例、「行け」。',
          ),
        ],
        rules: [
          SuffixInflection('ろ', 'る', [], ['v1']),
          SuffixInflection('よ', 'る', [], ['v1']),
          SuffixInflection('え', 'う', [], ['v5']),
          SuffixInflection('け', 'く', [], ['v5']),
          SuffixInflection('げ', 'ぐ', [], ['v5']),
          SuffixInflection('せ', 'す', [], ['v5']),
          SuffixInflection('て', 'つ', [], ['v5']),
          SuffixInflection('ね', 'ぬ', [], ['v5']),
          SuffixInflection('べ', 'ぶ', [], ['v5']),
          SuffixInflection('め', 'む', [], ['v5']),
          SuffixInflection('れ', 'る', [], ['v5']),
          SuffixInflection('じろ', 'ずる', [], ['vz']),
          SuffixInflection('ぜよ', 'ずる', [], ['vz']),
          SuffixInflection('しろ', 'する', [], ['vs']),
          SuffixInflection('せよ', 'する', [], ['vs']),
          SuffixInflection('為ろ', '為る', [], ['vs']),
          SuffixInflection('為よ', '為る', [], ['vs']),
          SuffixInflection('こい', 'くる', [], ['vk']),
          SuffixInflection('来い', '来る', [], ['vk']),
          SuffixInflection('來い', '來る', [], ['vk']),
        ],
      ),
      'continuative': TransformDescriptor(
        name: 'continuative',
        description: 'Used to indicate actions that are (being) carried out.\n' +
            'Refers to 連用形, the part of the verb after conjugating with -ます and dropping ます.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '連用形',
            description: '〔動詞などで〕「ます」などに続く。例、「バスを降りて歩きます」の「降り」「歩き」。',
          ),
        ],
        rules: [
          SuffixInflection('い', 'いる', [], ['v1d']),
          SuffixInflection('え', 'える', [], ['v1d']),
          SuffixInflection('き', 'きる', [], ['v1d']),
          SuffixInflection('ぎ', 'ぎる', [], ['v1d']),
          SuffixInflection('け', 'ける', [], ['v1d']),
          SuffixInflection('げ', 'げる', [], ['v1d']),
          SuffixInflection('じ', 'じる', [], ['v1d']),
          SuffixInflection('せ', 'せる', [], ['v1d']),
          SuffixInflection('ぜ', 'ぜる', [], ['v1d']),
          SuffixInflection('ち', 'ちる', [], ['v1d']),
          SuffixInflection('て', 'てる', [], ['v1d']),
          SuffixInflection('で', 'でる', [], ['v1d']),
          SuffixInflection('に', 'にる', [], ['v1d']),
          SuffixInflection('ね', 'ねる', [], ['v1d']),
          SuffixInflection('ひ', 'ひる', [], ['v1d']),
          SuffixInflection('び', 'びる', [], ['v1d']),
          SuffixInflection('へ', 'へる', [], ['v1d']),
          SuffixInflection('べ', 'べる', [], ['v1d']),
          SuffixInflection('み', 'みる', [], ['v1d']),
          SuffixInflection('め', 'める', [], ['v1d']),
          SuffixInflection('り', 'りる', [], ['v1d']),
          SuffixInflection('れ', 'れる', [], ['v1d']),
          SuffixInflection('い', 'う', [], ['v5']),
          SuffixInflection('き', 'く', [], ['v5']),
          SuffixInflection('ぎ', 'ぐ', [], ['v5']),
          SuffixInflection('し', 'す', [], ['v5']),
          SuffixInflection('ち', 'つ', [], ['v5']),
          SuffixInflection('に', 'ぬ', [], ['v5']),
          SuffixInflection('び', 'ぶ', [], ['v5']),
          SuffixInflection('み', 'む', [], ['v5']),
          SuffixInflection('り', 'る', [], ['v5']),
          SuffixInflection('き', 'くる', [], ['vk']),
          SuffixInflection('し', 'する', [], ['vs']),
          SuffixInflection('来', '来る', [], ['vk']),
          SuffixInflection('來', '來る', [], ['vk']),
        ],
      ),
      'negative': TransformDescriptor(
        name: 'negative',
        description: '1. Negative form of verbs.\n' +
            '2. Expresses a feeling of solicitation to the other party.\n' +
            'Usage: Attach ない to the irrealis form (未然形) of verbs, くない to the stem of i-adjectives. ない itself conjugates as i-adjective. ます becomes ません.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～ない',
            description: 'その動作・作用・状態の成立を否定することを表わす。',
          ),
        ],
        rules: [
          SuffixInflection('くない', 'い', ['adj-i'], ['adj-i']),
          SuffixInflection('ない', 'る', ['adj-i'], ['v1']),
          SuffixInflection('かない', 'く', ['adj-i'], ['v5']),
          SuffixInflection('がない', 'ぐ', ['adj-i'], ['v5']),
          SuffixInflection('さない', 'す', ['adj-i'], ['v5']),
          SuffixInflection('たない', 'つ', ['adj-i'], ['v5']),
          SuffixInflection('なない', 'ぬ', ['adj-i'], ['v5']),
          SuffixInflection('ばない', 'ぶ', ['adj-i'], ['v5']),
          SuffixInflection('まない', 'む', ['adj-i'], ['v5']),
          SuffixInflection('らない', 'る', ['adj-i'], ['v5']),
          SuffixInflection('わない', 'う', ['adj-i'], ['v5']),
          SuffixInflection('じない', 'ずる', ['adj-i'], ['vz']),
          SuffixInflection('しない', 'する', ['adj-i'], ['vs']),
          SuffixInflection('為ない', '為る', ['adj-i'], ['vs']),
          SuffixInflection('こない', 'くる', ['adj-i'], ['vk']),
          SuffixInflection('来ない', '来る', ['adj-i'], ['vk']),
          SuffixInflection('來ない', '來る', ['adj-i'], ['vk']),
          SuffixInflection('ません', 'ます', ['-ません'], ['-ます']),
        ],
      ),
      '-さ': TransformDescriptor(
        name: '-さ',
        description:
            'Nominalizing suffix of i-adjectives indicating nature, state, mind or degree.\n' +
                'Usage: Attach さ to the stem of i-adjectives.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～さ',
            description: 'こと。程度。',
          ),
        ],
        rules: [
          SuffixInflection('さ', 'い', [], ['adj-i']),
        ],
      ),
      'passive': TransformDescriptor(
        name: 'passive',
        description: passiveEnglishDescription +
            'Usage: Attach れる to the irrealis form (未然形) of godan verbs.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～れる',
          ),
        ],
        rules: [
          SuffixInflection('かれる', 'く', ['v1'], ['v5']),
          SuffixInflection('がれる', 'ぐ', ['v1'], ['v5']),
          SuffixInflection('される', 'す', ['v1'], ['v5d', 'v5sp']),
          SuffixInflection('たれる', 'つ', ['v1'], ['v5']),
          SuffixInflection('なれる', 'ぬ', ['v1'], ['v5']),
          SuffixInflection('ばれる', 'ぶ', ['v1'], ['v5']),
          SuffixInflection('まれる', 'む', ['v1'], ['v5']),
          SuffixInflection('われる', 'う', ['v1'], ['v5']),
          SuffixInflection('られる', 'る', ['v1'], ['v5']),
          SuffixInflection('じされる', 'ずる', ['v1'], ['vz']),
          SuffixInflection('ぜされる', 'ずる', ['v1'], ['vz']),
          SuffixInflection('される', 'する', ['v1'], ['vs']),
          SuffixInflection('為れる', '為る', ['v1'], ['vs']),
          SuffixInflection('こられる', 'くる', ['v1'], ['vk']),
          SuffixInflection('来られる', '来る', ['v1'], ['vk']),
          SuffixInflection('來られる', '來る', ['v1'], ['vk']),
        ],
      ),
      '-た': TransformDescriptor(
        name: '-た',
        description: '1. Indicates a reality that has happened in the past.\n' +
            '2. Indicates the completion of an action.\n' +
            '3. Indicates the confirmation of a matter.\n' +
            '4. Indicates the speaker\'s confidence that the action will definitely be fulfilled.\n' +
            '5. Indicates the events that occur before the main clause are represented as relative past.\n' +
            '6. Indicates a mild imperative/command.\n' +
            'Usage: Attach た to the continuative form (連用形) of verbs after euphonic change form, かった to the stem of i-adjectives.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～た',
          ),
        ],
        rules: [
          SuffixInflection('かった', 'い', ['-た'], ['adj-i']),
          SuffixInflection('た', 'る', ['-た'], ['v1']),
          SuffixInflection('いた', 'く', ['-た'], ['v5']),
          SuffixInflection('いだ', 'ぐ', ['-た'], ['v5']),
          SuffixInflection('した', 'す', ['-た'], ['v5']),
          SuffixInflection('った', 'う', ['-た'], ['v5']),
          SuffixInflection('った', 'つ', ['-た'], ['v5']),
          SuffixInflection('った', 'る', ['-た'], ['v5']),
          SuffixInflection('んだ', 'ぬ', ['-た'], ['v5']),
          SuffixInflection('んだ', 'ぶ', ['-た'], ['v5']),
          SuffixInflection('んだ', 'む', ['-た'], ['v5']),
          SuffixInflection('じた', 'ずる', ['-た'], ['vz']),
          SuffixInflection('した', 'する', ['-た'], ['vs']),
          SuffixInflection('為た', '為る', ['-た'], ['vs']),
          SuffixInflection('きた', 'くる', ['-た'], ['vk']),
          SuffixInflection('来た', '来る', ['-た'], ['vk']),
          SuffixInflection('來た', '來る', ['-た'], ['vk']),
          ...irregularVerbSuffixInflections('た', ['-た'], ['v5']),
          SuffixInflection('ました', 'ます', ['-た'], ['-ます']),
          SuffixInflection('でした', '', ['-た'], ['-ません']),
          SuffixInflection('かった', '', ['-た'], ['-ません', '-ん']),
        ],
      ),
      '-ます': TransformDescriptor(
        name: '-ます',
        description: 'Polite conjugation of verbs and adjectives.\n' +
            'Usage: Attach ます to the continuative form (連用形) of verbs.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～ます',
          ),
        ],
        rules: [
          SuffixInflection('ます', 'る', ['-ます'], ['v1']),
          SuffixInflection('います', 'う', ['-ます'], ['v5d']),
          SuffixInflection('きます', 'く', ['-ます'], ['v5d']),
          SuffixInflection('ぎます', 'ぐ', ['-ます'], ['v5d']),
          SuffixInflection('します', 'す', ['-ます'], ['v5d', 'v5s']),
          SuffixInflection('ちます', 'つ', ['-ます'], ['v5d']),
          SuffixInflection('にます', 'ぬ', ['-ます'], ['v5d']),
          SuffixInflection('びます', 'ぶ', ['-ます'], ['v5d']),
          SuffixInflection('みます', 'む', ['-ます'], ['v5d']),
          SuffixInflection('ります', 'る', ['-ます'], ['v5d']),
          SuffixInflection('じます', 'ずる', ['-ます'], ['vz']),
          SuffixInflection('します', 'する', ['-ます'], ['vs']),
          SuffixInflection('為ます', '為る', ['-ます'], ['vs']),
          SuffixInflection('きます', 'くる', ['-ます'], ['vk']),
          SuffixInflection('来ます', '来る', ['-ます'], ['vk']),
          SuffixInflection('來ます', '來る', ['-ます'], ['vk']),
          SuffixInflection('くあります', 'い', ['-ます'], ['adj-i']),
        ],
      ),
      'potential': TransformDescriptor(
        name: 'potential',
        description:
            'Indicates a state of being (naturally) capable of doing an action.\n' +
                'Usage: Attach (ら)れる to the irrealis form (未然形) of ichidan verbs.\n' +
                'Attach る to the imperative form (命令形) of godan verbs.\n' +
                'する becomes できる, くる becomes こ(ら)れる',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～(ら)れる',
          ),
        ],
        rules: [
          SuffixInflection('れる', 'る', ['v1'], ['v1', 'v5d']),
          SuffixInflection('える', 'う', ['v1'], ['v5d']),
          SuffixInflection('ける', 'く', ['v1'], ['v5d']),
          SuffixInflection('げる', 'ぐ', ['v1'], ['v5d']),
          SuffixInflection('せる', 'す', ['v1'], ['v5d']),
          SuffixInflection('てる', 'つ', ['v1'], ['v5d']),
          SuffixInflection('ねる', 'ぬ', ['v1'], ['v5d']),
          SuffixInflection('べる', 'ぶ', ['v1'], ['v5d']),
          SuffixInflection('める', 'む', ['v1'], ['v5d']),
          SuffixInflection('できる', 'する', ['v1'], ['vs']),
          SuffixInflection('出来る', 'する', ['v1'], ['vs']),
          SuffixInflection('これる', 'くる', ['v1'], ['vk']),
          SuffixInflection('来れる', '来る', ['v1'], ['vk']),
          SuffixInflection('來れる', '來る', ['v1'], ['vk']),
        ],
      ),
      'potential or passive': TransformDescriptor(
        name: 'potential or passive',
        description: passiveEnglishDescription +
            '3. Indicates a state of being (naturally) capable of doing an action.\n' +
            'Usage: Attach られる to the irrealis form (未然形) of ichidan verbs.\n' +
            'する becomes せられる, くる becomes こられる',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～られる',
          ),
        ],
        rules: [
          SuffixInflection('られる', 'る', ['v1'], ['v1']),
          SuffixInflection('ざれる', 'ずる', ['v1'], ['vz']),
          SuffixInflection('ぜられる', 'ずる', ['v1'], ['vz']),
          SuffixInflection('せられる', 'する', ['v1'], ['vs']),
          SuffixInflection('為られる', '為る', ['v1'], ['vs']),
          SuffixInflection('こられる', 'くる', ['v1'], ['vk']),
          SuffixInflection('来られる', '来る', ['v1'], ['vk']),
          SuffixInflection('來られる', '來る', ['v1'], ['vk']),
        ],
      ),
      'volitional': TransformDescriptor(
        name: 'volitional',
        description: '1. Expresses speaker\'s will or intention.\n' +
            '2. Expresses an invitation to the other party.\n' +
            '3. (Used in …ようとする) Indicates being on the verge of initiating an action or transforming a state.\n' +
            '4. Indicates an inference of a matter.\n' +
            'Usage: Attach よう to the irrealis form (未然形) of ichidan verbs.\n' +
            'Attach う to the irrealis form (未然形) of godan verbs after -o euphonic change form.\n' +
            'Attach かろう to the stem of i-adjectives (4th meaning only).',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～う・よう',
            description: '主体の意志を表わす',
          ),
        ],
        rules: [
          SuffixInflection('よう', 'る', [], ['v1']),
          SuffixInflection('おう', 'う', [], ['v5']),
          SuffixInflection('こう', 'く', [], ['v5']),
          SuffixInflection('ごう', 'ぐ', [], ['v5']),
          SuffixInflection('そう', 'す', [], ['v5']),
          SuffixInflection('とう', 'つ', [], ['v5']),
          SuffixInflection('のう', 'ぬ', [], ['v5']),
          SuffixInflection('ぼう', 'ぶ', [], ['v5']),
          SuffixInflection('もう', 'む', [], ['v5']),
          SuffixInflection('ろう', 'る', [], ['v5']),
          SuffixInflection('じよう', 'ずる', [], ['vz']),
          SuffixInflection('しよう', 'する', [], ['vs']),
          SuffixInflection('為よう', '為る', [], ['vs']),
          SuffixInflection('こよう', 'くる', [], ['vk']),
          SuffixInflection('来よう', '来る', [], ['vk']),
          SuffixInflection('來よう', '來る', [], ['vk']),
          SuffixInflection('ましょう', 'ます', [], ['-ます']),
          SuffixInflection('かろう', 'い', [], ['adj-i']),
        ],
      ),
      'volitional slang': TransformDescriptor(
        name: 'volitional slang',
        description: 'Contraction of volitional form + か\n' +
            '1. Expresses speaker\'s will or intention.\n' +
            '2. Expresses an invitation to the other party.\n' +
            'Usage: Replace final う with っ of volitional form then add か.\n' +
            'For example: 行こうか -> 行こっか.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～っか・よっか',
            description: '「うか・ようか」の短縮',
          ),
        ],
        rules: [
          SuffixInflection('よっか', 'る', [], ['v1']),
          SuffixInflection('おっか', 'う', [], ['v5']),
          SuffixInflection('こっか', 'く', [], ['v5']),
          SuffixInflection('ごっか', 'ぐ', [], ['v5']),
          SuffixInflection('そっか', 'す', [], ['v5']),
          SuffixInflection('とっか', 'つ', [], ['v5']),
          SuffixInflection('のっか', 'ぬ', [], ['v5']),
          SuffixInflection('ぼっか', 'ぶ', [], ['v5']),
          SuffixInflection('もっか', 'む', [], ['v5']),
          SuffixInflection('ろっか', 'る', [], ['v5']),
          SuffixInflection('じよっか', 'ずる', [], ['vz']),
          SuffixInflection('しよっか', 'する', [], ['vs']),
          SuffixInflection('為よっか', '為る', [], ['vs']),
          SuffixInflection('こよっか', 'くる', [], ['vk']),
          SuffixInflection('来よっか', '来る', [], ['vk']),
          SuffixInflection('來よっか', '來る', [], ['vk']),
          SuffixInflection('ましょっか', 'ます', [], ['-ます']),
        ],
      ),
      '-まい': TransformDescriptor(
        name: '-まい',
        description: 'Negative volitional form of verbs.\n' +
            '1. Expresses speaker\'s assumption that something is likely not true.\n' +
            '2. Expresses speaker\'s will or intention not to do something.\n' +
            'Usage: Attach まい to the dictionary form (終止形) of verbs.\n' +
            'Attach まい to the irrealis form (未然形) of ichidan verbs.\n' +
            'する becomes しまい, くる becomes こまい',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～まい',
            description: '1. 打うち消けしの推量すいりょう 「～ないだろう」と想像する\n' +
                '2. 打うち消けしの意志いし「～ないつもりだ」という気持ち',
          ),
        ],
        rules: [
          SuffixInflection('まい', '', [], ['v']),
          SuffixInflection('まい', 'る', [], ['v1']),
          SuffixInflection('じまい', 'ずる', [], ['vz']),
          SuffixInflection('しまい', 'する', [], ['vs']),
          SuffixInflection('為まい', '為る', [], ['vs']),
          SuffixInflection('こまい', 'くる', [], ['vk']),
          SuffixInflection('来まい', '来る', [], ['vk']),
          SuffixInflection('來まい', '來る', [], ['vk']),
          SuffixInflection('まい', '', [], ['-ます']),
        ],
      ),
      '-おく': TransformDescriptor(
        name: '-おく',
        description:
            'To do certain things in advance in preparation (or in anticipation) of latter needs.\n' +
                'Usage: Attach おく to the て-form of verbs.\n' +
                'Attach でおく after ない negative form of verbs.\n' +
                'Contracts to とく・どく in speech.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～おく',
          ),
        ],
        rules: [
          SuffixInflection('ておく', 'て', ['v5'], ['-て']),
          SuffixInflection('でおく', 'で', ['v5'], ['-て']),
          SuffixInflection('とく', 'て', ['v5'], ['-て']),
          SuffixInflection('どく', 'で', ['v5'], ['-て']),
          SuffixInflection('ないでおく', 'ない', ['v5'], ['adj-i']),
          SuffixInflection('ないどく', 'ない', ['v5'], ['adj-i']),
        ],
      ),
      '-いる': TransformDescriptor(
        name: '-いる',
        description: '1. Indicates an action continues or progresses to a point in time.\n' +
            '2. Indicates an action is completed and remains as is.\n' +
            '3. Indicates a state or condition that can be taken to be the result of undergoing some change.\n' +
            'Usage: Attach いる to the て-form of verbs. い can be dropped in speech.\n' +
            'Attach でいる after ない negative form of verbs.\n' +
            '(Slang) Attach おる to the て-form of verbs. Contracts to とる・でる in speech.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～いる',
          ),
        ],
        rules: [
          SuffixInflection('ている', 'て', ['v1'], ['-て']),
          SuffixInflection('ておる', 'て', ['v5'], ['-て']),
          SuffixInflection('てる', 'て', ['v1p'], ['-て']),
          SuffixInflection('でいる', 'で', ['v1'], ['-て']),
          SuffixInflection('でおる', 'で', ['v5'], ['-て']),
          SuffixInflection('でる', 'で', ['v1p'], ['-て']),
          SuffixInflection('とる', 'て', ['v5'], ['-て']),
          SuffixInflection('ないでいる', 'ない', ['v1'], ['adj-i']),
        ],
      ),
      '-き': TransformDescriptor(
        name: '-き',
        description:
            'Attributive form (連体形) of i-adjectives. An archaic form that remains in modern Japanese.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～き',
            description: '連体形',
          ),
        ],
        rules: [
          SuffixInflection('き', 'い', [], ['adj-i']),
        ],
      ),
      '-げ': TransformDescriptor(
        name: '-げ',
        description:
            'Describes a person\'s appearance. Shows feelings of the person.\n' +
                'Usage: Attach げ or 気 to the stem of i-adjectives',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～げ',
            description: '…でありそうな様子。いかにも…らしいさま。',
          ),
        ],
        rules: [
          SuffixInflection('げ', 'い', [], ['adj-i']),
          SuffixInflection('気', 'い', [], ['adj-i']),
        ],
      ),
      '-がる': TransformDescriptor(
        name: '-がる',
        description:
            '1. Shows subject’s feelings contrast with what is thought/known about them.\n' +
                '2. Indicates subject\'s behavior (stands out).\n' +
                'Usage: Attach がる to the stem of i-adjectives. It itself conjugates as a godan verb.',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～がる',
            description: 'いかにもその状態にあるという印象を相手に与えるような言動をする。',
          ),
        ],
        rules: [
          SuffixInflection('がる', 'い', ['v5'], ['adj-i']),
        ],
      ),
      '-え': TransformDescriptor(
        name: '-え',
        description: 'Slang. A sound change of i-adjectives.\n' +
            'ai：やばい → やべぇ\n' +
            'ui：さむい → さみぃ/さめぇ\n' +
            'oi：すごい → すげぇ',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～え',
          ),
        ],
        rules: [
          SuffixInflection('ねえ', 'ない', [], ['adj-i']),
          SuffixInflection('めえ', 'むい', [], ['adj-i']),
          SuffixInflection('みい', 'むい', [], ['adj-i']),
          SuffixInflection('ちぇえ', 'つい', [], ['adj-i']),
          SuffixInflection('ちい', 'つい', [], ['adj-i']),
          SuffixInflection('せえ', 'すい', [], ['adj-i']),
          SuffixInflection('ええ', 'いい', [], ['adj-i']),
          SuffixInflection('ええ', 'わい', [], ['adj-i']),
          SuffixInflection('ええ', 'よい', [], ['adj-i']),
          SuffixInflection('いぇえ', 'よい', [], ['adj-i']),
          SuffixInflection('うぇえ', 'わい', [], ['adj-i']),
          SuffixInflection('けえ', 'かい', [], ['adj-i']),
          SuffixInflection('げえ', 'がい', [], ['adj-i']),
          SuffixInflection('げえ', 'ごい', [], ['adj-i']),
          SuffixInflection('せえ', 'さい', [], ['adj-i']),
          SuffixInflection('めえ', 'まい', [], ['adj-i']),
          SuffixInflection('ぜえ', 'ずい', [], ['adj-i']),
          SuffixInflection('っぜえ', 'ずい', [], ['adj-i']),
          SuffixInflection('れえ', 'らい', [], ['adj-i']),
          SuffixInflection('れえ', 'らい', [], ['adj-i']),
          SuffixInflection('ちぇえ', 'ちゃい', [], ['adj-i']),
          SuffixInflection('でえ', 'どい', [], ['adj-i']),
          SuffixInflection('れえ', 'れい', [], ['adj-i']),
          SuffixInflection('べえ', 'ばい', [], ['adj-i']),
          SuffixInflection('てえ', 'たい', [], ['adj-i']),
          SuffixInflection('ねぇ', 'ない', [], ['adj-i']),
          SuffixInflection('めぇ', 'むい', [], ['adj-i']),
          SuffixInflection('みぃ', 'むい', [], ['adj-i']),
          SuffixInflection('ちぃ', 'つい', [], ['adj-i']),
          SuffixInflection('せぇ', 'すい', [], ['adj-i']),
          SuffixInflection('けぇ', 'かい', [], ['adj-i']),
          SuffixInflection('げぇ', 'がい', [], ['adj-i']),
          SuffixInflection('げぇ', 'ごい', [], ['adj-i']),
          SuffixInflection('せぇ', 'さい', [], ['adj-i']),
          SuffixInflection('めぇ', 'まい', [], ['adj-i']),
          SuffixInflection('ぜぇ', 'ずい', [], ['adj-i']),
          SuffixInflection('っぜぇ', 'ずい', [], ['adj-i']),
          SuffixInflection('れぇ', 'らい', [], ['adj-i']),
          SuffixInflection('でぇ', 'どい', [], ['adj-i']),
          SuffixInflection('れぇ', 'れい', [], ['adj-i']),
          SuffixInflection('べぇ', 'ばい', [], ['adj-i']),
          SuffixInflection('てぇ', 'たい', [], ['adj-i']),
        ],
      ),
      'n-slang': TransformDescriptor(
        name: 'n-slang',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～んな',
          ),
        ],
        description:
            'Slang sound change of r-column syllables to n (when before an n-sound, usually の or な)',
        rules: [
          SuffixInflection('んなさい', 'りなさい', [], ['-なさい']),
          SuffixInflection('らんない', 'られない', ['adj-i'], ['adj-i']),
          SuffixInflection('んない', 'らない', ['adj-i'], ['adj-i']),
          SuffixInflection('んなきゃ', 'らなきゃ', [], ['-ゃ']),
          SuffixInflection('んなきゃ', 'れなきゃ', [], ['-ゃ']),
        ],
      ),
      'imperative negative slang': TransformDescriptor(
        name: 'imperative negative slang',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '～んな',
          ),
        ],
        rules: [
          SuffixInflection('んな', 'る', [], ['v']),
        ],
      ),
      'kansai-ben negative': TransformDescriptor(
        name: 'kansai-ben',
        description: 'Negative form of kansai-ben verbs',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '関西弁',
            description: '～ない (関西弁)',
          ),
        ],
        rules: [
          SuffixInflection('へん', 'ない', [], ['adj-i']),
          SuffixInflection('ひん', 'ない', [], ['adj-i']),
          SuffixInflection('せえへん', 'しない', [], ['adj-i']),
          SuffixInflection('へんかった', 'なかった', ['-た'], ['-た']),
          SuffixInflection('ひんかった', 'なかった', ['-た'], ['-た']),
          SuffixInflection('うてへん', 'ってない', [], ['adj-i']),
        ],
      ),
      'kansai-ben -て': TransformDescriptor(
        name: 'kansai-ben',
        description: '-て form of kansai-ben verbs',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '関西弁',
            description: '～て (関西弁)',
          ),
        ],
        rules: [
          SuffixInflection('うて', 'って', ['-て'], ['-て']),
          SuffixInflection('おうて', 'あって', ['-て'], ['-て']),
          SuffixInflection('こうて', 'かって', ['-て'], ['-て']),
          SuffixInflection('ごうて', 'がって', ['-て'], ['-て']),
          SuffixInflection('そうて', 'さって', ['-て'], ['-て']),
          SuffixInflection('ぞうて', 'ざって', ['-て'], ['-て']),
          SuffixInflection('とうて', 'たって', ['-て'], ['-て']),
          SuffixInflection('どうて', 'だって', ['-て'], ['-て']),
          SuffixInflection('のうて', 'なって', ['-て'], ['-て']),
          SuffixInflection('ほうて', 'はって', ['-て'], ['-て']),
          SuffixInflection('ぼうて', 'ばって', ['-て'], ['-て']),
          SuffixInflection('もうて', 'まって', ['-て'], ['-て']),
          SuffixInflection('ろうて', 'らって', ['-て'], ['-て']),
          SuffixInflection('ようて', 'やって', ['-て'], ['-て']),
          SuffixInflection('ゆうて', 'いって', ['-て'], ['-て']),
        ],
      ),
      'kansai-ben -た': TransformDescriptor(
        name: 'kansai-ben',
        description: '-た form of kansai-ben terms',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '関西弁',
            description: '～た (関西弁)',
          ),
        ],
        rules: [
          SuffixInflection('うた', 'った', ['-た'], ['-た']),
          SuffixInflection('おうた', 'あった', ['-た'], ['-た']),
          SuffixInflection('こうた', 'かった', ['-た'], ['-た']),
          SuffixInflection('ごうた', 'がった', ['-た'], ['-た']),
          SuffixInflection('そうた', 'さった', ['-た'], ['-た']),
          SuffixInflection('ぞうた', 'ざった', ['-た'], ['-た']),
          SuffixInflection('とうた', 'たった', ['-た'], ['-た']),
          SuffixInflection('どうた', 'だった', ['-た'], ['-た']),
          SuffixInflection('のうた', 'なった', ['-た'], ['-た']),
          SuffixInflection('ほうた', 'はった', ['-た'], ['-た']),
          SuffixInflection('ぼうた', 'ばった', ['-た'], ['-た']),
          SuffixInflection('もうた', 'まった', ['-た'], ['-た']),
          SuffixInflection('ろうた', 'らった', ['-た'], ['-た']),
          SuffixInflection('ようた', 'やった', ['-た'], ['-た']),
          SuffixInflection('ゆうた', 'いった', ['-た'], ['-た']),
        ],
      ),
      'kansai-ben -たら': TransformDescriptor(
        name: 'kansai-ben',
        description: '-たら form of kansai-ben terms',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '関西弁',
            description: '～たら (関西弁)',
          ),
        ],
        rules: [
          SuffixInflection('うたら', 'ったら', [], []),
          SuffixInflection('おうたら', 'あったら', [], []),
          SuffixInflection('こうたら', 'かったら', [], []),
          SuffixInflection('ごうたら', 'がったら', [], []),
          SuffixInflection('そうたら', 'さったら', [], []),
          SuffixInflection('ぞうたら', 'ざったら', [], []),
          SuffixInflection('とうたら', 'たったら', [], []),
          SuffixInflection('どうたら', 'だったら', [], []),
          SuffixInflection('のうたら', 'なったら', [], []),
          SuffixInflection('ほうたら', 'はったら', [], []),
          SuffixInflection('ぼうたら', 'ばったら', [], []),
          SuffixInflection('もうたら', 'まったら', [], []),
          SuffixInflection('ろうたら', 'らったら', [], []),
          SuffixInflection('ようたら', 'やったら', [], []),
          SuffixInflection('ゆうたら', 'いったら', [], []),
        ],
      ),
      'kansai-ben -たり': TransformDescriptor(
        name: 'kansai-ben',
        description: '-たり form of kansai-ben terms',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '関西弁',
            description: '～たり (関西弁)',
          ),
        ],
        rules: [
          SuffixInflection('うたり', 'ったり', [], []),
          SuffixInflection('おうたり', 'あったり', [], []),
          SuffixInflection('こうたり', 'かったり', [], []),
          SuffixInflection('ごうたり', 'がったり', [], []),
          SuffixInflection('そうたり', 'さったり', [], []),
          SuffixInflection('ぞうたり', 'ざったり', [], []),
          SuffixInflection('とうたり', 'たったり', [], []),
          SuffixInflection('どうたり', 'だったり', [], []),
          SuffixInflection('のうたり', 'なったり', [], []),
          SuffixInflection('ほうたり', 'はったり', [], []),
          SuffixInflection('ぼうたり', 'ばったり', [], []),
          SuffixInflection('もうたり', 'まったり', [], []),
          SuffixInflection('ろうたり', 'らったり', [], []),
          SuffixInflection('ようたり', 'やったり', [], []),
          SuffixInflection('ゆうたり', 'いったり', [], []),
        ],
      ),
      'kansai-ben -く': TransformDescriptor(
        name: 'kansai-ben',
        description: '-く stem of kansai-ben adjectives',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '関西弁',
            description: '連用形 (関西弁)',
          ),
        ],
        rules: [
          SuffixInflection('う', 'く', [], ['-く']),
          SuffixInflection('こう', 'かく', [], ['-く']),
          SuffixInflection('ごう', 'がく', [], ['-く']),
          SuffixInflection('そう', 'さく', [], ['-く']),
          SuffixInflection('とう', 'たく', [], ['-く']),
          SuffixInflection('のう', 'なく', [], ['-く']),
          SuffixInflection('ぼう', 'ばく', [], ['-く']),
          SuffixInflection('もう', 'まく', [], ['-く']),
          SuffixInflection('ろう', 'らく', [], ['-く']),
          SuffixInflection('よう', 'よく', [], ['-く']),
          SuffixInflection('しゅう', 'しく', [], ['-く']),
        ],
      ),
      'kansai-ben adjective -て': TransformDescriptor(
        name: 'kansai-ben',
        description: '-て form of kansai-ben adjectives',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '関西弁',
            description: '～て (関西弁)',
          ),
        ],
        rules: [
          SuffixInflection('うて', 'くて', ['-て'], ['-て']),
          SuffixInflection('こうて', 'かくて', ['-て'], ['-て']),
          SuffixInflection('ごうて', 'がくて', ['-て'], ['-て']),
          SuffixInflection('そうて', 'さくて', ['-て'], ['-て']),
          SuffixInflection('とうて', 'たくて', ['-て'], ['-て']),
          SuffixInflection('のうて', 'なくて', ['-て'], ['-て']),
          SuffixInflection('ぼうて', 'ばくて', ['-て'], ['-て']),
          SuffixInflection('もうて', 'まくて', ['-て'], ['-て']),
          SuffixInflection('ろうて', 'らくて', ['-て'], ['-て']),
          SuffixInflection('ようて', 'よくて', ['-て'], ['-て']),
          SuffixInflection('しゅうて', 'しくて', ['-て'], ['-て']),
        ],
      ),
      'kansai-ben adjective negative': TransformDescriptor(
        name: 'kansai-ben',
        description: 'Negative form of kansai-ben adjectives',
        i18n: [
          TransformDescriptorI18n(
            language: 'ja',
            name: '関西弁',
            description: '～ない (関西弁)',
          ),
        ],
        rules: [
          SuffixInflection('うない', 'くない', ['adj-i'], ['adj-i']),
          SuffixInflection('こうない', 'かくない', ['adj-i'], ['adj-i']),
          SuffixInflection('ごうない', 'がくない', ['adj-i'], ['adj-i']),
          SuffixInflection('そうない', 'さくない', ['adj-i'], ['adj-i']),
          SuffixInflection('とうない', 'たくない', ['adj-i'], ['adj-i']),
          SuffixInflection('のうない', 'なくない', ['adj-i'], ['adj-i']),
          SuffixInflection('ぼうない', 'ばくない', ['adj-i'], ['adj-i']),
          SuffixInflection('もうない', 'まくない', ['adj-i'], ['adj-i']),
          SuffixInflection('ろうない', 'らくない', ['adj-i'], ['adj-i']),
          SuffixInflection('ようない', 'よくない', ['adj-i'], ['adj-i']),
          SuffixInflection('しゅうない', 'しくない', ['adj-i'], ['adj-i']),
        ],
      ),
    },
  );
}
