# Epub Parser Notes

## What to parse

### Spine
* We follow the spine, the table of contents is not important (as that is for the separate table of contents ui which will be useful for mobile platforms)
  * For epub 3.0, it's an xhtml file, so that means we can just make the reader navigate to the corresponding element id
  * For epub 2.0, it's an xml file adhering to the ncx standard, with some exceptions that are ignored
  * For now, we can just ignore the toc
* In epub 3.0, all elements in the spine should either be xhtml or svg documents (or their fallback chain eventually references an xhtml or svg document)
  * Fallback chains are given in the item elements of the manifest

#### Nonlinear Content
* By the specification, any nonlinear content mentioned in the spine must be able to be referenced by another element in the spine (or possibly any children of an element of the spine)
* For now, we can probably just display content as they appear in the spine

### External References (Media, Hyperlinks, etc.)
* Use the fallback chain if the current format is not supported
* We try to render it if possible, and just throw a warning for now (until we can focus on this part)

### CSS
* We might be able to get away with finding all unique paths to css files in the manifest and concatenating their contents together
* Need to have custom css override thing as well (*TODO: Figure out how overriding css works*)

## Parsing Process
*Note: I haven't confirmed if this is a complete process by looking at the epub and epub-rs specs yet*

1. Parse the toc nav element (inside of the toc file)
   1. If epub is 3.0 => toc is xhtml file
      1. Get tags inside of the ``<nav epub:type="toc" id="toc">...</nav>`` block
      2. Find all anchor elements inside of the block
      3. Keep track of their hrefs and inner text
   2. If epub is 2.0 => toc is xml ncx file
      1. Find all ``<navpoint>...</navpoint>`` blocks
      2. Find their inner text as the inner text of the``<navLabel><text>...</text></navLabel>`` blocks
      3. Find their hrefs as the ``src`` attribute of the``<content src="..." />`` tag
2. Get the corresponding manifest item for the first item listed in the toc nav element
3. Add that item as the first main chapter item and label it as the preface
4. Iterate through each element in the spine
   1. *TODO: See if the toc can ever be in the spine*
   2. Get html ref of the item
      1. Get idref attribute value
      2. Find the corresponding manifest item
         1. If item is xhtml file, href attribute stores their html ref
      3. Corresponding manifest item of type xhtml not found => look for fallback item
         1. Get idref of fallback item
         2. See if idref corresponds to an xhtml manifest item
         3. *TODO: Repeat this until we get xhtml item in the manifest chain*
         4. *TODO: See if there could exist svg elements without fallback*
      4. Parse corresponding xhtml file
         1. Get body tag (try parsing as html then xml)
         2. Get id and class name of the body tag
         3. Get class name of the html tag (*TODO: figure out why this is important*)
         4. Get inner html element
            1. Replace all relative hrefs to a dummy image
               1. *TODO: Figure out why?*
         5. Create div element with same id and classes as html element
            1. Also add wrapper class to the list of classes as it will be useful later
         6. Similarly, create inner div element with same id and classes as body element
            1. Also add wrapper body class
         7. Create a wrapper div class for the html element with unique d
            1. *TODO: Figure out the use for this*
         8. Add wrapper div to final parsed div 
            1. Final order is wrapper => html_wrapper => body_wrapper
         9. Add to the final character count for the publication
            1. Get the number of characters in the inner text of every paragraph element
         10. Find any chapters that correspond to the current manifest file
         11. Add section data for the corresponding chapter
             1. Able to find corresponding chapter
                 1. Id reference to the chapter
                 2. The number of characters of the body
                 3. The label (inner text) of the chapter
                 4. The starting character number (prev section characters + prev character count)
             2. Unable to find corresponding chapter, use last corresponding chapter found
                1. Add to main chapter character count
                2. Add section data
                   1. Id reference to the manifest/spine item id
                   2. Number of characters for body of this xhtml file
                   3. Parent chapter as the main chapter
5. Clear bad image references
   1. Bad image references are the dummy image hrefs
      1. Bad image file extension
      2. Input file does not include the required image
         1. *TODO: Figure out what the data: Record<string, string | Blob> parameter is for*
         2. We seem to want the manifest items to be in xml format
   2. Look at ``href`` attribute of ``image`` tags and ``src`` attribute of ``img`` tags
   3. Convert dummy image attribute to another dummy attribute with the same value
   4. Remove the corresponding old attribute
   5. *TODO: Figure out what this is for, which is likely resolving images later on*
6. Fix xhtml hrefs
   1. Find all ``image`` tags that don't have an ``href`` attribute
   2. If we find another attribute that ends in "href", make a new ``href`` attribute with the same value as that attribute
   3. *TODO: Figure out the cases in which this is the case (maybe something to do with xlink?)*
7. Flatten hrefs for anchor tags
   1. Set href to ``#<old href but concatenate everything before and after the "#">``
   2. *This allows for one href that works across the whole publication*
8. Return the final composed div element, the total character count, and the section data

## Displaying
1. Generate generic text reader page template
2. Insert final composed div
3. Ensure to also include the composed css
4. Have a javascript handler inside of the web view so communicate with the page
   1. Usages
      1. Send selected text to flutter
         1. Use ContextMenuItem to send request to display word lookup with current selected text
      2. Send stuff such as reading statistics
         1. Periodically send statistics/heartbeats
         2. Force send statistics on exit book or exit app in general
         3. *TODO: Try to see performance impact of sending decently frequent requests constantly*
   2. Can be done through InAppWebView
      1. InAppWebViewController.addJavaScriptHandler()
      2. Use custom ContextMenuItem
5. Should we display dictionary lookup information in the web view or natively?
   1. Make it part of the web view
      1. Would have to make more communication across the web view
      2. Would have to learn html/css or display it as an iframe on top of everything
   2. Viewing it natively
      1. Lookup has native communication
      2. Can use native flutter widgets and then make the webview grayed out
6. 

* We can probably put the parsed epub into the local filesystem, caching the results.

* We should probably disable any scripting and external resource access as a security concern, but security should be an afterthought (as the priority should be building a product in the first place)
