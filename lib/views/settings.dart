import 'package:flutter/material.dart';
import 'package:muchuu/dictionary/dictionary.dart';
import 'package:muchuu/user_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  UserPreferences? userPreferences;

  @override
  void initState() {
    UserPreferences.instance.then((prefs) {
      setState(() {
        userPreferences = prefs;
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Dictionary Settings',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        Text(
            'Current Database Path: ${userPreferences?.databasePath ?? 'Not Yet Found'}'),
        const SizedBox(height: 10),
        FilledButton.tonal(
          onPressed: () async =>
              launchUrl(await UserPreferences.preferencesDirectory),
          child: const Text('Open Directory'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonal(
          style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent.shade700,
              backgroundColor: Colors.red.shade100),
          onPressed: _confirmResetDatabase,
          child: const Text('Reset all Tables'),
        )
      ],
    );
  }

  Future<void> _confirmResetDatabase() async {
    DictionaryManager instance = await DictionaryManager.instance;
    return showDialog(
        context: context, // TODO: Fix warning
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Reset Database'),
            content: SizedBox(
              width: 400,
              child: Text(
                  'This will remove all currently imported dictionaries from the currently imported database.\nDatabase Location: ${instance.databaseLocation ?? 'In Memory'}'),
            ),
            // TODO: Show path of current database
            actions: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent.shade700),
                onPressed: () {
                  DictionaryManager.instance.then((_) => _.resetDatabase());
                  Navigator.of(context).pop();
                },
                child: const Text('Reset Database'),
              ),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'))
            ],
          );
        });
  }
}
