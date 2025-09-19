import 'package:xml/xml.dart';

class Book {
  String title;
  String bookHtml;

  Book({
    required this.title,
    required this.bookHtml,
  });
}

class Epub {
  // TODO: maybe we should have EpubParser class as well for more separation/cohesiveness
  List<String> titles;
  List<String> authors;
  String identifier;
  Map<String, EpubManifestItem> manifest;
  List<EpubManifestItem> spine;
  Uri basePath; // uri to opf file
  EpubVersion version;
  Uri toc;
  Uri? cover;
  int? contentsLength;

  // TODO: Find better location to store this.
  Map<String, List<String>> stylesheetReferences = {};

  Epub(this.titles, this.authors, this.identifier, this.manifest, this.spine,
      this.basePath, this.version, this.toc,
      [this.cover]);
}

class EpubManifestItem {
  String mediaType;
  String id;
  String href;
  String? properties;

  // TODO: Support fallback
  // EpubManifestItem? fallback;

  // Document? content;
  XmlDocument? content;

  EpubManifestItem(this.mediaType, this.id, this.href, [this.properties]);
}

enum EpubVersion {
  two,
  three,
}
