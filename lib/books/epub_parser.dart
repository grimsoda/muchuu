// Epub format:
// Unzipped archive
// META-INF directory
// https://help.apple.com/itc/booksassetguide/#/itccdf8e5ab3
// Table of Contents possible names:
//  toc.xhtml (epub 3)
//  toc.ncx (epub 2)

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:csslib/parser.dart';
import 'package:csslib/visitor.dart';

import 'package:html/dom.dart';
import 'package:muchuu/books/book.dart';
import 'package:muchuu/books/character_count.dart';
import 'package:xml/xml.dart';
import 'package:xml/xpath.dart';

class EpubParser {
  EpubParser._();

  static void exportEpubToHtml(
      Archive epubArchive,
      Epub epub,
      Document doc,
      List<EpubManifestItem> spineItems,
      Uri publicationDirectory,
      String assetsRelativePath) {
    // List<Future<File>> writeFutures = [];
    final assetsUri = publicationDirectory.resolve(assetsRelativePath);
    final assetsRelativeUri = Uri.directory(assetsRelativePath);
    if (publicationDirectory != assetsUri) {
      final dir = Directory.fromUri(assetsUri);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    }
    Map<String, String> assetPaths = {};
    for (final manifestItem in epub.manifest.values) {
      switch (manifestItem.mediaType) {
        case 'application/xhtml+xml'
            when (epub.basePath.resolve(manifestItem.href) == epub.toc) ||
                spineItems.contains(manifestItem):
          break;
        case 'application/x-dtbncx+xml':
          break;
        default:
          final oldHref = Uri.file(manifestItem.href);
          final newHrefRel =
              Uri.file('${manifestItem.id}-${oldHref.pathSegments.last}');
          final file = File.fromUri(assetsUri.resolveUri(newHrefRel));
          print('${manifestItem.id}\t${manifestItem.href}\t${file.path}');
          List<int> contents = epubArchive
              .findFile(epub.basePath.resolveUri(oldHref).path)!
              .content;
          file.writeAsBytesSync(contents);
          // writeFutures.add(
          //     file.writeAsString(contents));
          assetPaths[manifestItem.id] =
              assetsRelativeUri.resolveUri(newHrefRel).path;
      }
    }
    final tocFile = File.fromUri(publicationDirectory.resolve('toc.xhtml'));
    if (tocFile.existsSync()) {
      print(
          'Warning: ${tocFile.path} already exists before writing toc, overwriting');
    }
    // writeFutures.add(tocFile.writeAsString(
    //     utf8.decode(epubArchive.findFile(epub.toc.path)!.content)));
    tocFile.writeAsStringSync(
        utf8.decode(epubArchive.findFile(epub.toc.path)!.content));

    resolveFileReferences(doc, assetPaths);
    final docFile = File.fromUri(publicationDirectory.resolve('index.html'));
    if (docFile.existsSync()) {
      print(
          'Warning: ${docFile.path} already exists before writing to it when html files should never have been written');
    }
    // writeFutures.add(docFile.writeAsString(doc.outerHtml));
    docFile.writeAsStringSync(doc.outerHtml);

    // await Future.wait(writeFutures);
  }

  static Book parseEpubToInlineHtml(Archive epubArchive,
      [Uri? exportDirectory]) {
    final mimetype = epubArchive.findFile('mimetype');
    if (mimetype == null) {
      throw Exception(
          'mimetype file not found in epub; cannot determine mimetype');
    }
    if (!utf8
        .decode(mimetype.content.toList())
        .contains('application/epub+zip')) {
      throw const FormatException('Not an epub file');
    }

    final metaFile = epubArchive.findFile('META-INF/container.xml');
    if (metaFile == null) {
      throw const FormatException(
          'Cannot locate metadata file (META-INF/container.xml)');
    }

    final contentPath = getContentPath(utf8.decode(metaFile.content));
    final contentFile = epubArchive.findFile(contentPath);
    if (contentFile == null) {
      throw FormatException('Cannot locate content file: $contentPath');
    }
    final epubMetadata =
        parseContent(utf8.decode(contentFile.content), contentPath);

    List<EpubManifestItem> spineItems = parseSpine(epubArchive, epubMetadata);
    XmlDocument merged = mergeEpubParts(epubMetadata, spineItems);
    // Document merged = mergeEpubParts(epubMetadata, spineItems);

    // Ignore book CSS support for now
    // mergeEpubStyle(epubArchive, epubMetadata, epubMetadata.stylesheetReferences);

    // TODO: handle toc
    resolveFileReferencesToInline(epubArchive, epubMetadata, merged);

    if (exportDirectory != null) {
      final file = File.fromUri(exportDirectory.resolve('./outputNovel.html'));
      file.writeAsStringSync(merged.outerXml);
      print('write html to ${file.path}');
    }

    return Book(
      title: merged.xpathEvaluate('/html/head/title/text()').string,
      bookHtml: merged.xpath('/html/body').single.innerXml,
    );
  }

  static Epub parseEpubToDisk(Archive epubArchive, Uri exportDirectory) {
    final mimetype = epubArchive.findFile('mimetype');
    if (mimetype == null) {
      throw Exception(
          'mimetype file not found in epub; cannot determine mimetype');
    }
    if (!utf8
        .decode(mimetype.content.toList())
        .contains('application/epub+zip')) {
      throw const FormatException('Not an epub file');
    }

    final metaFile = epubArchive.findFile('META-INF/container.xml');
    if (metaFile == null) {
      throw const FormatException(
          'Cannot locate metadata file (META-INF/container.xml)');
    }

    final contentPath = getContentPath(utf8.decode(metaFile.content));
    final contentFile = epubArchive.findFile(contentPath);
    if (contentFile == null) {
      throw FormatException('Cannot locate content file: $contentPath');
    }
    final epubMetadata =
        parseContent(utf8.decode(contentFile.content), contentPath);

    List<EpubManifestItem> spineItems = parseSpine(epubArchive, epubMetadata);
    XmlDocument merged = mergeEpubParts(epubMetadata, spineItems);

    // Ignore book CSS support for now
    // mergeEpubStyle(epubArchive, epubMetadata, epubMetadata.stylesheetReferences);

    throw UnimplementedError(
        'exportEpubToHtml does not yet support XmlDocument');
    // exportEpubToHtml(epubArchive, epubMetadata, merged, spineItems,
    //     exportDirectory, './assets/');

    return epubMetadata;
  }

  static String getContentPath(String metaInfContainer) {
    final meta = XmlDocument.parse(metaInfContainer);
    final contentPath = meta
        .xpath(
            '/container/rootfiles/rootfile[@media-type="application/oebps-package+xml"]/@full-path')
        .first
        .value;
    if (contentPath == null) {
      throw const FormatException(
          'opf rootfile does not have attribute full-path');
    }
    return contentPath;
  }

  // Epub 3.3 content.opf Spec
  // https://www.w3.org/TR/epub-33/#sec-package-elem
  // All data encapsulated in <package>
  // Attributes:
  //  dir // directionality of text, values = {'ltr', 'rtl', 'auto'}
  //  id [optional]

  //  https://www.w3.org/TR/epub-33/#sec-prefix-attr
  //  prefix [optional] // For additional prefixes
  //  xml:lang [optional]
  //  unique-identifier // TODO: handle case where unique-identifier metadata values are identical across publications
  //  version = "3.0"
  // Content Tags:
  //  metadata // https://www.w3.org/TR/epub-33/#sec-meta-elem
  //    Required Tags:
  //      dc:identifier
  //      dc:title
  //      dc:language
  //      meta // 1 required, 5 optional attributes
  //        dir [optional]
  //        id [optional]

  //        // Default Values
  //        // https://www.w3.org/TR/epub-33/#app-meta-property-vocab
  //        // Additional Values
  //        // https://www.w3.org/TR/epub-33/#sec-vocab-assoc
  //        property // https://www.w3.org/TR/epub-33/#sec-property-datatype
  //
  //        // No refines attribute -> primary expression
  //        //  Establishes some metadata for this epub
  //        // refines attribute -> subexpression
  //        //  Refines another expression/resource with more metadata
  //        refines [optional]
  //        scheme [optional] // prefixed string determining scheme of value
  //        xml:lang [optional]
  //        Inner Content: Text // https://www.w3.org/TR/epub-33/#sec-vocab-assoc
  //    Optional Tags:
  //      // https://www.dublincore.org/specifications/dublin-core/dcmi-terms/
  //      // https://www.w3.org/TR/epub-33/#sec-opf-dcmes-optional-def
  //      // Shared attributes for all dublin core tags
  //        id [optional] // allowed on all elements
  //        dir [optional] // on elements that is rendered as is and not parsed
  //        xml:lang [optional] // same restriction as above
  //
  //      dc:coverage // spatial or temporal region publication is relevant in
  //
  //      // role determined in meta tag with following attributes:
  //        property="role"
  //        scheme="marc:relators"
  //      dc:contributor // same rules as dc:creator
  //      dc:creator // https://www.w3.org/TR/epub-33/#dfn-dc-creator
  //      dc:date // recommended (rfc2119 meaning) to be parsable but not always
  //      dc:description
  //      dc:format // file format, physical medium, or dimensions
  //      dc:publisher
  //      dc:relation // resource related to this epub (recommended as uri)
  //      dc:rights
  //      dc:source // where this is derived from (recommended as uri)
  //
  //      // source system/scheme specified in meta with property="authority"
  //      // source specified -> there exists meta with property="term" for subject code
  //      dc:subject // https://www.w3.org/TR/epub-33/#sec-shared-attrs
  //
  //      // value can be any string but there are recommended values:
  //      // https://idpf.github.io/epub-registries/types/
  //      dc:type
  //      meta // epub 2 version with epub 2 attributes, ignore
  //      link // href links to more metadata, ignore?
  //        // TODO: Make warning when link tag detected
  //        href
  //        hreflang [optional]
  //        id [optional]
  //        media-type [conditionally required]
  //        properties [optional] // only value is "onix" for onix resources
  //        refines [optional]
  //        rel // https://www.w3.org/TR/epub-33/#sec-link-rel
  //  manifest
  // TODO: Handle and cache remote resources, which will be listed in the manifest
  //    Attributes:
  //      id [optional] // TODO: figure out why
  //    Required Tags:
  //      item // 3 required, 2 optional, 1 conditionally required attributes
  //        href
  //        id
  //        media-type // mimetype
  //        media-overlay [optional]
  //
  //        // https://www.w3.org/TR/epub-33/#app-item-properties-vocab
  //        // Additional values for Properties
  //        // https://www.w3.org/TR/epub-33/#sec-vocab-assoc
  //        properties [optional] // exactly one instance of "nav" properties
  //        fallback [conditionally required] // idref fallback chain
  //    Optional Tags:
  //      bindings [deprecated] // ignore
  //  spine
  //    Attributes:
  //      id [optional] // TODO: figure out why
  //      page-progression-direction [optional] // individual pages and user prefs will override this
  //      toc [optional; legacy]
  //    Required Tags:
  //      // Note: It is not mandatory to include epub nav doc here
  //      itemref // 1 required, 3 optional attributes
  //        id [optional]
  //        idref
  //        linear [optional] // linear if omitted
  //        properties [optional] // https://www.w3.org/TR/epub-33/#app-itemref-properties-vocab
  //  guide [optional; legacy] // landmarks nav in nav doc replaces this
  //  bindings [optional; deprecated] // custom handlers for unsupported media types, ignore
  //  collection [0 or more] // collection of resources for arbitrary purposes
  //    Attributes:
  //      dir [optional]
  //      id [optional]
  //      role
  //      xml:lang [optional]
  static Epub parseContentEpub3(XmlDocument content, String contentPath) {
    final identifierId =
        content.xpath('./package/@unique-identifier').first.value!;
    final meta = content.xpath('./package/metadata').first;
    // Using XmlElement.xpath instead of .xpathEvaluate because .xpathEvaluate('invalid input').string == '' and .xpath would throw an exception

    Map<String, EpubManifestItem> manifestItems = {};

    final manifest = content.xpath('./package/manifest').first;
    // Cover image in epub 3.x publication recommended but optional
    String? coverId = manifest
        .xpath('./item[@properties="cover-image"]/@id')
        .firstOrNull
        ?.value;
    String navId = manifest.xpath('./item[@properties="nav"]/@id').first.value!;
    String? coverHref;
    String? navHref;
    for (final item in manifest.childElements) {
      final id = item.xpath('./@id').first.value!;
      final mimeType = item.xpath('./@media-type').first.value!;
      final href = item.xpath('./@href').first.value!;
      // May not have properties attribute
      final properties = item.xpath('./@properties').firstOrNull?.value;

      if (id == coverId) {
        coverHref = href;
      } else if (id == navId) {
        navHref = href;
      }

      manifestItems[id] = EpubManifestItem(mimeType, id, href, properties);
    }

    // TODO: handle all allowed values for properties attribute
    // https://www.w3.org/TR/epub/#attrdef-properties
    List<EpubManifestItem> spineItems = [];
    final spineRefs = content
        .xpath('./package/spine/itemref/@idref')
        .map((node) => node.value);
    for (String? idRef in spineRefs) {
      if (idRef == null) {
        continue;
      }
      final item = manifestItems[idRef];
      if (item == null) {
        throw FormatException('Invalid idRef not included in manifest: $idRef');
      }
      spineItems.add(item);
    }

    Uri contentUri = Uri.file(contentPath, windows: false);

    if (navHref == null) {
      throw const FormatException('href nav is null');
    }

    return Epub(
      meta.xpath('./dc:title/text()').map((node) => node.value!).toList(),
      meta.xpath('./dc:creator/text()').map((node) => node.value!).toList(),
      meta.xpath('./dc:identifier[@id="$identifierId"]/text()').first.value!,
      manifestItems,
      spineItems,
      contentUri,
      EpubVersion.three,
      contentUri.resolve(navHref),
      coverHref != null ? contentUri.resolve(coverHref) : null,
    );
  }

  // Epub 2.0.1 content.opf Spec
  // All data encapsulated in <package> element
  // Attributes:
  //  unique-identifier
  //  version = "2.0" // TODO: if omitted, treat as OEBPS 1.2 ffs
  // Content Tags:
  //  metadata // NOTE: Multiple are allowed for all containing tags
  //    Required Tags:
  //      dc:title // first title likely most appropriate
  //      dc:identifier
  //      dc:language
  //    Optional Tags:
  //      dc:creator // 2 optional attributes below
  //        opf:file-as // normalized form of contents, ignore
  //        opf:role // values: https://idpf.org/epub/20/spec/OPF_2.0.1_draft.htm#Section2.2.6
  //      dc:subject // library genre codes, arbitrary
  //      dc:description
  //      dc:publisher
  //      dc:contributor // values: https://idpf.org/epub/20/spec/OPF_2.0.1_draft.htm#Section2.2.6
  //      dc:date // YYYY-MM-DD, year only required; 1 optional attribute below
  //        event // arbitrary values
  //      dc:format // MIME or dimensions or arbitrary
  //      dc:source
  //      dc:language // RFC-3066 codes
  //      dc:relation // auxiliary resource and relation to publication
  //      dc:coverage // scope of book contents
  //      dc:rights
  //      meta // out of spec metadata, xhtml 1.1 format
  //        name
  //        content
  //        scheme [optional]
  //        http-equiv [optional] // maybe http header name?
  //    DEPRECATED version could have these tags instead:
  //      dc-metadata // contains dc namespace metadata tags
  //      x-metadata // contains out of spec metadata tagsA
  //  manifest
  //    Required Tags:
  //      item // 3 required attributes
  //        id
  //        href // unique
  //        media-type
  //        fallback [optional] // fallback id if not supported (recursive)
  //        fallback-style [optional] // id to css, can either use fallback-style or required-namespace/modules
  //        required-namespace [optional]
  //        required-modules [optional] // comma separated; trim whitespaces
  //  spine
  //    Required Attributes:
  //      toc // id for table of contents; application/x-dtbncx+xml
  //    Required Tags:
  //      itemref // 1 required attribute
  //        idref // if id corresponds to invalid media-type with no fallback, exclude it
  //        linear [optional] // == "no" -> auxiliary content visible through hyperlink or could just do noting // TODO: option to switch between these
  //  tours [DEPRECATED] // don't care
  //  guide [optional] // "fundamental structural components" of book
  //    // We can find things like type == "cover", "text" for main content
  //    Required Tags:
  //      reference // 3 required attributes
  //        type // https://idpf.org/epub/20/spec/OPF_2.0.1_draft.htm#Section2.6
  //        title
  //        href
  // TODO: Fallback Items (https://idpf.org/epub/20/spec/OPF_2.0.1_draft.htm#Section2.3.1)
  static Epub parseContentEpub2(XmlDocument content, String contentPath) {
    final meta = content.xpath('./package/metadata').first;
    final identifierId =
        content.xpath('./package/@unique-identifier').first.value!;

    Map<String, EpubManifestItem> manifestItems = {};
    final manifest = content.xpath('./package/manifest').first;

    for (final item in manifest.childElements) {
      // Epub 2.x supports fallbacks, but we probably don't need to worry about those
      final id = item.xpath('./@id').first.value!;
      final mimeType = item.xpath('./@media-type').first.value!;
      final href = item.xpath('./@href').first.value!;
      manifestItems[id] = EpubManifestItem(mimeType, id, href);
    }

    // Map<String, ({String mimeType, String href})> items = {};
    // for (final item in manifest.childElements) {
    //   final id = item.xpath('./@id').first.value!;
    //   final mimeType = item.xpath('./@media-type').first.value!;
    //   final href = item.xpath('./@href').first.value!;
    //   items[id] = (
    //     mimeType: mimeType,
    //     href: href,
    //   );
    // }

    List<EpubManifestItem> spineItems = [];
    final spine = content.xpath('./package/spine').first;
    String navId = spine.xpath('./@toc').first.value!;
    String navHref = manifestItems[navId]!.href;
    final spineRefs = content
        .xpath('./package/spine/itemref/@idref')
        .map((node) => node.value);
    for (String? idRef in spineRefs) {
      if (idRef == null) {
        continue;
      }
      final item = manifestItems[idRef];
      if (item == null) {
        throw FormatException('Invalid idRef not included in manifest: $idRef');
      }
      spineItems.add(item);
    }

    // We only care about extracting cover (if not already found) from the guide for now
    // Other values for type property that may or may not be of use:
    // https://idpf.org/epub/20/spec/OPF_2.0.1_draft.htm#Section2.6
    String? coverId = meta.xpath('./meta[@name="cover"]/@content').first.value;
    String? coverHref;
    if (coverId != null) {
      coverHref = manifestItems[coverId]?.href;
    }
    final guide = content.xpath('./package/guide').first;
    coverHref ??= guide.xpath('./reference[@type="cover"]/@href/').first.value;

    final contentUri = Uri.file(contentPath, windows: false);

    return Epub(
      meta.xpath('./dc:title/text()').map((node) => node.value!).toList(),
      meta.xpath('./dc:creator/text()').map((node) => node.value!).toList(),
      meta.xpath('./dc:identifier[@id="$identifierId"]/text()').first.value!,
      manifestItems,
      spineItems,
      contentUri,
      EpubVersion.two,
      contentUri.resolve(navHref),
      coverHref != null ? contentUri.resolve(coverHref) : null,
    );
  }

  static Epub parseContent(String content, String contentPath) {
    final contentXml = XmlDocument.parse(content);
    String version = contentXml.xpath('./package/@version').first.value!;
    return switch (version) {
      '2.0' => parseContentEpub2(contentXml, contentPath),
      '3.0' => parseContentEpub3(contentXml, contentPath),
      _ => throw FormatException(
          'Unrecognized epub content file version: $version'),
    };
  }

  static List<EpubManifestItem> parseSpine(Archive epubArchive, Epub epub) {
    // epub 2.0 => toc is ncx file
    // epub 3.0 => toc is just a specialized xhtml file
    // TOdO: test with epub 2.0

    List<EpubManifestItem> items = [];
    List<String> itemPaths = [];

    for (final item in epub.spine) {
      switch (item.mediaType) {
        case 'application/xhtml+xml':
          if (item.href == epub.toc.path) {
            print(
                "Found nav item in spine (epub 3.0) of id ${item.id}: ${item.href}");
          }
          items.add(item);
          break;
        case 'application/x-dtbncx+xml':
          print(
              'Warning: ncx (id=${item.id}, href=${item.href}) in spine which should probably never happen.');
          break;
        case 'image/svg+xml':
          print(
              'Warning: svg (id=${item.id}, href=${item.href}) in spine, which is currently unsupported');
          break;
        default:
          throw FormatException(
              'Unknown media type in spine for id ${item.id} (href=${item.href}): ${item.mediaType}');
      }
      Uri path = epub.basePath.resolve(item.href);
      final file = epubArchive.findFile(path.path);
      if (file == null) {
        throw FormatException(
            'File found in spine but not found in epub archive: ${path.path}');
      }
      itemPaths.add(path.path);
    }

    for (int i = 0; i < items.length; i++) {
      EpubManifestItem item = items[i];
      ArchiveFile file = epubArchive.findFile(itemPaths[i])!;
      // item.content = Document.html(utf8.decode(file.content));
      item.content = XmlDocument.parse(utf8.decode(file.content));
    }

    return items;
  }

  static XmlDocument mergeEpubParts(
      Epub epub, List<EpubManifestItem> contentItems) {
    // We can probably use toc to build refs (though we can just use the included refs inside the xhtml files)
    // Do this separately

    // Since we're dealing with xhtml (and svg) we can use an xml parser instead of an html parser.
    // The package:html package also doesn't seem to be able to properly select elements with a specific
    // attribute if the attribute name has a prefix, which is needed for svgs including attributes with the
    // deprecated xlink prefix (for an example see https://developer.mozilla.org/en-US/docs/Web/SVG/Attribute/xlink:href).
    // However, we only need to compose a document that is valid html for now.
    // TODO: we can probably reorganize this section to be a little bit more readable
    final composed = XmlDocument([XmlDoctype('html')]);

    final composedParent = XmlElement(XmlName('html'));
    composed.children.add(composedParent);

    final composedHead = XmlElement(
        XmlName('head'),
        const [],
        [
          XmlElement(
            XmlName('meta'),
            [XmlAttribute(XmlName('charset'), 'UTF-8')],
          ),
          XmlElement(
            XmlName('title'),
          )..children.add(XmlText(epub.titles[0])),
        ],
        false);
    composedParent.children.add(composedHead);

    final composedBody = XmlElement(XmlName('body'));
    composedParent.children.add(composedBody);

    // This is so we can make the ebook only take up a percentage of the viewport if we wanted to
    final composedBodyMainDivWrapper = XmlElement(
        XmlName('div'),
        [
          XmlAttribute(XmlName('id'), 'wrapper-muchuu'),
          XmlAttribute(XmlName('style'),
              'display: flex; flex-direction: column; justify-content: center; align-items: center;'),
        ],
        const [],
        false);
    composedBody.children.add(composedBodyMainDivWrapper);

    final composedBodyMainDiv = XmlElement(XmlName('div'),
        [XmlAttribute(XmlName('id'), 'main-muchuu')], const [], false);
    composedBodyMainDivWrapper.children.add(composedBodyMainDiv);

    // TODO: Incorporate everything that isn't the body
    // TODO: Fix composed does not contain composedBody for some reason

    Map<String, List<String>> stylesheetReferences = {};
    for (final item in contentItems) {
      // print('\n${item.id}');
      final XmlDocument doc = item.content!;
      final XmlElement parent = doc.getElement('html')!;
      XmlElement body = parent.getElement('body')!;
      XmlElement head = parent.getElement('head')!;

      Uri basePath = epub.basePath.resolve(item.href);

      // References to be resolved later
      setFileReferencePlaceholders(epub, body, 'src', basePath);
      setFileReferencePlaceholders(epub, body, 'href', basePath);
      setFileReferencePlaceholders(epub, body, 'xlink:src', basePath);
      setFileReferencePlaceholders(epub, body, 'xlink:href', basePath);

      // TODO: Handle style tags in the head as well
      // Honestly we should probably just ignore those style tags because what are they doing.
      // Let's hope that since these documents should conform to the xhtml spec no one puts style tags
      // inside of the body.
      final fileWideStylesheets = head
          .findAllElements('link')
          .where((element) => element.getAttribute('rel') == 'stylesheet');
      for (final link in fileWideStylesheets) {
        Uri href = basePath.resolve(link.getAttribute('href')!);
        stylesheetReferences
            .putIfAbsent(href.toString(), () => [])
            .add('muchuu-${item.id}');
      }

      final bodyClasses = body.getAttributeNode('class');
      composedBodyMainDiv.children.add(XmlElement(
        XmlName('div'),
        [
          XmlAttribute(XmlName('id'), 'muchuu-${item.id}'),
          if (bodyClasses != null) bodyClasses..detachParent(body),
        ],
        body.childElements
          ..forEach((child) => child.detachParent(child.parent!)),
        false,
      ));
      // final contentParent = Element.tag('div');
      // contentParent.id = 'muchuu-${item.id}';
      // contentParent.classes.addAll(body.classes);
      // body.reparentChildren(contentParent);
      // composedBody.append(contentParent);

      // TODO: Character counting

      // TODO: Actually display character counts
    }

    int charCount = CharacterCounter.countCharactersInDiv(composedBodyMainDiv);
    print('found a total of $charCount characters');
    epub.contentsLength = charCount;
    // TODO: Handle potentially tag-specific classes for body tag
    epub.stylesheetReferences = stylesheetReferences;
    return composed;
  }

  static void mergeEpubStyle(Archive archive, Epub epub,
      Map<String, List<String>> stylesheetReferences) {
    for (final MapEntry(
          key: String sheetHref,
          value: List<String> referenceLocations
        ) in stylesheetReferences.entries) {
      // TODO: Probably make it so instead of the files being is([all classes]) as the selector
      //       make it another class.
      ArchiveFile sheetFile = archive.findFile(sheetHref)!;
      StyleSheet sheet = parse(utf8.decode(sheetFile.content));
      print(sheet.span);
      for (final node in sheet.topLevels) {
        if (node is RuleSet) {
          print(node.selectorGroup);
        }
      }
    }

    throw UnimplementedError();
  }

  // Display this as inapp webview?
  // We might be able to integrate existing context menus or just make our own context menus
  // And we can do hotkey or hold key detection on desktop/web just like in yomichan

  static void setFileReferencePlaceholders(
      Epub epub, XmlElement parent, String referenceAttribute, Uri basePath) {
    final elementsWithReferences = parent.xpath('//*[@$referenceAttribute]');
    for (var element in elementsWithReferences) {
      final rel = Uri.parse(element.getAttribute(referenceAttribute)!);
      switch (rel.scheme) {
        case '':
          break;
        case 'file':
          // Weird for there to be a file scheme URI but ok?
          print('File scheme detected in element of base path $basePath: $rel');
          break;
        case 'http' || 'https':
          continue;
        default:
          print(
              'Unknown scheme in element of base path $basePath: $rel. Skipping.');
          continue;
      }

      final ref = basePath.resolve(rel.path);
      // References to other files in epub should always be in the manifest
      // firstWhere() will throw StateError if no such match
      final manifestItem = epub.manifest.values.firstWhere(
          (manifestItem) => epub.basePath.resolve(manifestItem.href) == ref);
      final magic = '!';
      // We probably don't need to handle queries to local files?
      String suffix = rel.hasFragment ? ' #${rel.fragment}' : '';
      element.setAttribute(
          referenceAttribute, '$magic${manifestItem.id}$suffix');
    }
  }

  static void resolveFileReferences(
      Document doc, Map<String, String> idToPath) {
    // TODO: resolve toc as well (or put the toc in the db)
    // TODO: html head for css
    final magic = '!';
    final attributes = ['src', 'href'];
    for (final attribute in attributes) {
      final elements = doc.querySelectorAll('html body [$attribute^="$magic"]');
      print(elements);
      for (final element in elements) {
        final match = element.attributes[attribute]!.substring(1).split(' ');
        final href = idToPath[match[0]];
        final fragment = match.length > 1 ? match[1] : '';
        print('prev ${element.attributes[attribute]}');
        element.attributes[attribute] = '$href$fragment';
        print('now: ${element.attributes[attribute]}\n');
      }
    }
  }

  static Map<XmlElement, XmlAttribute> _collectElementsWithSimpleAttribute(
          XmlDocument doc,
          String magic,
          String parentSelector,
          String attribute) =>
      {
        for (var element in doc
            .xpath('$parentSelector//*[starts-with(@$attribute, "$magic")]'))
          element as XmlElement: element.getAttributeNode(attribute)!
      };

  static Map<XmlElement, XmlAttribute> _collectElementsWithPrefixedAttribute(
          XmlDocument doc,
          String magic,
          String parentSelector,
          String attributePrefix,
          String attributeName,
          {bool namespaceOptional = false}) =>
      _collectElementsWithSimpleAttribute(
          doc, magic, parentSelector, attributeName)
        ..addAll(namespaceOptional
            ? _collectElementsWithSimpleAttribute(
                doc, magic, parentSelector, '$attributePrefix:$attributeName')
            : {});

  static void resolveFileReferencesToInline(
      Archive epubArchive, Epub epub, XmlDocument doc) {
    // TODO: resolve toc as well (or put the toc in the db)
    // TODO: html head for css
    final magic = '!';
    // final attributes = ['src', 'href'];
    // TODO: properly confirm utilization of href and src attributes in svgs
    // Also do a quick sanity check that there aren't any other xml types validly possible apart from xhtml and svg
    Map<XmlElement, XmlAttribute> mediaReferenceElements =
        _collectElementsWithSimpleAttribute(
            doc, magic, '//body//*[not(ancestor::svg)]', 'src')
          ..addAll(_collectElementsWithPrefixedAttribute(
            doc,
            magic,
            '//body//svg',
            'xlink',
            'href',
            namespaceOptional: true,
          ));
    Map<XmlElement, XmlAttribute> documentReferenceElements =
        _collectElementsWithSimpleAttribute(
            doc, magic, '//body//*[not(ancestor::svg)]', 'href');

    String clampString(String input, int maxLength) => input.length > maxLength
        ? '${input.substring(0, (maxLength / 2).ceil())} ... ${input.substring(input.length - (maxLength / 2).ceil())}'
        : input;

    for (final MapEntry(key: element, value: attribute)
        in mediaReferenceElements.entries) {
      final match = attribute.value.substring(1).split(' ');
      final manifestItem = epub.manifest[match[0]]!;
      final fragment = match.length > 1 ? match[1] : '';
      if (fragment != '') {
        throw UnimplementedError(
            'Unable to handle media reference with a fragment: ${element.outerXml}');
      }
      final file =
          epubArchive.findFile(epub.basePath.resolve(manifestItem.href).path)!;
      print(
          'prev ${element.localName}[${attribute.name}] ${clampString(element.getAttribute(attribute.qualifiedName)!, 50)}');
      print('skipping');
      // attribute.value =
      //     Uri.dataFromBytes(file.content, mimeType: manifestItem.mediaType)
      //         .toString();
      print(
          'now: ${element.localName}[${attribute.name}] ${clampString(element.getAttribute(attribute.qualifiedName)!, 50)}\n');
    }

    for (final MapEntry(key: element, value: attribute)
        in documentReferenceElements.entries) {
      final match = attribute.value.substring(1).split(' ');
      final manifestItem = epub.manifest[match[0]]!;
      final fragment = match.length > 1 ? match[1] : '';
      if (!epub.spine.contains(manifestItem)) {
        throw UnimplementedError(
            'element does not refer to a document in the spine: ${element.outerXml}');
      }
      if (fragment.isNotEmpty) {
        print('fragment is $fragment for muchuu-${manifestItem.id}');
      }
      print(
          'prev ${element.localName}[${attribute.name}] ${clampString(element.getAttribute(attribute.qualifiedName)!, 50)}');
      // attribute.value = 'muchuu-${manifestItem.id}$fragment';
      attribute.value = '#muchuu-${manifestItem.id}';
      print(
          'now: ${element.localName}[${attribute.name}] ${clampString(element.getAttribute(attribute.qualifiedName)!, 50)}\n');
    }
  }
}
