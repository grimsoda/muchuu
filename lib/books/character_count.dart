import 'package:xml/xml.dart';
import 'package:xml/xpath.dart';

class CharacterCounter {
  CharacterCounter._();

  static const _excludedTagsForCounting = <String>['rp', 'rt'];

  // From ttsu reader: https://github.com/ttu-ttu/ebook-reader/blob/main/apps/web/src/lib/functions/get-character-count.ts
  // TODO: Come up with your own regex
  // Technically matches all non Japanese or English characters
  static final _nonJapaneseTextRegex = RegExp(
      r'[^0-9A-Z○◯々-〇〻ぁ-ゖゝ-ゞァ-ヺー０-９Ａ-Ｚｦ-ﾝ\p{Radical}\p{Unified_Ideograph}]+',
      multiLine: true,
      caseSensitive: false,
      unicode: true);

  static int countCharacters(String text) =>
      text.replaceAll(_nonJapaneseTextRegex, '').length;

  static int countCharactersInDiv(XmlElement element) {
    final paragraphs = element.xpath('//p').whereType<XmlElement>();
    int characterCount = 0;
    for (final par in paragraphs) {
      characterCount += countCharactersInParagraph(par);
    }
    return characterCount;
  }

  // TODO: Figure out character counting with progression
  // Continuous page implementation:
  // https://github.com/ttu-ttu/ebook-reader/blob/main/apps/web/src/lib/components/book-reader/book-reader-continuous/character-stats-calculator.ts
  // Paginated implementation:
  // https://github.com/ttu-ttu/ebook-reader/blob/main/apps/web/src/lib/components/book-reader/book-reader-paginated/section-character-stats-calculator.ts

  static int countCharactersInParagraph(XmlElement paragraph) {
    // TODO: Figure out why this undercounts compared to ttsu reader implementation
    // Though, this should probably be a more accurate count.
    // https://github.com/ttu-ttu/ebook-reader/blob/main/apps/web/src/lib/functions/get-character-count.ts
    assert(paragraph.localName == 'p');

    // TODO: Replacement regex
    final loneParagraph = paragraph.copy()
      ..childElements.toList().forEach((child) => child.remove());
    int characterCount = countCharacters(loneParagraph.innerXml);

    for (final descendant in paragraph.descendantElements) {
      if (_excludedTagsForCounting.contains(descendant.localName)) {
        continue;
      }
      final loneDescendant = descendant.copy()
        ..childElements.toList().forEach((child) => child.remove());
      characterCount += countCharacters(loneDescendant.innerXml);
    }

    print('$characterCount chars in paragraph ${paragraph.outerXml}');
    return characterCount;
  }
}
