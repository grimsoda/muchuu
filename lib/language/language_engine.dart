// Implementation largely based off yomitan's implementation of deinflection through LanguageTransforms
// https://github.com/yomidevs/yomitan/blob/master/docs/development/language-features.md

typedef TextProcessorFunction<T> = String Function(String rawText, T options);

class TextPreprocessor<T> {
  String name;
  String description;
  List<T> options;
  TextProcessorFunction<T> process;

  TextPreprocessor(
      {required this.name,
      required this.description,
      required this.options,
      required this.process});
}

class BasicTextPreprocessor extends TextPreprocessor<bool> {
  BasicTextPreprocessor(
      {required super.name, required super.description, required super.process})
      : super(options: [true, false]);
}

class BidirectionalTextPreprocessor
    extends TextPreprocessor<BidirectionalProcessorOption> {
  // TODO: Determine whether Enum.values elements are in a deterministic order based off declaration order
  BidirectionalTextPreprocessor(
      {required super.name, required super.description, required super.process})
      : super(options: [
          BidirectionalProcessorOption.off,
          BidirectionalProcessorOption.forward,
          BidirectionalProcessorOption.inverse,
        ]);
}

enum BidirectionalProcessorOption {
  off,
  forward,
  inverse,
}

// Rule chain candidates can be useful for sorting term dictionary entries (see _sortTermDictionaryEntries)
// And also showing the user the deinflection/processing order/candidates for each term

// TODO: Possibly remove this since possibly we don't really need this for anything?
// In the end, we just omit the text processor and inflection rule chain candidates
// typedef Trace = ({String text, String transform, int ruleIndex});

// TODO: Shall we rename these to transforms rather than deinflections?
typedef DeinflectionRule = ({
  TransformDescriptor transform,
  TransformRule rule,
  String inputText
});

typedef DeinflectionRuleChain = List<DeinflectionRule>;

typedef DeinflectedText = ({
  String text,
  List<String> conditions,
  DeinflectionRuleChain deinflectionRuleChain
});

abstract class LanguageEngine {
  abstract List<TextPreprocessor> textPreprocessors;
  abstract LanguageTransformsDescriptor transformsDescriptor;

  String getLanguageCode();

  bool isLookupWorthy(String text);

  bool conditionsMatch(
      List<String> currentConditions, List<String> nextConditions) {
    if (currentConditions.isEmpty) {
      return true;
    }

    final currentConditionsAll = _getConditionsWithParents(currentConditions);
    final nextConditionsAll = _getConditionsWithParents(nextConditions);

    if (currentConditionsAll.length != nextConditionsAll.length) {
      return false;
    }
    for (final condition in currentConditionsAll) {
      if (!nextConditionsAll.contains(condition)) {
        return false;
      }
    }
    return true;
  }

  Set<String> _getConditionsWithParents(List<String> conditions) {
    final resultConditions = Set<String>.from(conditions);
    final allConditions = transformsDescriptor.conditions;
    containsSubcondition(TransformCondition condition, String subCondition) =>
        condition.subConditions.contains(subCondition);

    final addedConditions = resultConditions
        .where((condition) => allConditions.values.any((transformCondition) =>
            containsSubcondition(transformCondition, condition)))
        .map((condition) => allConditions.entries
            .firstWhere((transformConditionEntry) =>
                containsSubcondition(transformConditionEntry.value, condition))
            .key)
        .toSet();

    final result = resultConditions.union(addedConditions);
    // Recursively add parents until there are no more parent conditions
    if (result.length > conditions.length) {
      return result.union(_getConditionsWithParents(result.toList()));
    } else {
      return result;
    }
  }

  // TODO: Maybe rename this as transform?
  List<DeinflectedText> deinflect(String originalText) {
    // This basically functions as getAlgorithmDeinflections

    // Don't forget to work with preprocessedtext variants
    // We can probably separate the entire deinflection process from the transformation process?

    final transforms = transformsDescriptor.transforms;

    final transformQueue = <DeinflectedText>[];
    transformQueue
        .add((text: originalText, conditions: [], deinflectionRuleChain: []));

    for (int i = 0; i < transformQueue.length; i++) {
      final current = transformQueue[i];
      print(
          '$i: processing ${current.text} with conditions ${current.conditions}');
      for (final MapEntry(key: transformName, value: transform)
          in transforms.entries) {
        // print('testing rules in transform $transformName');

        for (final rule in transform.rules) {
          // TODO: Heuristic testing
          // Heuristic just seems to be the concatenated regex rules for testing if it is concatenated
          // We'll have to see if the inclusion of a heuristic to skip entire transforms is worth it
          if (!conditionsMatch(
                  current.conditions, rule.conditionsBeforeDeinflection) ||
              !rule.matchesTransformRule(current.text)) {
            continue;
          }

          // TODO: Shall we add cycle detection? yomitan doesn't do anything about it except create a warning about it

          print('continue $i');
          transformQueue.add((
            text: rule.transformText(current.text),
            conditions: rule.conditionsAfterDeinflection,
            deinflectionRuleChain: List.from(current.deinflectionRuleChain)
              ..add((transform: transform, rule: rule, inputText: current.text))
          ));
        }
      }
    }

    return transformQueue;

    // Order of deinflection:
    // Get all candidates, along with their end conditions (is it conditionOut? we need to confirm this.)
    // Look up all terms of candidates, with probably first candidates being prioritized
    // If the looked up term conditions match the candidate's conditions (all conditions or there are no conditions to be matched)

    // The actual order of operations:
    // Iterating for each substring of the source text,
    //    Get preprocessed text variants:
    //        Create a map for variants
    //        Handle explicit text replacements first
    //        Nested iteration in order: preprocessors, existing variants, options from the preprocessor
    //        If processed text same as existing variant: existingCandidate defined ? do nothing : set variants[existingCandidate] to currentPreprocessorRuleChainCandidates
    //        Else: variants[existingCandidate].append currentPreprocessorRuleChainCandidates.map((c) => [...c, preprocessorId]) (or itself if existingCandidate undefined)
    //        Actually commit changes to variants map so nothing breaks, continue iteration of next preprocessor
    //    For each preprocessed text variant in order,
    //        Transform the text to its deinflected form
    //        Postprocessing of the text (unnecessary)
    //        Add to list of deinflections (with textProcessorRuleChainCandidates being every combination of preprocessor and postprocessor rule candidates)

    // The actual transforming:
    //    Make a queue of text to transform, starting with sourceText with no conditions and empty trace
    //    Iterate through each item in queue,
    //        Test against heuristic???
    //        For each transform rule, if conditionsIn match, passes test with inflection, doesn't form a cycle, deinflect it with conditionsOut
    //        Cycle detection is just to warn but it's detected when we reuse some transform id with the same input text
    //        That deinflection is added to the queue, continue until we reach the end

    // We then add entries to deinflections:
    //    Group deinflections together based on the same output deinflected text
    //    Look up all the possible deinflected texts
    //    Match entries to deinflections:
    //        Get condition flags from parts of speech of database entry
    //        Database entries of a deinflection consist of those whose condition flags match (or all the entries of we chose not to filter based off parts of speech)

    // Then we call _getDictionaryDeinflections(...):
    //    Iterating in nested order: deinflections, database entries (of said deinflection), definitions (of said entry)
    //    :Note that we skip this entirely if we disable using deinflections from the specific dictionary
    //    :Skip if uninflected text of definition is empty or definition itself is not an array
    //    Map inflection rule candidates where inflectionRules become
    //      {
    //        source: 'dictionary' if inflectionRules is empty else 'both',
    //        inflectionRules: flattenedMap of [inflectionRules (from deinflection), inflectionRules from definition]
    //      }
    //    Create new combined deinflection where the entries are from definition: formOf/deinflectedText, part of inflectionRuleChainCandidates
    //    no conditions because we don't care about them anymore
    //    We then add dictionary entries to these deinflections again

    //  Now total deinflections are both algorithm and dictionary deinflections, for each of these entries:
    //      Filter each dictionary entry's definitions to only those that aren't arrays
    //      Filter the dictionary entries themselves that have at least one definition
    //  Now we filter the deinflections themselves to those that have at least one database entry

    // Now we get the dictionary entries of the above deinflections using _getDictionaryEntries(...):
    //    Create id set
    //    For each deinflection:
    //      Skip those with no databaseEntries
    //      originalTextLength is continually updated maximum deinflection.originalText/transformedText.length value
    //      For each databaseEntry:
    //          id set doesn't contain databaseEntry id;
    //              add to returned dictionaryEntries _createTermDictionaryEntryFromDatabaseEntry with enabledDictionaryMap, tagAggregator, primaryReading
    //              add to id set the databaseEntry's id
    //          id set contains databaseEntry id:
    //              use existing entry that contains some definitions with same id to get existingEntry, existingIndex
    //              existingTransformedLength is existingEntry.headwords[0].sources[0].transformedText.length (i.e., any of its transformed text lengths?)
    //              deinflection.transformedText.length < existingTransformedLength: skip to next databaseEntry if
    //              deinflection.transformedText.length > existingTransformedLength: replace element at dictionaryEntries[existingIndex] with new dictionary entry (same parameters as if databaseEntry id wasn't in id set)
    //              deinflection.transformedText.length == existingTransformedLength: merge inflectionRuleChains and textProcessorRuleChains with existing
    //      Returning dictionaryEntries and originalTextLength
    //
    //    Merging inflectionRuleChains: if a rule chain is overlapping but sources differ, mark it as having a source of 'both'
    //    Merging textProcessorRuleChains: simply just merge and prevent duplicates from appearing multiple times

    // List<String> processedTextCandidates = [];
    // for (final preprocessor in textPreprocessors) {
    //   for (final option in preprocessor.options) {
    //     final candidate = preprocessor.process.call(originalText, option);
    //     if (!processedTextCandidates.contains(candidate)) {
    //       processedTextCandidates.add(candidate);
    //     }
    //   }
    // }
    // return originalText;
  }
}

typedef TransformConditionName = String;

class LanguageTransformsDescriptor {
  String language;
  Map<TransformConditionName, TransformCondition> conditions;
  Map<String, TransformDescriptor> transforms;

  LanguageTransformsDescriptor(
      {required this.language,
      required this.conditions,
      required this.transforms});
}

class TransformConditionI18n {
  String language;
  String name;
  String? description;

  TransformConditionI18n({
    required this.language,
    required this.name,
    this.description,
  });
}

class TransformDescriptorI18n {
  String language;
  String name;
  String? description;

  TransformDescriptorI18n({
    required this.language,
    required this.name,
    this.description,
  });
}

class TransformDescriptor {
  String name;
  String? description;
  List<TransformDescriptorI18n> i18n;

  // RegExp matchPattern;

  List<TransformRule> rules;

  bool isInflected(String text) =>
      rules.any((rule) => rule.matchesTransformRule(text));

  TransformDescriptor(
      {required this.name,
      this.description,
      this.i18n = const [], // TODO: Review whether const lists are mutuable
      required this.rules});
}

typedef TransformConditionTag = String;

class TransformCondition {
  String name;

  // TODO: Should we have internationalization?
  bool isDictionaryForm;
  List<TransformConditionI18n> i18n;
  List<TransformConditionName> subConditions;

  // TODO: Figure out conditionsIn and conditionsOut from yomitan
  // conditionsIn := The inflected word type/condition
  // conditionsOut := The word type/condition after deinflection

  // Condition matching done by checking whether current conditions and rule.conditionsIn
  // share at least one condition

  // Conditions are like an "inverted" tree:
  // Conditions start at a leaf node, at its most inflected form
  // Traverse upwards until you end at a dictionary form condition or at the local root,
  // which should be a dictionary from condition as well

  TransformCondition(
      {required this.name,
      this.i18n = const [],
      required this.isDictionaryForm,
      this.subConditions = const []});
}

abstract class TransformRule {
  List<TransformConditionTag> conditionsBeforeDeinflection;
  List<TransformConditionTag> conditionsAfterDeinflection;

  bool matchesTransformRule(String text);

  String transformText(String input);

  TransformRule(
      this.conditionsBeforeDeinflection, this.conditionsAfterDeinflection);
}

class SuffixInflection extends TransformRule {
  String inflectedSuffix;
  String deinflectedSuffix;
  RegExp matchPattern;

  @override
  bool matchesTransformRule(String text) => matchPattern.hasMatch(text);

  @override
  String transformText(String input) =>
      input.substring(0, input.length - inflectedSuffix.length) +
      deinflectedSuffix;

  SuffixInflection(
      this.inflectedSuffix,
      this.deinflectedSuffix,
      List<TransformConditionTag> inflectedConditions,
      List<TransformConditionTag> deinflectedConditions)
      : matchPattern = RegExp('$inflectedSuffix\$'),
        super(inflectedConditions, deinflectedConditions);
}
