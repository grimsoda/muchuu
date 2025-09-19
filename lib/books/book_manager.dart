import 'package:muchuu/books/book_type.dart';
import 'package:muchuu/user_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

class BookManager {
  static BookManager? _instance;

  static Future<BookManager> get instance async =>
      _instance ??= await _fromPreferences();

  late Database _db;

  BookManager._internal();

  static Future<BookManager> _fromPreferences() async {
    // TODO: Should we store user preferences in a sqlite database alongside our books collection?
    // We're going to have a directory of books where it the collection should auto update
    // Book progress, bookmarks, and other info would be kept in sqlite database in separate tables
    // That way if a book is removed from the directory the stats don't disappear
    // Probably best to implement reading stats more complex than total time spent reading as one of the the last few things to be implemented
    // TODO: Maybe also have reread count?
    final instance = BookManager._internal();
    Uri dbPath =
        (await UserPreferences.preferencesDirectory).resolve('books.sqlite3');
    instance._db = sqlite3.open(dbPath.path);
    instance.initDatabaseTables();
    return instance;
  }

  void initDatabaseTables() {
    // TODO: Should hash/id be the primary key as opposed to title?
    _db.execute('''
    CREATE TABLE IF NOT EXISTS books (
    title TEXT NOT NULL PRIMARY KEY,
    hash TEXT NOT NULL,
    type TEXT NOT NULL,
    progress INTEGER NOT NULL,
    length INTEGER NOT NULL,
    collection TEXT
    )
    ''');
  }

  void addBook(
      String title, String hash, BookType bookType, int progress, int length,
      [String? collection]) {
    _db.execute(
        'INSERT INTO books (title, hash, type, progress, length, collection) VALUES (?, ?, ?, ?, ?, ?)',
        [title, hash, bookType, progress, length, collection]);
  }

  bool bookExists(String title, String hash) {
    final result =
        _db.select('SELECT title FROM books WHERE title = \'$title\'');
    return result.isNotEmpty;
  }

  ({int length, int progress})? getBookProgressAndLength(
      String title, String hash) {
    final result = _db
        .select('SELECT progress, length FROM books WHERE title = \'$title\'');
    return result.rows.isEmpty
        ? null
        : (
            progress: result[0]['progress'] as int,
            length: result[0]['length'] as int
          );
  }

  bool updateBookProgress(String title, String hash, int newProgress) {
    if (!bookExists(title, hash)) {
      return false;
    }
    _db.execute(
        'UPDATE books SET progress=? WHERE title=?', [newProgress, title]);
    return true;
  }
}
