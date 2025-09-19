import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class UserPreferences {
  static final Future<UserPreferences> instance = _getCurrentUserPreferences();

  static Uri? _preferencesDirectory;

  static Future<Uri> get preferencesDirectory async => _preferencesDirectory ??=
      Uri.directory((await getApplicationSupportDirectory()).path,
          windows: Platform.isWindows);

  static Uri? _preferencesFilePath;

  static Future<Uri> get preferencesFilePath async => _preferencesFilePath ??=
      (await preferencesDirectory).resolve('preferences.json');

  String _databasePath;

  String get databasePath => _databasePath;

  set databasePath(String path) {
    _databasePath = path;
    _onPreferencesChanged();
  }

  bool _useDatabaseFromDisk;

  bool get useDatabaseFromDisk => _useDatabaseFromDisk;

  set useDatabaseFromDisk(bool useDisk) {
    _useDatabaseFromDisk = useDisk;
    _onPreferencesChanged();
  }

  UserPreferences._init({
    required databasePath,
    useDatabaseFromDisk = true,
  })  : _databasePath = databasePath,
        _useDatabaseFromDisk = useDatabaseFromDisk;

  factory UserPreferences._fromJson(Map<String, dynamic> json) {
    print(json);
    return UserPreferences._init(
      databasePath: (json['databasePath'] ?? '$preferencesDirectory/db.sqlite3')
          as String,
      useDatabaseFromDisk: (json['useDatabaseFromDisk'] ?? true) as bool,
    );
  }

  static Future<UserPreferences> _getCurrentUserPreferences() async {
    try {
      return UserPreferences._fromJson(jsonDecode(
          await File.fromUri(await preferencesFilePath).readAsString()));
    } catch (e) {
      print(
          'Could not read current user preferences, using default preferences');
      return UserPreferences._init(
          databasePath: (await preferencesDirectory)
              .resolve('db.sqlite3')
              .toFilePath(windows: Platform.isWindows))
        ..exportPreferences();
    }
  }

  Map<String, dynamic> toJson() => {
        'databasePath': databasePath,
        'useDatabaseFromDisk': useDatabaseFromDisk,
      };

  Future<void> exportPreferences() async {
    File.fromUri(await preferencesFilePath).writeAsString(jsonEncode(this));
  }

  void _onPreferencesChanged() {
    // TODO: If we need more methods to access this we can just use streams as event handlers
    exportPreferences();
  }
}
