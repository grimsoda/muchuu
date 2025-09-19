import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:muchuu/dictionary/dictionary.dart';
import 'package:muchuu/user_preferences.dart';

class DatabaseExportView extends StatefulWidget {
  const DatabaseExportView({super.key});

  @override
  State<DatabaseExportView> createState() => _DatabaseExportViewState();
}

class _DatabaseExportViewState extends State<DatabaseExportView> {
  String _lastResult = 'No Exports Yet';
  late String importedDictionaryCountText;

  Future<void> exportDatabase() async {
    String? initialDirectory = UserPreferences.preferencesDirectory == null
        ? null
        : '${UserPreferences.preferencesDirectory}${Platform.isWindows ? '\\' : '/'}';
    print(initialDirectory);
    String? result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Dictionary Database (sqlite3)',
      fileName: 'db.sqlite3',
      initialDirectory: initialDirectory,
    );
    if (result != null) {
      (await DictionaryManager.instance).exportDictionary(result);
      setState(() {
        _lastResult = 'Exported at ${DateTime.timestamp()}';
      });
    }
  }

  String fetchImportedDictionaryCount() {
    DictionaryManager.instance.then((instance) => setState(() {
          importedDictionaryCountText =
              '${instance.importedDictionaries().length} Dictionaries Imported';
        }));
    return ('Fetching Imported Dictionary Count');
  }

  @override
  void initState() {
    importedDictionaryCountText = fetchImportedDictionaryCount();
    DictionaryManager.instance.then((instance) =>
        instance.addDictionaryImportedCallback(fetchImportedDictionaryCount));
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Export Database',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            FilledButton.tonal(
              onPressed: exportDatabase,
              child: const Text('Export'),
            ),
            const SizedBox(width: 5),
            Text(_lastResult),
          ],
        ),
        const SizedBox(height: 10),
        Text(importedDictionaryCountText),
      ],
    );
  }
}
