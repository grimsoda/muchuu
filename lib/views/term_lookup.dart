import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:muchuu/dictionary/dictionary.dart';

class TermLookupView extends StatefulWidget {
  const TermLookupView({this.initialQuery, super.key});

  final String? initialQuery;

  @override
  State<TermLookupView> createState() => _TermLookupViewState();
}

class _TermLookupViewState extends State<TermLookupView> {
  late TextEditingController _controller;
  late final DictionaryManager dictionaryManager;

  List<String> _searchResults = [];

  void _searchForTerm(String search) {
    List<Term> terms = dictionaryManager.searchTerms(search);
    print('found ${terms.length} terms');
    _generateTermSearchResults(terms).then((results) => setState(() {
          _searchResults = results;
        }));
    print('sent async generate term query "$search"');
  }

  Future<List<String>> _generateTermSearchResults(List<Term> terms) async {
    List<String> parsedResults = [];
    for (final term in terms) {
      // Get metadata
      final metaList = dictionaryManager.searchTermMeta(term.term);
      String metaText = metaList
          .map((meta) =>
              '${meta.dictionary}<br>${switch (meta.getMetadataType()) {
                'frequency' => _getTermFrequencyText(meta as TermFrequency),
                'pitch' => _getTermPitchText(meta as TermPitch),
                'ipa' => _getTermIPAText(meta as TermIPA),
                _ => throw FormatException(
                    'Unknown metadata type: ${meta.getMetadataType()}'),
              }}')
          .join('<br>');
      // TODO: Add support for tags based on term and definition (tag table lookup)
      if (term.termTags.isNotEmpty) {
        metaText += '<br>Term Tags: ${term.termTags.join(' ')}';
      }
      if (term.definitionTags.isNotEmpty) {
        metaText += '<br>Definition Tags: ${term.definitionTags.join(' ')}';
      }
      // TODO: Separate metadata based on source dictionary
      // We can start doing this.

      for (final definition in term.definitions) {
        String definitionText = await definition.getDefinitionText();
        parsedResults.add(
            '$metaText${metaText.isNotEmpty ? '<br>' : ''}$definitionText');
        // parsedResults.add(
        //     '$metaText${metaText.isNotEmpty ? '<br>' : ''}${await definition.getDefinitionText()}');
      }
    }

    print('done setting search term results');
    return parsedResults;
  }

  String _getTermFrequencyText(TermFrequency termFrequency) {
    List<String> text = [];
    if (termFrequency.displayFrequency != null) {
      text.add('Frequency: ${termFrequency.displayFrequency}');
    }
    if (termFrequency.frequency != null) {
      text.add('Actual Value: ${termFrequency.frequency}');
    }
    return text.join(' ');
  }

  String _getTermPitchText(TermPitch termPitch) {
    List<String> text = [];
    text.add('Downstep on mora ${termPitch.downstepPosition}');
    if (termPitch.devoicePositions.isNotEmpty) {
      text.add('<br>Devoice on these morae:');
      for (final position in termPitch.devoicePositions) {
        text.add(position.toString());
      }
    }
    if (termPitch.nasalPositions.isNotEmpty) {
      text.add('<br>Nasal on these morae:');
      for (final position in termPitch.nasalPositions) {
        text.add(position.toString());
      }
    }
    if (termPitch.tags.isNotEmpty) {
      text.add('<br> Tags:');
      for (final tag in termPitch.tags) {
        text.add(tag.toString());
      }
    }
    return text.join(' ');
  }

  String _getTermIPAText(TermIPA termIPA) {
    List<String> text = [];
    text.add('Transcription: ${termIPA.transcription}');
    if (termIPA.tags.isNotEmpty) {
      text.add('<br> Tags:');
      for (final tag in termIPA.tags) {
        text.add(tag.toString());
      }
    }
    return text.join(' ');
  }

  // (List<String>, Map<String, List<String>>) _generateResults(
  //     List<Term> results) {
  //   List<String> definitions = [];
  //   Map<String, List<TermMetadata>> metadata = {};
  //   Map<String, List<String>> metadataParsed = {};
  //   for (final Term term in results) {
  //     metadata.putIfAbsent(
  //         term.term, () => dictionaryManager.searchTermMeta(term.term));
  //     for (final Definition definition in term.definitions) {
  //       definitions.add(switch (definition) {
  //         BasicDefinition def => def.definition,
  //         StructuredContent def => def.getHtmlContent(),
  //         DeinflectionDefinition def =>
  //           'Inflection Rules: ${def.inflectionRules.join(', ')}',
  //         ImageDefinition def => 'Image: ${def.path}',
  //       });
  //     }
  //   }
  //   for (final MapEntry<String, List<TermMetadata>>(key: term, value: meta)
  //       in metadata.entries) {
  //     metadataParsed[term] = meta
  //         .map((termMetadata) => switch (termMetadata) {
  //               TermFrequency freq =>
  //                 'Reading: ${freq.reading}<br>Frequency: ${freq.frequency}<br>Display Frequency: ${freq.displayFrequency}',
  //               TermPitch pitch =>
  //                 'Reading: ${pitch.reading}<br>Downstep on mora ${pitch.downstepPosition}<br>Nasal Positions: ${pitch.nasalPositions.join(', ')}<br>Devoice Positions: ${pitch.devoicePositions.join(', ')}<br>Tags: ${pitch.tags.join(', ')}',
  //               TermIPA ipa =>
  //                 'Reading: ${ipa.reading}<br>Transcription: ${ipa.transcription}<br>Tags: ${ipa.tags.join(', ')}',
  //             })
  //         .toList();
  //   }
  //   return (definitions, metadataParsed);
  // }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    DictionaryManager.instance.then((instance) {
      dictionaryManager = instance;
      if (widget.initialQuery != null) {
        _searchForTerm(widget.initialQuery!);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Search in db',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Search for Terms',
              ),
              onSubmitted: _searchForTerm,
            ),
            const SizedBox(height: 10),
            Text(
                '${_searchResults.isEmpty ? 'No' : _searchResults.length} results found.'),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                // padding: EdgeInsets.all(8),
                itemCount: _searchResults.length,
                itemBuilder: (BuildContext context, int index) {
                  return HtmlWidget('<p>${_searchResults[index]}</p>');
                },
                separatorBuilder: (BuildContext context, int index) =>
                    const Divider(),
              ),
              // We can also render it into one widget, performance seems negligible
              // child: ListView(
              //   children: [HtmlWidget(
              //       _searchResults.asMap().entries.expand((entry) => ['<p>${entry.value}</p>', if (entry.key+1 < _searchResults.length) '<hr />' ]).join('')
              //   )],
              // ),
            ),
            FilledButton.tonal(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Close')),
          ],
        ),
      ),
    );
  }
}
