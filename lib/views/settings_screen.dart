import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:muchuu/user_preferences.dart';
import 'package:muchuu/views/book_card.dart';
import 'package:muchuu/views/new_book_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Uri? preferencesDirectory;

  void fetchUserPreferences() {
    UserPreferences.preferencesDirectory.then((directory) => setState(() {
          preferencesDirectory = directory;
        }));
  }

  @override
  Widget build(BuildContext context) {
    if (preferencesDirectory == null) {
      fetchUserPreferences();
    }

    final textTheme = Theme.of(context).textTheme;
    final displaySmallBold =
        textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold);
    final headlineSmall = textTheme.headlineSmall;
    final headlineMedium = textTheme.headlineMedium;
    final headlineLarge = textTheme.headlineLarge;
    final double vHeight = MediaQuery.sizeOf(context).height;
    final double vWidth = MediaQuery.sizeOf(context).width;
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text('Settings', style: displaySmallBold),
          Text('Dictionaries', style: headlineSmall),
          OutlinedButton(onPressed: () {}, child: Text('Import Dictionaries')),
          FilledButton(onPressed: () {}, child: Text('Check for New Dictionaries')),
          Text('Books', style: headlineSmall),
          Row(
            spacing: 16,
            children: [
              Text('Preferences Directory:'),
              Text(preferencesDirectory?.path ?? 'Loading Directory Path'),
            ],
          ),
          FilledButton(onPressed: () {}, child: Text('Check for New Books')),
        ],
      ),
    );
  }
}
