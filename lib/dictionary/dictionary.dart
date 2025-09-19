import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:json_schema/json_schema.dart';
import 'package:muchuu/language/ja/japanese_transforms.dart';
import 'package:muchuu/user_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import '../language/language_engine.dart';

class _DictionaryConstants {
  // TODO: Maybe make readings nullable?
  static const Map<String, String> tableInitStatements = {
    'terms': '''
    CREATE TABLE terms (
      term TEXT NOT NULL,
      reading TEXT NOT NULL,
      dictionary TEXT NOT NULL,
      definitions TEXT,
      termTags TEXT,
      definitionTags TEXT,
      inflectionRules TEXT,
      popularity INTEGER,
      sequenceNumber INTEGER NOT NULL
    );
    ''',
    'kanji': '''
    CREATE TABLE kanji (
      kanji TEXT NOT NULL,
      onyomi TEXT,
      kunyomi TEXT,
      definitions TEXT,
      tags TEXT,
      stats BLOB,
      dictionary TEXT NOT NULL
    );
    ''',
    'termsMeta': '''
    CREATE TABLE termsMeta (
      term TEXT NOT NULL,
      reading TEXT NOT NULL,
      dictionary TEXT NOT NULL,
      metaType TEXT NOT NULL,
      data TEXT NOT NULL
    );
    ''',
    'kanjiMeta': '''
    CREATE TABLE kanjiMeta (
      kanji TEXT NOT NULL,
      frequency INTEGER,
      displayFrequency TEXT,
      dictionary TEXT NOT NULL
    );
    ''',
    'tags': '''
    CREATE TABLE tags (
      tag TEXT NOT NULL,
      category TEXT,
      sortingOrder INTEGER,
      notes TEXT,
      popularity INTEGER,
      dictionary TEXT NOT NULL
    );
    ''',
    'dictionaries': '''
    CREATE TABLE dictionaries (
      title TEXT NOT NULL PRIMARY KEY,
      revision TEXT,
      sequenced BOOL,
      format INTEGER,
      author TEXT,
      url TEXT,
      description TEXT,
      attribution TEXT,
      sourceLang TEXT,
      targetLang TEXT,
      frequencyMode TEXT,
      cssStyle TEXT
    );
    ''',
  };

  static Future<JsonSchema> metadataSchema =
      JsonSchema.createFromUrl('assets/schemas/dictionary-index-schema.json');
  static Future<JsonSchema> kanjiBankV1Schema = JsonSchema.createFromUrl(
      'assets/schemas/dictionary-kanji-bank-v1-schema.json');
  static Future<JsonSchema> kanjiBankV3Schema = JsonSchema.createFromUrl(
      'assets/schemas/dictionary-kanji-bank-v3-schema.json');
  static Future<JsonSchema> kanjiMetaBankSchema = JsonSchema.createFromUrl(
      'assets/schemas/dictionary-kanji-meta-bank-v3-schema.json');
  static Future<JsonSchema> termBankV1Schema = JsonSchema.createFromUrl(
      'assets/schemas/dictionary-term-bank-v1-schema.json');
  static Future<JsonSchema> termBankV3Schema = JsonSchema.createFromUrl(
      'assets/schemas/dictionary-term-bank-v3-schema.json');
  static Future<JsonSchema> termMetaBankSchema = JsonSchema.createFromUrl(
      'assets/schemas/dictionary-term-meta-bank-v3-schema.json');
  static Future<JsonSchema> tagBankSchema =
      JsonSchema.createFromUrl('assets/schemas/dictionary-index-schema.json');

  _DictionaryConstants._();
}

class DictionaryManager {
  static DictionaryManager? _instance;

  static Future<DictionaryManager> get instance async =>
      _instance ??= await _fromPreferences();

  late final Database _db;
  late final String? databaseLocation;
  final List<VoidCallback> _databaseChangedCallbacks = [];

  DictionaryManager._internal();

  static Future<DictionaryManager> _fromPreferences() async {
    final instance = DictionaryManager._internal();
    UserPreferences prefs = await UserPreferences.instance;

    switch (prefs.useDatabaseFromDisk) {
      case true:
        instance._db = sqlite3.open(prefs.databasePath);
        instance.databaseLocation = prefs.databasePath;
      case false:
        instance._db = sqlite3.openInMemory();
        instance.databaseLocation = null;
    }
    instance.initDatabaseTables();
    return instance;
  }

  bool initDatabaseTables() {
    // TODO: Figure out if we can do some sort of IF NOT EXISTS table
    for (final MapEntry<String, String>(
          key: String table,
          value: String tableInitSql
        ) in _DictionaryConstants.tableInitStatements.entries) {
      if (_db
          .select(
              'SELECT name FROM sqlite_master where type=\'table\' and name=\'$table\'')
          .isEmpty) {
        print("table $table doesn't exist, creating it");
        _db.execute(tableInitSql);
      }
    }
    return true;
  }

  void resetDatabase() {
    for (final MapEntry(key: String table, value: String initSql)
        in _DictionaryConstants.tableInitStatements.entries) {
      _db.execute('DROP TABLE IF EXISTS $table');
      _db.execute(initSql);
    }
    _db.execute('vacuum');
    _onDatabaseChanged();
  }

  Future<void> exportDictionary(String saveLocation) async {
    Database export = sqlite3.open(saveLocation);
    await _db.backup(export).drain();
  }

  bool dictionaryAlreadyImported(String dictionaryName) {
    final result = _db.select(
        'SELECT title FROM dictionaries WHERE title = \'$dictionaryName\'');
    return result.isNotEmpty;
  }

  List<String> importedDictionaries() {
    return _db
        .select('SELECT title FROM dictionaries')
        .map((e) => e[0] as String)
        .toList(growable: false);
  }

  Future<void> _importDictionary(Dictionary dictionary) async {
    final realStopwatch = Stopwatch()..start();
    _db.execute('BEGIN');
    try {
      _addDictionaryEntry(dictionary.metadata);
      print('Importing ${dictionary.metadata.title} to db');

      switch (dictionary) {
        case YomichanDictionary dictionary:
          final stopwatch = Stopwatch()..start();

          // TODO: Test try not awaiting them and see what happens

          final termRows =
              await _addTerms(dictionary.terms, dictionary.metadata.title);
          print(
              'Imported terms in $termRows rows in ${stopwatch.elapsedMilliseconds} ms');
          stopwatch.reset();

          final termMetaRows = await _addTermsMeta(
              dictionary.termsMeta, dictionary.metadata.title);
          print(
              'Imported termsMeta in $termMetaRows rows in ${stopwatch.elapsedMilliseconds} ms');
          stopwatch.reset();

          final kanjiRows =
              await _addKanji(dictionary.kanji, dictionary.metadata.title);
          print(
              'Imported kanji in $kanjiRows rows in ${stopwatch.elapsedMilliseconds} ms');
          stopwatch.reset();

          final kanjiMetaRows = await _addKanjiMeta(
              dictionary.kanjiMeta, dictionary.metadata.title);
          print(
              'Imported kanjiMeta in $kanjiMetaRows rows in ${stopwatch.elapsedMilliseconds} ms');
          stopwatch.reset();

          final tagRows =
              await _addTags(dictionary.tags, dictionary.metadata.title);
          print(
              'Imported tags in $tagRows rows in ${stopwatch.elapsedMilliseconds} ms');
          stopwatch.reset();

          _onDatabaseChanged();
      }
      _db.execute('COMMIT');

      // Import media
      for (final mediaPath in dictionary.metadata.mediaFiles) {
        // TODO: Handle conflicts where there are different files?
        // TODO: How are we going to get the path of the dictionary archive? lol
        // File(mediaPath.resolve(file.name).toFilePath(windows: Platform.isWindows))
        //     .create(recursive: true).then((fileOnDisk) => fileOnDisk.writeAsBytes(file.content));
      }
    } catch (e) {
      print(e);
      print('Rolling back dictionary import');
      _db.execute('ROLLBACK');
    }
    print('Finished importing in ${realStopwatch.elapsedMilliseconds} ms');
    realStopwatch.stop();
  }

  Future<void> _importDictionaryMedia(
      DictionaryMetadata metadata, Archive dictionaryArchive) async {
    Uri mediaPath = (await UserPreferences.preferencesDirectory)
        .resolve('dictionaryMedia/${metadata.title}/');
    print(
        'Importing ${metadata.mediaFiles.length} media files to ${Uri.decodeFull(mediaPath.path)}');
    List<Future<File>> importFutures = [];
    final stopwatch = Stopwatch()..start();
    for (final mediaFile in metadata.mediaFiles) {
      final mediaData = dictionaryArchive.findFile(mediaFile);
      if (mediaData == null) {
        print('Cannot find file $mediaFile in archive of ${metadata.title}');
        continue;
      }
      final importFuture = File.fromUri(mediaPath.resolve(mediaFile))
          .create(recursive: true)
          .then((file) => file.writeAsBytes(mediaData.content));
      importFutures.add(importFuture);
    }
    int futures = (await Future.wait(importFutures)).length;
    print(
        'Imported $futures media files in ${stopwatch.elapsedMilliseconds} ms');
  }

  void addDictionaryImportedCallback(VoidCallback callback) {
    _databaseChangedCallbacks.add(callback);
  }

  bool removeDictionaryImportedCallback(VoidCallback callback) {
    return _databaseChangedCallbacks.remove(callback);
  }

  // TODO: me when the function is async funny function
  Future<int> _addRows<T>(String table,
      List<(String, Function(T))> valuesAndAccessors, List<T> objects) async {
    int rowCounter = 0;
    final valueNames = valuesAndAccessors.map((pair) => pair.$1).join(', ');
    final bindVariables =
        List.filled(valuesAndAccessors.length, '?').join(', ');
    final statement =
        _db.prepare('INSERT INTO $table ($valueNames) VALUES ($bindVariables)');
    for (final object in objects) {
      statement.execute([
        for (final (_, accessor) in valuesAndAccessors) await accessor(object)
      ]);
      rowCounter++;
    }
    return rowCounter;
  }

  Future<int> _addTerms(List<Term> terms, String dictionaryName) async =>
      _addRows<Term>(
          'terms',
          [
            ('term', (term) => term.term),
            ('reading', (term) => term.reading),
            ('dictionary', (_) => dictionaryName),
            (
              'definitions',
              (term) async =>
                  '[${(await Future.wait((term.definitions as List<BasicDefinition>).map((def) async => await def.getDefinitionText()).toList())).join(',')}]' // Disgusting
            ),
            ('termTags', (term) => term.termTags.join(' ')),
            ('definitionTags', (term) => term.definitionTags.join(' ')),
            ('inflectionRules', (term) => term.inflections.join(' ')),
            ('popularity', (term) => term.popularity),
            ('sequenceNumber', (term) => term.sequenceNumber),
          ],
          terms);

  Future<int> _addTermsMeta(
          List<TermMetadata> termsMeta, String dictionaryName) async =>
      _addRows<TermMetadata>(
          'termsMeta',
          [
            ('term', (meta) => meta.term),
            ('reading', (meta) => meta.reading),
            ('dictionary', (_) => dictionaryName),
            ('metaType', (meta) => meta.getMetadataType()),
            ('data', (meta) => jsonEncode(meta)),
          ],
          termsMeta);

  Future<int> _addKanji(List<Kanji> kanji, String dictionaryName) async =>
      _addRows<Kanji>(
          'kanji',
          [
            ('kanji', (kanji) => kanji.kanji),
            ('onyomi', (kanji) => kanji.onyomiReadings.join(' ')),
            ('kunyomi', (kanji) => kanji.kunyomiReadings.join(' ')),
            ('definitions', (kanji) => jsonEncode(kanji.definitions)),
            ('tags', (kanji) => kanji.tags.join(' ')),
            ('stats', (kanji) => jsonEncode(kanji.stats)),
            ('dictionary', (_) => dictionaryName),
          ],
          kanji);

  Future<int> _addKanjiMeta(
          List<KanjiMetadata> kanjiMeta, String dictionaryName) async =>
      _addRows<KanjiMetadata>(
          'kanjiMeta',
          [
            ('kanji', (meta) => meta.kanji),
            ('frequency', (meta) => meta.frequency),
            ('displayFrequency', (meta) => meta.displayFrequency),
            ('dictionary', (_) => dictionaryName),
          ],
          kanjiMeta);

  Future<int> _addTags(List<Tag> tags, String dictionaryName) async =>
      _addRows<Tag>(
          'tags',
          [
            ('tag', (tag) => tag.name),
            ('category', (tag) => tag.category),
            ('sortingOrder', (tag) => tag.sortingOrder),
            ('notes', (tag) => tag.notes),
            ('popularity', (tag) => tag.popularity),
            ('dictionary', (_) => dictionaryName),
          ],
          tags);

  Future<int> _addDictionaryEntry(DictionaryMetadata metadata) async =>
      _addRows<DictionaryMetadata>(
        'dictionaries',
        [
          ('title', (dict) => dict.title),
          ('revision', (dict) => dict.revision),
          ('sequenced', (dict) => dict.sequenced.toString()),
          ('format', (dict) => dict.format),
          ('author', (dict) => dict.author),
          ('url', (dict) => dict.url),
          ('description', (dict) => dict.description),
          ('attribution', (dict) => dict.attribution),
          ('sourceLang', (dict) => dict.sourceLanguage),
          ('targetLang', (dict) => dict.targetLanguage),
          ('frequencyMode', (dict) => dict.frequencyMode.toString()),
          ('cssStyle', (dict) => dict.cssStyle)
        ],
        [metadata],
      );

  void _onDatabaseChanged() {
    print(
        'database changed, calling ${_databaseChangedCallbacks.length} callbacks');
    for (final callback in _databaseChangedCallbacks) {
      callback.call();
    }
  }

  List<T> search<T>(String table, String searchColumn, String query,
      SearchMode searchMode, T Function(Row) createSearchResult,
      [List<String> dictionaryFilter = const []]) {
    final searchQuery = switch (searchMode) {
      SearchMode.exact => '= \'$query\'',
      SearchMode.prefix => 'LIKE \'%$query\'',
      SearchMode.suffix => 'LIKE \'$query%\'',
      SearchMode.contains => 'LIKE \'%$query%\'',
    };
    if (dictionaryFilter.isNotEmpty) {
      print(
          'Searching with enabled dictionary restriction, query is SELECT * FROM $table WHERE $searchColumn $searchQuery AND dictionary IN (${List.filled(dictionaryFilter.length, '?').join(', ')})');
    }
    ResultSet results = switch (dictionaryFilter.isEmpty) {
      true =>
        _db.select('SELECT * FROM $table WHERE $searchColumn $searchQuery'),
      false => _db.select(
          'SELECT * FROM $table WHERE $searchColumn $searchQuery AND dictionary IN (${List.filled(dictionaryFilter.length, '?').join(', ')})',
          dictionaryFilter),
    };
    return results
        .map((row) => createSearchResult(row))
        .toList(growable: false);
  }

  // TODO: Named optional parameters
  List<Term> searchTerms(
    String term, {
    SearchMode searchMode = SearchMode.exact,
    List<String> dictionaryFilter = const [],
    bool deinflectTerms = true,
  }) {
    // TODO: Preprocessor rule chain candidates

    // TODO: We shuold probably have a combined type that is dictionaryEntry or something so that we can display that the text was deinflected from specific rule
    final List<Term> dictionaryTerms;
    if (!deinflectTerms) {
      dictionaryTerms = searchTermsInDictionary(term,
          searchMode: searchMode, dictionaryFilter: dictionaryFilter);
    } else {
      final engine = JapaneseEngine();
      final searchCandidates = engine.deinflect(term);
      dictionaryTerms =
          searchCandidates.expand((candidate) =>
              searchTermsInDictionary(
                candidate.text,
                searchMode: searchMode,
                dictionaryFilter: dictionaryFilter,
              )).toList();
      // TODO: If the dictionary has deinflection/part of speech tags, merge dictionary entries
      // We shuold do it regardless and have the source be dictionary, algorithm, or both
    }

    // TODO: Implement sorting and grouping of dictionary terms
    // TODO: Implement sorting terms based off frequency from a specified frequency dictionary as well


    return dictionaryTerms;
  }

  // TODO: Named optional parameters
  List<Term> searchTermsInDictionary(String term,
      {SearchMode searchMode = SearchMode.exact,
      List<String> dictionaryFilter = const [],
      List<DeinflectedText> deinflectionCandidates = const [],}) {
    return search<Term>(
      'terms',
      'term',
      term,
      searchMode,
      (result) => Term(
        term: result['term'] as String,
        reading: result['reading'] as String,
        definitions: (jsonDecode(result['definitions']) as List<dynamic>)
            .map((definition) =>
                Definition.fromJson(definition, result['dictionary']))
            .toList(),
        termTags: (result['termTags'] as String).split(' '),
        definitionTags: (result['definitionTags'] as String).split(' '),
        inflections: (result['inflectionRules'] as String).split(' '),
        popularity: result['popularity'] as num,
        sequenceNumber: result['sequenceNumber'] as int,
      ),
      dictionaryFilter,
    );
  }

  List<Term> searchTermsBySequenceNumber(int sequenceNumber,
      [List<String> dictionaryFilter = const []]) {
    return search<Term>(
      'terms',
      'sequenceNumber',
      sequenceNumber.toString(),
      SearchMode.exact,
      (result) => Term(
        term: result['term'] as String,
        reading: result['reading'] as String,
        definitions: (jsonDecode(result['definitions']) as List<dynamic>)
            .map((definition) =>
                Definition.fromJson(definition, result['dictionary']))
            .toList(),
        termTags: (result['termTags'] as String).split(' '),
        definitionTags: (result['definitionTags'] as String).split(' '),
        inflections: (result['inflectionRules'] as String).split(' '),
        popularity: result['popularity'] as num,
        sequenceNumber: result['sequenceNumber'] as int,
      ),
      dictionaryFilter,
    );
  }

  // TODO: Term meta objects should probably have a dictionary name attached to them (same goes for terms, kanji and kanji meta)
  List<TermMetadata> searchTermMeta(String term,
      [List<String> dictionaryFilter = const []]) {
    return search<TermMetadata>(
      'termsMeta',
      'term',
      term,
      SearchMode.exact,
      (result) {
        Map<String, dynamic> data = jsonDecode(result['data']);
        return switch (result['metaType']) {
          'frequency' => TermFrequency(
              result['dictionary'],
              term,
              result['reading'],
              frequency: data['frequency'],
              displayFrequency: data['displayFrequency'],
            ),
          'pitch' => TermPitch(
              result['dictionary'],
              term,
              result['reading'],
              data['downstepPosition'],
              nasalPositions: (data['nasalPositions'] as List<dynamic>)
                  .map((e) => int.parse(e))
                  .toList(),
              devoicePositions: (data['devoicePositions'] as List<dynamic>)
                  .map((e) => int.parse(e))
                  .toList(),
              tags: (data['tags'] as List<dynamic>)
                  .map((e) => e as String)
                  .toList(),
            ),
          'ipa' => TermIPA(
              result['dictionary'],
              term,
              result['reading'],
              data['transcription'],
              tags: (data['tags'] as List<dynamic>)
                  .map((e) => e as String)
                  .toList(),
            ),
          _ => throw FormatException(
              'Unknown metaType for termsMeta: ${result['metaType']}: $result'),
        };
      },
      dictionaryFilter,
    );
  }
}

enum SearchMode {
  exact,
  prefix,
  suffix,
  contains,
}

sealed class Dictionary {
  DictionaryMetadata metadata;

  Dictionary(this.metadata);
}

class YomichanDictionary extends Dictionary {
  List<Term> terms;
  List<TermMetadata> termsMeta;
  List<Kanji> kanji;
  List<KanjiMetadata> kanjiMeta;
  List<Tag> tags;

  void addContent(
      {List<dynamic> termsData = const [],
      List<dynamic> termsMetaData = const [],
      List<dynamic> kanjiData = const [],
      List<dynamic> kanjiMetaData = const [],
      List<dynamic> tagsData = const []}) {
    terms = YomichanDictionary.parseTermBank(termsData, terms);
    termsMeta = YomichanDictionary.parseTermMetaBank(termsMetaData, termsMeta);
    kanji = YomichanDictionary.parseKanjiBank(kanjiData, kanji);
    kanjiMeta = YomichanDictionary.parseKanjiMetaBank(kanjiMetaData, kanjiMeta);
    tags = YomichanDictionary.parseTagBank(tagsData, tags);
  }

  YomichanDictionary(
      {required DictionaryMetadata metadata,
      List<dynamic> termsData = const [],
      List<dynamic> termsMetaData = const [],
      List<dynamic> kanjiData = const [],
      List<dynamic> kanjiMetaData = const [],
      List<dynamic> tagsData = const []})
      : terms = YomichanDictionary.parseTermBank(termsData),
        termsMeta = YomichanDictionary.parseTermMetaBank(termsMetaData),
        kanji = YomichanDictionary.parseKanjiBank(kanjiData),
        kanjiMeta = YomichanDictionary.parseKanjiMetaBank(kanjiMetaData),
        tags = YomichanDictionary.parseTagBank(tagsData),
        super(metadata);

  YomichanDictionary.empty(DictionaryMetadata metadata)
      : terms = [],
        termsMeta = [],
        kanji = [],
        kanjiMeta = [],
        tags = [],
        super(metadata);

  static Future<DictionaryMetadata?> parseMetadata(String metadata,
      [String? cssStyle]) async {
    // TODO: Should we validate metadata here or in the validate method or both?
    if (!(await _DictionaryConstants.metadataSchema)
        .validate(metadata, parseJson: true)
        .isValid) {
      return null;
    }
    Map<String, dynamic> parsed = jsonDecode(metadata);
    var args = <Symbol, dynamic>{};
    parsed.forEach((key, value) {
      switch (key) {
        case 'version':
          args[const Symbol('version')] = value;
          break;
        case 'frequencyMode':
          args[Symbol(key)] = value == 'rank-based'
              ? DictionaryFrequencyMode.rankBased
              : DictionaryFrequencyMode.occurrenceBased;
          break;
        default:
          args[Symbol(key)] = value;
      }
    });
    if (cssStyle != null) {
      args[const Symbol('cssStyle')] = cssStyle;
    }
    DictionaryMetadata dictionaryMetadata =
        Function.apply(DictionaryMetadata.new, [], args);
    return dictionaryMetadata;
  }

  static Future<bool> parseAndImportDictionary(
      Archive dictionaryArchive) async {
    final dictionary = await parseDictionary(dictionaryArchive);
    if (dictionary == null) {
      return false;
    }
    final db = await DictionaryManager.instance;
    // TODO: Both must be canceled if one of them throws an exception

    if (db.dictionaryAlreadyImported(dictionary.metadata.title)) {
      print(
          '${dictionary.metadata.title} already imported into db, ignoring import request');
      return false;
    }
    await Future.wait([
      db._importDictionary(dictionary),
      db._importDictionaryMedia(dictionary.metadata, dictionaryArchive)
    ]);
    return true;
  }

  static Future<YomichanDictionary?> parseDictionary(
      Archive dictionaryArchive) async {
    // Duplicate
    RegExp jsonExp = RegExp(r'(?<name>.+)_(?<count>\d+)\.json$');

    var index = dictionaryArchive.findFile('index.json');
    if (index == null) {
      return null;
    }

    var styles = dictionaryArchive.findFile('styles.css');
    String? style = styles != null ? utf8.decode(styles.content) : null;

    DictionaryMetadata? metadata =
        await parseMetadata(utf8.decode(index.content), style);
    if (metadata == null) {
      return null;
    }

    final dictionary = YomichanDictionary.empty(metadata);
    int mediaCount = 0;
    for (var file in dictionaryArchive.files) {
      var match = jsonExp.firstMatch(file.name);
      if (match == null) {
        if (!file.isFile ||
            file.name == 'index.json' ||
            file.name == 'styles.css') {
          continue;
        }
        // Media that will be imported onto disk
        // TODO: Make this method actually call the import so this is basically a factory method
        metadata.mediaFiles.add(file.name);
        mediaCount++;
        continue;
      }
      switch (match.namedGroup('name')) {
        case 'kanji_bank':
          print('parsing kanji bank ${file.name}');
          List<dynamic> kanjiBank = jsonDecode(utf8.decode(file.content));
          dictionary.addContent(kanjiData: kanjiBank);
          break;
        case 'kanji_meta_bank':
          print('parsing kanji meta bank ${file.name}');
          List<dynamic> kanjiMetaBank = jsonDecode(utf8.decode(file.content));
          dictionary.addContent(kanjiMetaData: kanjiMetaBank);
          break;
        case 'term_bank':
          print('parsing terms ${file.name}');
          List<dynamic> termBank = jsonDecode(utf8.decode(file.content));
          dictionary.addContent(termsData: termBank);
          break;
        case 'term_meta_bank':
          print('parsing term meta ${file.name}');
          List<dynamic> termMetaBank = jsonDecode(utf8.decode(file.content));
          dictionary.addContent(termsMetaData: termMetaBank);
          break;
        case 'tag_bank':
          print('parsing tag bank ${file.name}');
          List<dynamic> tagBank = jsonDecode(utf8.decode(file.content));
          dictionary.addContent(tagsData: tagBank);
          break;
      }
    }
    print('there are $mediaCount possibly media files');
    print('done');
    return dictionary;
  }

  static Future<bool> validateDictionary(
      Archive dictionary, int dictionaryFormat) async {
    final index = dictionary.findFile('index.json');
    if (index == null) {
      return false;
    }
    // We can ignore styles.css in validation
    final metadata = await parseMetadata(utf8.decode(index.content));
    if (metadata == null) {
      return false;
    }
    final fileExp = RegExp(r'(?<name>.+)_(?<count>\d+)\.json$');
    if (metadata.format != 1 && metadata.format != 3) {
      return false;
    }

    Map<YomichanDictionaryFileType, int> numberedFileCount = {};
    Map<YomichanDictionaryFileType, int> numberedFileMax = {};

    for (var file in dictionary.files) {
      YomichanDictionaryFileType? numberedFileType;
      // Potentially a numbered file if valid
      JsonSchema? schema;
      var match = fileExp.firstMatch(file.name);
      if (match == null) {
        continue;
      }

      print(
          'Attempt to match potentially numbered file ${file.name} with name ${match.namedGroup('name')} and num ${match.namedGroup('count')}');
      switch (match.namedGroup('name')) {
        case 'kanji_bank':
          schema = await (metadata.format == 1
              ? _DictionaryConstants.kanjiBankV1Schema
              : _DictionaryConstants.kanjiBankV3Schema);
          numberedFileType = YomichanDictionaryFileType.kanjiBank;
          break;
        case 'kanji_meta_bank':
          numberedFileType = YomichanDictionaryFileType.kanjiMetaBank;
          schema = await _DictionaryConstants.kanjiMetaBankSchema;
          break;
        case 'term_bank':
          numberedFileType = YomichanDictionaryFileType.termBank;
          schema = await (metadata.format == 1
              ? _DictionaryConstants.termBankV1Schema
              : _DictionaryConstants.termBankV3Schema);
          break;
        case 'term_meta_bank':
          numberedFileType = YomichanDictionaryFileType.termMetaBank;
          schema = await _DictionaryConstants.termMetaBankSchema;
          break;
        case 'tag_bank':
          numberedFileType = YomichanDictionaryFileType.tagBank;
          schema = await _DictionaryConstants.tagBankSchema;
          break;
      }

      if (numberedFileType != null) {
        numberedFileCount.putIfAbsent(numberedFileType, () => 0);
        numberedFileMax.putIfAbsent(numberedFileType, () => 0);
        numberedFileCount[numberedFileType] =
            numberedFileCount[numberedFileType]! + 1;
        numberedFileMax[numberedFileType] = max(
            numberedFileMax[numberedFileType]!,
            int.tryParse(match.namedGroup('count') ?? '0') ?? 0);
      }
      if (schema == null) {
        print('Skipping file ${file.name}');
        continue;
      }

      print(
          'Validating with schema ${schema.id} for file ${file.name} ($numberedFileType)');
      var result = schema.validate(utf8.decode(file.content), parseJson: true);
      if (!result.isValid) {
        for (var e in result.errors) {
          print(e.message.substring(0, 100));
        }
        return false;
      }
    }

    // Validate that the the numbered files are in increasing order without
    // skipping numbers
    for (var fileType in YomichanDictionaryFileType.values) {
      print(
          '$fileType has count ${numberedFileCount[fileType]} and max ${numberedFileMax[fileType]}');
      if (numberedFileCount.containsKey(fileType) &&
          numberedFileMax.containsKey(fileType) &&
          numberedFileCount[fileType] != numberedFileMax[fileType]) {
        return false;
      }
    }
    print('successfully validated archive');
    return true;
  }

  static List<Term> parseTermBank(List<dynamic> termBank, [List<Term>? terms]) {
    // Term Bank Format:
    // Each item is a term, typed List<dynamic>
    // term has 8 items
    // 0: String text
    // 1: String reading ('' if reading == text)
    // 2: String space-separated definitionTags ('' if no tags)
    // 3: String spaced-separated rule identifiers to validate deinflection ('' if no inflection rules)
    // 4: num popularity (set of all integers or reals)
    // 5: List<dynamic> definitions
    // 6: int sequenceNumber (can merge output of 2 terms with same sequenceNumber)
    // 7: String space-separated termTags ('' if no tags)
    // for (var termJson in termBank) {
    terms ??= [];
    for (final [
          String term,
          String reading,
          String? definitionTags,
          String inflectionRules,
          num popularity,
          List<dynamic> definitions,
          int sequenceNumber,
          String termTags
        ] in termBank) {
      terms.add(Term.rawDefinitions(
        term: term,
        reading: reading,
        definitions: definitions // Definitions will be parsed on term lookup
            .map((e) => BasicDefinition(jsonEncode(e), ''))
            .toList(growable: false),
        termTags: termTags.split(' '),
        definitionTags: (definitionTags ?? '').split(' '),
        inflections: inflectionRules.split(' '),
        popularity: popularity,
        sequenceNumber: sequenceNumber,
      ));
    }
    print(
        'Processed from ${termBank.length} terms in bank to ${terms.length} terms in list');
    return terms;
  }

  // TODO: Test
  static List<Term> parseTermBankV1(List<dynamic> termBank,
      [List<Term>? terms]) {
    // Format:
    // 0: Array:
    //    0: String text
    //    1: String reading ('' if reading == text)
    //    2: String space-separate definitionTags ('' or null if no tags)
    //    3: String space-separated inflectionRules
    //    4: num popularity
    // ...: String definition
    terms ??= [];
    for (final [List<dynamic> attributes, ...definitions] in termBank) {
      // terms.putIfAbsent(attributes[0], () => []);
      // terms[attributes[0]]!.add(Term(
      terms.add(Term(
        term: attributes[0],
        reading: (attributes[1] ?? '') == '' ? attributes[0] : attributes[1],
        definitions: definitions
            .map((definitionText) =>
                BasicDefinition(definitionText.toString(), ''))
            .toList(),
        termTags: [],
        definitionTags: (attributes[2] as String).split(' '),
        inflections: (attributes[3] as String).split(' '),
        popularity: attributes[4],
        sequenceNumber: 0,
      ));
    }
    return terms;
  }

  // TODO: Move this to imageDefinition class?

  static List<Kanji> parseKanjiBank(List<dynamic> kanjiBank,
      [List<Kanji>? kanjiList]) {
    // kanjiBank Format:
    // 0: String: Kanji character
    // 1: String: Space-separated onyomi readings
    // 2: String: Space-separated kunyomi readings
    // 3: String: Space-separated tags
    // 4: List<String> definitions
    // 5: Map<String, dynamic> stats
    kanjiList ??= [];
    for (final [
          String kanji,
          String spaceSepOnyomi,
          String spaceSepKunyomi,
          String spaceSepTags,
          List<dynamic> definitions,
          Map<String, dynamic> stats
        ] in kanjiBank) {
      // kanjiMap.putIfAbsent(kanji, () => []);
      // kanjiMap[kanji]!.add(Kanji(
      kanjiList.add(Kanji(
        kanji: kanji,
        definitions: definitions.map((e) => e.toString()).toList(),
        onyomiReadings: spaceSepOnyomi.split(' '),
        kunyomiReadings: spaceSepKunyomi.split(' '),
        tags: spaceSepTags.split(' '),
        stats: stats.map((k, v) => MapEntry<String, String>(k, v.toString())),
      ));
    }
    print(
        'Parsed ${kanjiList.length} unique kanji from ${kanjiBank.length} entries');
    return kanjiList;
  }

  // TODO: Test
  static List<Kanji> parseKanjiBankV1(List<dynamic> kanjiBank,
      [List<Kanji>? kanjiList]) {
    // Format:
    // 0: Attributes Format:
    //    0: String character
    //    1: String space-separated onyomiReadings
    //    2: String space-separated onyomiReadings
    //    3: String space-separated tags
    // ...: List<String> meanings
    kanjiList ??= [];
    for (final [
          [
            String kanji,
            String spaceSepOnyomi,
            String spaceSepKunyomi,
            String spaceSepTags
          ],
          ...definitions
        ] in kanjiBank) {
      kanjiList.add(Kanji(
        kanji: kanji,
        definitions: definitions.map((e) => e.toString()).toList(),
        onyomiReadings: spaceSepOnyomi.split(' '),
        kunyomiReadings: spaceSepKunyomi.split(' '),
        tags: spaceSepTags.split(' '),
        stats: {},
      ));
    }
    return kanjiList;
  }

  static List<TermMetadata> parseTermMetaBank(List<dynamic> termMetaBank,
      [List<TermMetadata>? termsMetadata]) {
    // static Map<String, List<TermMetadata>> parseTermMetaBank(
    //     List<dynamic> termMetaBank,
    //     [Map<String, List<TermMetadata>> termsMetadata = const {}]) {
    // termMetaBank Format:
    // 0: String: Text for the term
    // 1: String: Type of metadata ('freq', 'pitch', 'ipa')
    // 2: OneOf(num, String, Map<String, dynamic>): Respective metadata for the term
    termsMetadata ??= [];
    for (final [String term, String type, dynamic data] in termMetaBank) {
      // if (termsMetadata.containsKey(term)) {}
      // termsMetadata.putIfAbsent(term, () => []);

      // termsMetadata[term]!.addAll(switch (type) {
      termsMetadata.addAll(switch (type) {
        'freq' => [parseTermFrequency(term, data)],
        'pitch' => parseTermPitch(term, data),
        'ipa' => parseTermIPA(term, data),
        _ => throw FormatException('Unknown term metadata type: $type'),
      });
    }
    print(
        'Parsed metadata for ${termsMetadata.length} terms from ${termMetaBank.length} items');
    return termsMetadata;
  }

  static List<KanjiMetadata> parseKanjiMetaBank(List<dynamic> kanjiMetaBank,
      [List<KanjiMetadata>? kanjiMetadata]) {
    // static Map<String, List<KanjiMetadata>> parseKanjiMetaBank(
    //     List<dynamic> kanjiMetaBank,
    //     [Map<String, List<KanjiMetadata>> kanjiMetadata = const {}]) {
    // kanjiMetaBank Format:
    // 0: String kanji
    // 1: String type == 'freq' (as specified in kanjiMetaBank schema)
    // 2: OneOf(num, String, Map<String, dynamic>): Frequency metadata
    kanjiMetadata ??= [];
    for (final [String kanji, ..., dynamic data] in kanjiMetaBank) {
      // kanjiMetadata.putIfAbsent(kanji, () => []);
      // kanjiMetadata[kanji]!.add(switch (data) {
      kanjiMetadata.add(switch (data) {
        num frequency => KanjiMetadata(kanji, frequency: frequency),
        String displayFrequency =>
          KanjiMetadata(kanji, displayFrequency: displayFrequency),
        Map<String, dynamic> data => KanjiMetadata(kanji,
            frequency: data['value'], displayFrequency: data['displayValue']),
        _ => throw FormatException(
            'Unknown data of type ${data.runtimeType} for parseKanjiMetaBank'),
      });
    }
    print(
        'Parsed metadata for ${kanjiMetadata.length} kanji from ${kanjiMetaBank.length} items');
    return kanjiMetadata;
  }

  static TermFrequency parseTermFrequency(String term, dynamic data) {
    //  Format:
    //  OneOf(
    //    num value,
    //    String displayValue,
    //    {
    //      reading: String,
    //      value: num,
    //      displayValue: String,
    //    },
    //  )
    switch (data) {
      case num frequency:
        return TermFrequency('', term, term, frequency: frequency);
      case String displayFrequency:
        return TermFrequency('', term, term,
            displayFrequency: displayFrequency);
      case Map<String, dynamic> frequencyMap
          when !frequencyMap.containsKey('reading'):
        return TermFrequency('', term, term,
            frequency: frequencyMap['value'],
            displayFrequency: frequencyMap['displayValue']);
      case {'reading': String reading, 'frequency': num frequency}:
        return TermFrequency('', term, reading, frequency: frequency);
      case {'reading': String reading, 'frequency': String displayFrequency}:
        return TermFrequency('', term, reading,
            displayFrequency: displayFrequency);
      case {
          'reading': String reading,
          'frequency': Map<String, dynamic> frequencyMap,
        }:
        return TermFrequency('', term, reading,
            frequency: frequencyMap['value'],
            displayFrequency: frequencyMap['displayValue']);
      case _:
        throw FormatException(
            'Unknown data of type ${data.runtimeType} for parseTermFrequency: ${data.toString()}');
    }
  }

  static List<TermPitch> parseTermPitch(
      String term, Map<String, dynamic> data) {
    //  Format:
    //  {
    //    reading: String,
    //    pitches: List<
    //      position: int,
    //      nasal: OneOf(int, List<int>),
    //      devoice: OneOf(int, List<int>),
    //      tags: List<String>,
    //    >,
    //  }
    List<TermPitch> termPitches = [];
    final {'reading': String reading, 'pitches': List<dynamic> pitches} = data;
    for (final pitch in pitches) {
      int downstep = pitch['position'];
      // Can't do optional keys in map patterns?
      List<int> nasal = switch (pitch['nasal']) {
        int n => [n],
        List<int> n => n,
        _ => [],
      };
      List<int> devoice = switch (pitch['devoice']) {
        int d => [d],
        List<int> d => d,
        _ => [],
      };
      List<String> tags = pitch['tags'] ?? [];
      termPitches.add(TermPitch(
        '',
        term,
        reading,
        downstep,
        nasalPositions: nasal,
        devoicePositions: devoice,
        tags: tags,
      ));
    }
    return termPitches;
  }

  // TODO: Test this
  static List<TermIPA> parseTermIPA(String term, Map<String, dynamic> data) {
    //  Format:
    //  {
    //    reading: String,
    //    transcriptions: List<{
    //        ipa: String,
    //        tags: List<String>,
    //      }>,
    //  }
    List<TermIPA> termIPAs = [];
    final {
      'reading': String reading,
      'transcriptions': List<dynamic> transcriptions
    } = data;
    for (final transcription in transcriptions) {
      String ipa = transcription['ipa'];
      List<String> tags = transcription['tags'] ?? [];
      termIPAs.add(TermIPA('', term, reading, ipa, tags: tags));
    }
    return termIPAs;
  }

  static List<Tag> parseTagBank(List<dynamic> tagBank, [List<Tag>? tags]) {
    // static Map<String, Tag> parseTagBank(List<dynamic> tagBank,
    //     [Map<String, Tag> tags = const {}]) {
    // tagBank Format:
    // 0: String name
    // 1: String category
    // 2: num sortingOrder
    // 3: String notes
    // 4: num popularity
    tags ??= [];
    for (final [
          String name,
          String category,
          num sortingOrder,
          String notes,
          num popularity
        ] in tagBank) {
      // if (tags.containsKey(name)) {
      //   print('Duplicate tag info for $name in tagBank found');
      // }
      tags.add(Tag(
        name: name,
        category: category,
        sortingOrder: sortingOrder,
        notes: notes,
        popularity: popularity,
      ));
    }
    return tags;
  }
}

class DictionaryMetadata {
  String title;
  String revision;
  bool sequenced;
  int format;
  String author;
  String url;
  String description;
  String attribution;
  String sourceLanguage;
  String targetLanguage;
  DictionaryFrequencyMode frequencyMode;
  String cssStyle;
  List<String> mediaFiles;

  DictionaryMetadata({
    required this.title,
    required this.revision,
    this.sequenced = false,
    required this.format,
    this.author = '',
    this.url = '',
    this.description = '',
    this.attribution = '',
    this.sourceLanguage = '',
    this.targetLanguage = '',
    this.frequencyMode = DictionaryFrequencyMode.occurrenceBased,
    this.cssStyle = '',
    List<String>? mediaFiles,
  }) : mediaFiles = mediaFiles ?? [];

  @override
  String toString() {
    return '''
    Title: $title
    Revision: $revision
    Sequenced: $sequenced
    Format: $format
    Author: $author
    URL: $url
    Description: $description
    Attribution: $attribution
    Source Language: $sourceLanguage
    Target Language: $targetLanguage
    Frequency Mode: $frequencyMode
    Custom Styling: ${cssStyle.isNotEmpty}
    ''';
  }
}

enum DictionaryFrequencyMode {
  occurrenceBased, // Default value
  rankBased,
}

enum YomichanDictionaryFileType {
  metadata,
  customAudioList,
  kanjiBank,
  kanjiMetaBank,
  termBank,
  termMetaBank,
  tagBank,
}

class Term {
  String term;
  String reading;
  List<Definition> definitions;
  List<String> termTags;
  List<String> definitionTags;
  List<String> inflections;
  num popularity;
  int sequenceNumber;

  Term({
    required this.term,
    required this.reading,
    required this.definitions,
    required this.termTags,
    required this.definitionTags,
    required this.inflections,
    required this.popularity,
    required this.sequenceNumber,
  });

  Term.rawDefinitions({
    required this.term,
    required this.reading,
    required List<BasicDefinition> this.definitions,
    required this.termTags,
    required this.definitionTags,
    required this.inflections,
    required this.popularity,
    required this.sequenceNumber,
  });
}

class Kanji {
  String kanji;
  List<String> definitions;
  List<String> onyomiReadings;
  List<String> kunyomiReadings;
  List<String> tags;
  Map<String, String> stats;

  Kanji({
    required this.kanji,
    required this.definitions,
    required this.onyomiReadings,
    required this.kunyomiReadings,
    required this.tags,
    required this.stats,
  });
}

sealed class Definition {
  String dictionary;

  Future<String> getDefinitionText();

  Definition(this.dictionary);

  factory Definition.fromJson(dynamic definitionJson, String dictionary) {
    return switch (definitionJson) {
      String textDefinition => BasicDefinition(textDefinition, dictionary),
      Map<String, dynamic> detailedDefinition => switch (
            definitionJson['type']) {
          'text' => BasicDefinition(detailedDefinition['text'], dictionary),
          'structured-content' => StructuredContent.fromJson(
              detailedDefinition['content'], dictionary),
          'image' => ImageDefinition.fromJson(detailedDefinition, dictionary),
          _ => throw FormatException(
              'Unknown detailed definition type: ${definitionJson["type"]}'),
        },
      List<dynamic> deinflectionRule => DeinflectionDefinition(
          deinflectionRule[0], deinflectionRule[1], dictionary),
      _ => throw FormatException(
          'Unknown definition type ${definitionJson.runtimeType}: $definitionJson'),
    };
  }
}

class BasicDefinition extends Definition {
  String definition;

  BasicDefinition(this.definition, String dictionary) : super(dictionary);

  @override
  Future<String> getDefinitionText() async => definition;
}

class DeinflectionDefinition extends Definition {
  String uninflectedTerm;

  // Chain of inflection rules to produce uninflectedTerm
  List<String> inflectionRules;

  DeinflectionDefinition(
      this.uninflectedTerm, this.inflectionRules, String dictionary)
      : super(dictionary);

  @override
  Future<String> getDefinitionText() async {
    print(
        'Warning: Deinflection definition found: inflected form of $uninflectedTerm with the following rules: ${inflectionRules.join(', ')}');
    return jsonEncode({
      'uninflectedTerm': uninflectedTerm,
      'inflectionRules': inflectionRules,
    });
  }
}

class ImageDefinition extends Definition {
  String path;
  int width;
  int height;
  String title;
  String alt;
  String description;
  bool pixelated;
  ImageRendering imageRendering;
  ImageAppearance appearance;
  bool background;
  bool collapsed;
  bool collapsible;

  ImageDefinition(
    String dictionary, {
    required this.path,
    this.width = 0,
    this.height = 0,
    this.title = '',
    this.alt = '',
    this.description = '',
    this.pixelated = false,
    this.imageRendering = ImageRendering.auto,
    this.appearance = ImageAppearance.auto,
    this.background = true,
    this.collapsed = false,
    this.collapsible = true,
  }) : super(dictionary);

  // TODO: Test
  @override
  Future<String> getDefinitionText() async {
    return await HtmlTag.imgTag(dictionary, dataAttributes: {
      'path': path,
      'width': width,
      'height': height,
      'title': title,
      'alt': alt,
      'description': description,
      'pixelated': pixelated,
      'imageRendering': imageRendering.name,
      'appearance': appearance.name,
      'background': background,
      'collapsed': collapsed,
      'collapsible': collapsible,
    }).getDefinitionText();
    // return jsonEncode({
    //   'path': path,
    //   'width': width,
    //   'height': height,
    //   'title': title,
    //   'alt': alt,
    //   'description': description,
    //   'pixelated': pixelated,
    //   'imageRendering': imageRendering.toString(),
    //   'appearance': appearance.toString(),
    //   'background': background,
    //   'collapsed': collapsed,
    //   'collapsible': collapsible,
    // });
  }

  factory ImageDefinition.fromJson(
      Map<String, dynamic> definition, String dictionary) {
    Map<Symbol, dynamic> args = {};
    for (var key in definition.keys) {
      switch (key) {
        case 'type':
          break;
        case 'path':
        case 'title':
        case 'alt':
        case 'description':
          args[Symbol(key)] = definition[key] as String;
        case 'width':
        case 'height':
          args[Symbol(key)] = definition[key] as int;
        case 'pixelated':
        case 'background':
        case 'collapsed':
        case 'collapsible':
          args[Symbol(key)] = definition[key] as bool;
          break;
        case 'imageRendering':
          args[Symbol(key)] = switch (definition[key]) {
            'pixelated' => ImageRendering.pixelated,
            'crisp-edges' => ImageRendering.crispEdges,
            'auto' || _ => ImageRendering.auto,
          };
        case 'appearance':
          args[Symbol(key)] = definition[key] == 'monochrome'
              ? ImageAppearance.monochrome
              : ImageAppearance.auto;
      }
    }
    return Function.apply(ImageDefinition.new, [dictionary], args)
        as ImageDefinition;
  }
}

enum ImageRendering { auto, pixelated, crispEdges }

enum ImageAppearance {
  auto,
  monochrome,
}

abstract interface class StructuredContent extends Definition {
  // StructuredContent is basically html tags in json format
  // Therefore we'll treat StructuredContent as a tree node
  // which gives content inside of a paragraph (<p>...</p>)
  Future<String> getHtmlContent();

  @override
  Future<String> getDefinitionText() async => await getHtmlContent();

  StructuredContent(String dictionary) : super(dictionary);

  factory StructuredContent.fromJson(
      dynamic structuredContent, String dictionary) {
    // StructuredContent Format (Basically HTML tags turned into json):
    //  OneOf(
    //    String textNode,
    //    List<StructuredContent> childContent,
    //    OneOf( // Tags
    //      { // Empty tags
    //        tag: 'br',
    //        data: StructuredContentData,
    //      }, // Empty tags
    //      { // Generic container tags
    //        tag: OneOf(
    //          'ruby', 'rt', 'rp', 'table', 'thead', 'tbody', 'tfoot', 'tr',
    //          ),
    //        content: StructuredContent
    //        data: StructuredContentData
    //        lang: String
    //      }, // Generic container tags
    //      { // Table tags
    //        tag: OneOf(
    //          'td', 'th',
    //          ),
    //        content: StructuredContent
    //        data: StructuredContentData
    //        colSpan: int >=1,
    //        rowSpan: int >=1,
    //        style: StructuredContentStyle
    //        lang: String
    //      }, // Table tags
    //      { // Tags with configurable styles
    //        tag: OneOf(
    //          'span', 'div', 'ol', 'ul', 'li', 'details', 'summary'
    //          ),
    //        content: StructuredContent
    //        data: StructuredContentData
    //        style: StructuredContentStyle
    //        title: String
    //        lang: String
    //      }, // Tags with configurable styles
    //      { // Image tag
    //        tag: 'img',
    //        data: StructuredContentData
    //        path: String,
    //        width: num >= 0
    //        height: num >= 0
    //        title: String
    //        alt: String
    //        description: String
    //        pixelated: bool default = false
    //        imageRendering: OneOf(
    //          'auto', 'pixelated', 'crisp-edges',
    //          default: 'auto',
    //          )
    //        appearance: OneOf(
    //          'auto', 'monochrome',
    //          default: 'auto',
    //          )
    //        background: bool default = true
    //        collapsed: bool default = false
    //        collapsible: bool default = true
    //        verticalAlign: OneOf(
    //          'baseline', 'sub', 'super', 'text'-top',
    //          'text-bottom', 'middle', 'top', 'bottom',
    //          )
    //        border: String
    //        borderRadius: String
    //        sizeUnits: OneOf('px', 'em')
    //      }, // Image tag
    //      { // Link tag
    //        tag: 'a',
    //        content: StructuredContent,
    //        href: String follows matches regex r'^(?:https?:|\?)[\w\W]*',
    //        lang: String,
    //      }, // Link tag
    //    ), // Tags
    //  )
    return switch (structuredContent) {
      String content => TextContent(content, dictionary),
      List<dynamic> content => StructuredContentContainer(
          content
              .map((element) => StructuredContent.fromJson(element, dictionary))
              .toList(),
          dictionary),
      Map<String, dynamic> content when content['tag'] == 'br' =>
        HtmlTag.voidTag(
          dictionary,
          // img and br don't have style
          tag: content['tag'],
          dataAttributes: _getDataAttributes(content),
        ),
      Map<String, dynamic> content when content['tag'] == 'img' =>
        HtmlTag.imgTag(
          dictionary,
          dataAttributes: _getDataAttributes(content),
        ),
      Map<String, dynamic> content => HtmlTag(
          dictionary,
          tag: content['tag'],
          content: content['content'] != null
              ? StructuredContent.fromJson(content['content'], dictionary)
              : null,
          dataAttributes: _getDataAttributes(content),
          style: content['style'] ?? {},
        ),
      _ => throw FormatException(
          'Unknown runtime type of structured content: ${structuredContent.runtimeType}'),
    };
  }

  static Map<String, dynamic> _getDataAttributes(
          Map<String, dynamic> structuredContent) =>
      mergeMaps(
          structuredContent['data'] ?? {},
          Map<String, dynamic>.fromEntries(structuredContent.entries.where(
              (entry) =>
                  entry.key != 'tag' &&
                  entry.key != 'data' &&
                  entry.key != 'style' &&
                  entry.key != 'content')));
}

class TextContent extends StructuredContent {
  String text;

  TextContent(this.text, String dictionary) : super(dictionary);

  @override
  Future<String> getHtmlContent() async {
    return text;
  }
}

class StructuredContentContainer extends StructuredContent {
  List<StructuredContent> contents;

  StructuredContentContainer(this.contents, String dictionary)
      : super(dictionary);

  @override
  Future<String> getHtmlContent() async {
    final buffer = StringBuffer();
    for (final content in contents) {
      buffer.write(await content.getHtmlContent());
    }
    // print(buffer.toString());
    return buffer.toString();
  }
}

class HtmlTag extends StructuredContent {
  static Future<Uri> mediaBasePath = UserPreferences.preferencesDirectory.then(
      (preferencesDirectory) =>
          preferencesDirectory.resolve('/dictionaryMedia/'));

  String tag;
  StructuredContent? content;
  Map<String, dynamic> dataAttributes;
  Map<String, dynamic> style;
  bool voidTag = false;

  HtmlTag(String dictionary,
      {required this.tag,
      this.content,
      this.dataAttributes = const {},
      this.style = const {}})
      : super(dictionary);

  HtmlTag.voidTag(
    String dictionary, {
    required this.tag,
    this.dataAttributes = const {},
    this.style = const {},
  }) : super(dictionary) {
    voidTag = true;
  }

  factory HtmlTag.imgTag(
    String dictionary, {
    required Map<String, dynamic> dataAttributes,
    Map<String, dynamic>? style,
  }) {
    style ??= {};
    if (!dataAttributes.containsKey('path')) {
      throw const FormatException(
          'dataAttributes of img tag must contain path');
    }
    style.addAll(_filterStyleFromDataAttributes(dataAttributes));
    dataAttributes['src'] = dataAttributes.remove('path');
    bool? collapsible = dataAttributes.remove('collapsible');
    bool? collapsed = dataAttributes.remove('collapsed');
    return switch (collapsible) {
      true => HtmlTag(
          dictionary,
          tag: 'details',
          dataAttributes: (collapsed ?? false) ? const {} : {'open': ''},
          content: StructuredContentContainer(
            [
              HtmlTag(
                dictionary,
                tag: 'summary',
                // TODO: Should the summary text be blank or dataAttributes['description']
                content: TextContent(' ', dictionary),
              ),
              HtmlTag.voidTag(
                dictionary,
                tag: 'img',
                dataAttributes: dataAttributes,
                style: style,
              ),
            ],
            dictionary,
          ),
        ),
      false || null => HtmlTag.voidTag(
          dictionary,
          tag: 'img',
          dataAttributes: dataAttributes,
          style: style,
        ),
    };
  }

  static Map<String, dynamic> _filterStyleFromDataAttributes(
      Map<String, dynamic> attributes) {
    Map<String, dynamic> style = {};
    List<String> filteredAttributes = attributes.keys.toList();
    for (final MapEntry<String, dynamic>(key: String key, value: dynamic value)
        in attributes.entries) {
      switch (key) {
        case 'pixelated':
          if (attributes['imageRendering'] == null &&
              value.toString() == 'true') {
            style['image-rendering'] = 'pixelated';
          }
        case 'imageRendering':
          style['image-rendering'] = value as String;
        case 'appearance' when value == 'monochrome':
          // TODO: what the fuck does the schema want us to do
          break;
        case 'background':
          // TODO: also what the fuck
          break;
        case 'verticalAlign':
          style['vertical-align'] = value as String;
        case 'border':
          style['border'] = value as String;
        case 'borderRadius':
          style['border-radius'] = value as String;
        case _:
          filteredAttributes.remove(key);
      }
    }
    for (final key in filteredAttributes) {
      attributes.remove(key);
    }
    return style;
  }

  String _camelToParamCase(String text) => text.replaceAllMapped(
      RegExp(r'([A-Z])'), (match) => '-${match[0]!.toLowerCase()}');

  Future<String> _dataAttributesToString() async {
    return (await dataAttributes.entries
            .map((entry) async => await _preprocessDataAttribute(entry))
            .map((entry) async =>
                '${(await entry).key.toString()}="${(await entry).value.toString()}"')
            .wait)
        .join(' ');
  }

  // TODO: Test this
  String _styleToString() => style.entries
      .map((entry) => '${_camelToParamCase(entry.key)}:${entry.value};')
      .fold('', (prev, current) => '$prev $current');

  String _styleAsAttribute() {
    return _styleToString() != '' ? 'style="${_styleToString()}"' : '';
  }

  // TODO: We probably also need to do this with anchor tags
  // Though we would also have to handle hyperlinks prompting a search for other terms/kanji
  Future<MapEntry<String, dynamic>> _preprocessDataAttribute(
          MapEntry<String, dynamic> attribute) async =>
      switch (attribute.key) {
        'src' => MapEntry<String, dynamic>(
            attribute.key, await _resolveMediaPath(attribute.value)),
        _ => attribute,
      };

  Future<String> _resolveMediaPath(String path) async =>
      (await UserPreferences.preferencesDirectory)
          .resolve('dictionaryMedia/$dictionary/')
          .resolve(path)
          .toString();

  @override
  Future<String> getHtmlContent() async {
    notEmpty(String str) => str.isNotEmpty;
    return voidTag
        ? '<${[
            tag,
            await _dataAttributesToString()
          ].where(notEmpty).join(' ')}>'
        : '<${[
            tag,
            await _dataAttributesToString(),
            _styleAsAttribute()
          ].where(notEmpty).join(' ')}>${await content?.getHtmlContent() ?? ''}</$tag>';
  }
}

sealed class TermMetadata {
  String term;
  String reading;
  String dictionary;

  TermMetadata(this.term, this.reading, this.dictionary);

  String getMetadataType();

  Map<String, dynamic> toJson();
}

class TermFrequency extends TermMetadata {
  // TODO: If implementing frequency sorting, figure out to sort if only frequencyDisplayValue and it's some value like '1/10077' in Nier freq dict
  // By yomichan dictionary validation, at least one of the
  // following parameters must be non-null.
  num? frequency;
  String? displayFrequency;

  TermFrequency(String dictionary, String term, String reading,
      {this.frequency, this.displayFrequency})
      : super(term, reading, dictionary);

  @override
  String getMetadataType() => 'frequency';

  @override
  Map<String, dynamic> toJson() => {
        'frequency': frequency,
        'displayFrequency': displayFrequency,
      };
}

class TermPitch extends TermMetadata {
  int downstepPosition;
  List<int> nasalPositions;
  List<int> devoicePositions;
  List<String> tags;

  TermPitch(
      String dictionary, String term, String reading, this.downstepPosition,
      {this.nasalPositions = const [],
      this.devoicePositions = const [],
      this.tags = const []})
      : super(term, reading, dictionary);

  @override
  String getMetadataType() => 'pitch';

  @override
  Map<String, dynamic> toJson() {
    return {
      'downstepPosition': downstepPosition,
      'nasalPositions': nasalPositions,
      'devoicePositions': devoicePositions,
      'tags': tags,
    };
  }
}

class TermIPA extends TermMetadata {
  String transcription;
  List<String> tags;

  TermIPA(String dictionary, String term, String reading, this.transcription,
      {this.tags = const []})
      : super(term, reading, dictionary);

  @override
  String getMetadataType() => 'ipa';

  @override
  Map<String, dynamic> toJson() => {
        'transcription': transcription,
        'tags': tags,
      };
}

class KanjiMetadata {
  // Only possible metadata is frequency data for now
  String kanji;
  num? frequency;
  String? displayFrequency;

  KanjiMetadata(this.kanji, {this.frequency, this.displayFrequency});
}

class Tag {
  String name;
  String category;
  num sortingOrder;
  String notes;
  num popularity;

  Tag(
      {required this.name,
      required this.category,
      required this.sortingOrder,
      required this.notes,
      required this.popularity});
}
