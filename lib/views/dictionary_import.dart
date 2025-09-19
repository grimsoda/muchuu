import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:muchuu/dictionary/dictionary.dart';
import 'package:archive/archive_io.dart';
import 'package:muchuu/views/term_lookup.dart';
import 'package:path_provider/path_provider.dart';

// FIXME: Redo this whole thing, in fact just move this whole thing to a different section that complies with standards
class DictionaryImporterView extends StatefulWidget {
  const DictionaryImporterView({super.key});

  @override
  State<DictionaryImporterView> createState() => _DictionaryImporterViewState();
}

class _DictionaryImporterViewState extends State<DictionaryImporterView> {
  final _dictionaryPathController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  var _dictionaryMetadata = 'Sample Text';
  String? previousValidDictionary;
  YomichanDictionary? currentDictionary;

  Future<void> pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result != null) {
      setState(() {
        _dictionaryPathController.text = result.files.single.path!;
      });
    }
  }

  String? validateDictionary(String? path) {
    String? result =
        (path != null && path.endsWith('.zip') && File(path).existsSync())
            ? null
            : 'Must be a path to a valid dictionary (.zip)';
    if (result == null && previousValidDictionary != path) {
      previousValidDictionary = path;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        loadMetadata();
      });
    }
    return result;
  }

  bool canParseDictionary() => _formKey.currentState?.validate() ?? false;

  void loadMetadata() async {
    final inputStream = InputFileStream(_dictionaryPathController.text);
    final archive = ZipDecoder().decodeStream(inputStream);
    // final archive = ZipDecoder().decodeBuffer(inputStream);
    var index = archive.findFile('index.json');
    if (index == null) {
      setState(() {
        _dictionaryMetadata = 'Cannot find index.json from file';
      });
      return;
    }
    var metadata = await metadataToString(utf8.decode(index.content));
    setState(() {
      _dictionaryMetadata = metadata;
    });
  }

  Future<String> metadataToString(String content) async {
    DictionaryMetadata? metadata =
        await YomichanDictionary.parseMetadata(content);
    return metadata?.toString() ?? 'Failed to parse metadata';
  }

  Future<void> importDictionary() async {
    final inputStream = InputFileStream(_dictionaryPathController.text);
    final archive = ZipDecoder().decodeStream(inputStream);
    // final archive = ZipDecoder().decodeBuffer(inputStream);
    YomichanDictionary.parseAndImportDictionary(archive);
  }

  Future<void> importDictionaryTest() async {
    final inputStream = InputFileStream(_dictionaryPathController.text);
    final archive = ZipDecoder().decodeStream(inputStream);
    // final archive = ZipDecoder().decodeBuffer(inputStream);
    YomichanDictionary.parseDictionary(archive).then((dictionary) {
      setState(() {
        currentDictionary = dictionary;
      });
      // if (dictionary != null) {
      //   showDialog(
      //     context: context,
      //     barrierDismissible: false,
      //     builder: (BuildContext context) {
      //       return YomichanDictionarySearchView(dictionary: dictionary);
      //     },
      //   );
      // }
    });
    // currentDictionary = await YomichanParser.parseDictionary(archive);
  }

  Future<void> showTermLookupView() async => showDialog(
      context: context,
      builder: (BuildContext context) {
        return const TermLookupView();
      });

  void clearCurrentDictionary() {
    setState(() {
      currentDictionary = null;
      _dictionaryPathController.text = '';
    });
  }

  Future<bool> validateDictionaryContents() async {
    final inputStream = InputFileStream(_dictionaryPathController.text);
    final archive = ZipDecoder().decodeStream(inputStream);
    // final archive = ZipDecoder().decodeBuffer(inputStream);
    final index = archive.findFile('index.json');
    if (index == null) {
      return false;
    }
    var metadata =
        await YomichanDictionary.parseMetadata(utf8.decode(index.content));
    if (metadata == null) {
      return false;
    }
    return YomichanDictionary.validateDictionary(archive, metadata.format);
  }

  void printDirectoryPaths() {
    // Throws UnimplementedError if no such directory in platform
    getTemporaryDirectory().then((e) => print('Temp Dir: $e'));
    getApplicationSupportDirectory().then((e) => print('AppSupport Dir: $e'));
    getApplicationCacheDirectory().then((e) => print('AppCache Dir: $e'));
    getApplicationDocumentsDirectory().then((e) => print('AppDocs Dir: $e'));
    // getLibraryDirectory().then((e) => print('Library Dir: $e'));
    getDownloadsDirectory().then((e) => print('Downloads Dir: $e'));
    // getExternalStorageDirectory().then((e) => print('ExtStorage Dir: $e'));
  }

  @override
  void initState() {
    // _dictionaryPathController.addListener()

    super.initState();
  }

  @override
  void dispose() {
    _dictionaryPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Import Dictionary',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints.loose(const Size(400, 80)),
                child: TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _dictionaryPathController,
                  decoration: const InputDecoration(
                    hintText: 'The path to the dictionary.',
                    labelText: 'Dictionary Path *',
                  ),
                  validator: (String? value) {
                    return validateDictionary(value);
                  },
                ),
              ),
              const SizedBox(width: 5),
              FilledButton.tonal(
                onPressed: pickFile,
                child: const Text('Browse'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          canParseDictionary()
              ? Text(_dictionaryMetadata)
              : const SizedBox.shrink(),
          FilledButton(
            onPressed: canParseDictionary() ? validateDictionaryContents : null,
            child: const Text('Validate Contents of Dictionary'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: canParseDictionary() ? importDictionary : null,
            child: const Text('Parse and Import Dictionary'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: canParseDictionary() ? clearCurrentDictionary : null,
            child: const Text('Clear Current Dictionary'),
          ),
          const SizedBox(height: 10),
          currentDictionary != null
              ? Text(
                  'Lengths: kanji ${currentDictionary!.kanji.length}, kanjiMeta ${currentDictionary!.kanjiMeta.length}, term ${currentDictionary!.terms.length}, termMeta ${currentDictionary!.termsMeta.length}')
              : const SizedBox.shrink(),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: showTermLookupView,
            child: const Text('Show Term Lookup View'),
          ),
        ],
      ),
    );
  }
}
