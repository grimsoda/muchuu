import 'dart:io';
import 'dart:ui';

import 'package:sqlite3/sqlite3.dart';

import '../books/book.dart';
import '../user_preferences.dart';

class DisplayBook {
  String fileHash;
  Uri fileUri;
  String type; // TODO: Should this merely be a String?
  String primaryTitle;
  List<String> otherTitles;
  int length;
  int currentProgress;
  Uri coverUri;

  double getProgressPercentage() => currentProgress / length;

  DisplayBook(
      {required this.fileHash,
      required this.fileUri,
      required this.type,
      required this.primaryTitle,
      this.otherTitles = const [],
      required this.length,
      required this.currentProgress,
      required this.coverUri});
}

class _LibraryConstants {
  static const Map<String, String> tableInitStatements = {
    // TODO: Figure out what books store
    // Basic book metadata
    // Path to cover image (or standardize it)
    // Root directory for book (cover/rendered doc)
    // We could possibly store the epub and render it in realtime anyway

    // TODO: Store book reading/completion data
    // We possibly store this on another table or maybe even database entirely
    // It may be important to link data if we wanted to view the stats for a specific book

    // Perhaps we can go off the unique identifier and then the primary title if two books so happen to have different
    // primary-identifier attributes

    'books': '''
    CREATE TABLE books (
    fileHash TEXT NOT NULL,
    filePath TEXT NOT NULL,
    primaryTitle TEXT NOT NULL,
    otherTitles TEXT,
    authorString TEXT NOT NULL,
    type TEXT NOT NULL,
    length INTEGER NOT NULL,
    currentProgress INTEGER NOT NULL,
    coverPath TEXT
    )
    ''',
  };

  _LibraryConstants._();
}

class LibraryManager {
  // TODO: We can probably abstract away instances of managers that interface with a database
  // Perhaps this can be an interface instead
  // Actually, inheritance may be preferred so we can reuse implementations

  static LibraryManager? _instance;

  static Future<LibraryManager> get instance async =>
      _instance ??= await _fromPreferences();

  late final Database _db;
  late final String? databaseLocation;
  final List<VoidCallback> _databaseChangedCallbacks = [];

  LibraryManager._internal();

  static Future<LibraryManager> _fromPreferences() async {
    final instance = LibraryManager._internal();
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
        ) in _LibraryConstants.tableInitStatements.entries) {
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
        in _LibraryConstants.tableInitStatements.entries) {
      _db.execute('DROP TABLE IF EXISTS $table');
      _db.execute(initSql);
    }
    _db.execute('vacuum');
    _onDatabaseChanged();
  }

  bool conflictingBookExists(String uniqueIdentifier, String title) {
    final result = _db.select(
        'SELECT * from books WHERE uniqueIdentifier = \'$uniqueIdentifier\' AND title = \'$title\'');
    return result.isNotEmpty;
  }

  // TODO: Make this return all books and return all fields
  List<String> getAllTitles() {
    return _db
        .select('SELECT * FROM books')
        .map((e) => e[0] as String)
        .toList(growable: false);
  }

  Future<void> addBookToLibrary(DisplayBook book) async {
    switch (book.type) {
      case ("epub"):
        // TODO: We need to get file hash

        throw UnimplementedError();
        addEpubToLibrary(book);
        break;
      default:
        throw UnimplementedError(
            'Unimplemented book subtype for addBookToLibrary');
        return;
    }
  }

  // 'books': '''
  //   CREATE TABLE books (
  //   fileHash TEXT NOT NULL,
  //   filePath TEXT NOT NULL,
  //   primaryTitle TEXT NOT NULL,
  //   otherTitles TEXT,
  //   authorString TEXT NOT NULL,
  //   type TEXT NOT NULL,
  //   length INTEGER NOT NULL,
  //   currentProgress INTEGER NOT NULL,
  //   coverPath TEXT
  //   )
  //   ''',

  // TODO: Test this
  Future<void> addEpubToLibrary(DisplayBook epub) async => _addRows<DisplayBook>('books', [
        ('uniqueIdentifier', (epub) => epub.fileHash),
        ('primaryTitle', (epub) => epub.primaryTitle),
        ('otherTitles', (epub) => epub.otherTitles.toString()),
        ('type', (_) => 'epub'),
        ('length', (epub) => epub.length),
        ('currentProgress', (_) => 0),
        (
          'coverPath',
          (epub) => epub.coverUri.toFilePath(windows: Platform.isWindows),
        ),
      ], [
        epub
      ]);

  void addBookAddedCallback(VoidCallback callback) {
    _databaseChangedCallbacks.add(callback);
  }

  bool removeBookAddedCallback(VoidCallback callback) {
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

  void _onDatabaseChanged() {
    print(
        'database changed, calling ${_databaseChangedCallbacks.length} callbacks');
    for (final callback in _databaseChangedCallbacks) {
      callback.call();
    }
  }

  List<DisplayBook> getEpubs(String? query) {
    ResultSet results = query != null
        ? _db.select(
            'SELECT * FROM books WHERE primaryTitle LIKE \'%(val)%\' AND type = \'epub\' VALUES (?)',
            [query])
        : _db.select('SELECT * FROM books WHERE type = \'epub\'');
    return results
        .map((row) => DisplayBook(
              fileHash: row['fileHash'] as String,
              fileUri: Uri.file(row['filePath'] as String),
              primaryTitle: row['primaryTitle'],
              otherTitles: row['otherTitles'] as List<String>,
              length: row['length'] as int,
              currentProgress: row['currentProgress'] as int,
              coverUri: Uri.file(row['coverPath']),
            ))
        .toList(growable: false);
  }

  List<T> search<T>(String table, String searchColumn, String query,
      T Function(Row) createSearchResult) {
    ResultSet results = _db.select(
        'SELECT * FROM books WHERE (col) LIKE \'%(val)%\' VALUES (?, ?)',
        [searchColumn, query]);
    return results
        .map((row) => createSearchResult(row))
        .toList(growable: false);
  }
}
