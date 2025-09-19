import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:muchuu/views/term_lookup.dart';

class NovelViewer extends StatefulWidget {
  // TODO: Get parsed html document here
  // For now, we parse epubs on demand so it'll always be at a consistent directory
  final String novelTitle;
  final String novelHtml;

  const NovelViewer(
    this.novelTitle,
    this.novelHtml, {
    super.key,
  });

  @override
  State<NovelViewer> createState() => _NovelViewerState();
}

class _NovelViewerState extends State<NovelViewer> {
  bool useCustomColors = false;
  String outerWidth = '100%';
  String outerBackgroundColor = 'black';
  int innerWidthPercentage = 60;
  String innerBackgroundColor = 'black';
  String textColor = 'white';

  final ScrollController _scrollController = ScrollController();

  String? selectedText;
  final currentProgress = ValueNotifier<double>(0);

  void _onTextSelectedUpdate(SelectedContent? text) {
    // Seems to also be called when clicking on view definitions context menu item
    // print('selected "${text?.plainText}"');
    selectedText =
        text != null && text.plainText.isNotEmpty ? text.plainText : null;
  }

  void _onScrollEvent() {
    final position = _scrollController.position;
    final progress = position.pixels / position.maxScrollExtent;
    // print('Current scroll pos is ${progress*100}% (${position.pixels}/${position.maxScrollExtent})');
    currentProgress.value = (progress * 1000).roundToDouble() / 10;
  }

  @override
  void initState() {
    _scrollController.addListener(_onScrollEvent);
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  void updateColors() {
    // TODO: Figure out color scheme parts for this
    // TODO: Figure out how or when to call this
    ColorScheme colorScheme = Theme.of(context).colorScheme;

    String toHexString(Color color) =>
        '#${color.value.toRadixString(16).substring(2)}';

    // TODO: wrapping in setState has no effect; figure out how to make it affected
    // Maybe just affect the theme itself or use another ThemeData object?
    outerBackgroundColor =
        innerBackgroundColor = toHexString(colorScheme.onSurface);
    textColor = toHexString(colorScheme.surface);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.novelTitle),
        actions: <Widget>[
          // TODO: Implement variable width (we might need to do a custom widget builder for this though)
          ValueListenableBuilder<double>(
            builder: (BuildContext context, double value, Widget? child) =>
                Text('Progress: $value%'),
            valueListenable: currentProgress,
          ),
          SizedBox(width: 50),
        ],
      ),
      // TODO: Figure out why for svgs the images look like dogshit
      // Might be because of something overriding the width but keeping the intended height as per the svg/image tag
      // fwfh_svg does FittedBox -> SizedBox for inner TODO: check the src
      // https://github.com/daohoangson/flutter_widget_from_html/blob/master/packages/fwfh_svg/lib/src/svg_factory.dart
      // We can do absolute file uris where we put the assets in a directory
      // skip this for now and just move on
      body: SelectionArea(
        onSelectionChanged: _onTextSelectedUpdate,
        contextMenuBuilder: (BuildContext context,
                SelectableRegionState selectableRegionState) =>
            AdaptiveTextSelectionToolbar.buttonItems(
          anchors: selectableRegionState.contextMenuAnchors,
          buttonItems: <ContextMenuButtonItem>[
            // TODO: Figure out how selectableRegionState.contextMenuButtonItems are initally set by flutter
            ...selectableRegionState.contextMenuButtonItems,
            if (selectedText != null)
              ContextMenuButtonItem(
                onPressed: () => showDialog(
                  context: context,
                  // TODO: Figure out if we can get selectedText using not somethimg htat calls every time a selection change occurs
                  builder: (BuildContext context) =>
                      TermLookupView(initialQuery: selectedText),
                ),
                label: 'View Definitions',
              )
          ],
        ),
        child: HtmlWidget(
          widget.novelHtml,
          factoryBuilder: () => _NovelWidgetFactory(),
          customStylesBuilder: (element) {
            // Note: flex direction does not seem to work here so we turned them into inline styles
            if (element.id == 'wrapper-muchuu') {
              print('main wrapper');
              // Custom colors are handled by changes in Theme.of(context).colorScheme
              // if there is no overriding color
              // TODO: Evaluate and potentially improve performance of these being changed
              // Currently very laggy in debug mode
              return useCustomColors
                  ? {
                      'background-color': outerBackgroundColor,
                      'color': textColor,
                      'width': outerWidth,
                    }
                  : {
                      'width': outerWidth,
                    };
            }
            if (element.id == 'main-muchuu') {
              print('main inner');
              return useCustomColors
                  ? {
                      'background-color': innerBackgroundColor,
                      'width': '$innerWidthPercentage%',
                    }
                  : {
                      'width': '$innerWidthPercentage%',
                    };
            }
            if (element.localName == 'rt') {
              // print(element.outerHtml);
              return {'user-select': 'none'};
            }
            return null;
          },
          // renderMode: RenderMode.listView,
          renderMode: ListViewMode(controller: _scrollController),
        ),
      ),
    );
  }
}

class _NovelWidgetFactory extends WidgetFactory {
  final inlineMarkNotSelectableOp = BuildOp.v2(
    // It seems to be the case that if alwaysRenderBlock is true or unset,
    // the ruby text is rendered as a block element. This makes a paragraph
    // render as a column (with horizontal text at least) with the ruby texts
    // and the parts of the paragraph between those. Thus, we then must set
    // alwaysRenderBlock to false, which somehow still results in onRenderBlock
    // being called.
    alwaysRenderBlock: false,
    onRenderBlock: (BuildTree tree, WidgetPlaceholder placeholder) {
      return placeholder.wrapWith((BuildContext context, Widget widget) =>
          SelectionContainer.disabled(child: widget));
    },
  );

  @override
  void parse(BuildTree tree) {
    final element = tree.element;
    // TODO: Normalize line heights so that lines not containing ruby elements
    // are as long as lines that do contain ruby elements.
    switch (element.localName) {
      // case 'p' when element.children.any((e) => e.localName == 'ruby'):
      //   break;
      case 'ruby':
        break;
      case 'rt':
        tree.register(inlineMarkNotSelectableOp);
        break;
    }
    super.parse(tree);
  }

  @override
  Widget? buildText(
      BuildTree tree, InheritedProperties resolved, InlineSpan text) {
    // TODO: Come back to this to figure out accurate character counting by figuring out which paragraph we're at
    if (text is! TextSpan || (text.children?.isNotEmpty ?? false)) {
      // print('');
    } else {
      // print('Rendering: ${text.text}');
    }

    // Rest is mostly taken from the implementation of the fwfh_core library

    // pre-compute as many parameters as possible
    // final maxLines = tree.maxLines > 0 ? tree.maxLines : null;
    final maxLines = null;
    final softWrap = resolved.get<CssWhitespace>() != CssWhitespace.nowrap;
    final textAlign = resolved.get<TextAlign>() ?? TextAlign.start;
    final textDirection = resolved.get<TextDirection>();

    // Original implementation uses RichText but we should use the Text.rich
    // constructor instead because it allows for better functionality with
    // text selection being properly ordered for paragraphs containing both
    // normal text and ruby text.
    return Text.rich(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.clip,
      softWrap: softWrap,
      textAlign: textAlign,
      textDirection: textDirection,
    );
  }

  @override
  InlineSpan? buildTextSpan(
      {List<InlineSpan>? children,
      GestureRecognizer? recognizer,
      TextStyle? style,
      String? text}) {
    // TODO: implement buildTextSpan
    return super.buildTextSpan(
        children: children, recognizer: recognizer, style: style, text: text);
  }
}
