# Legacy prototype code (not built)

This folder holds the first prototype of StackSpace's document plugins and their tests,
moved out of `lib/` and `test/` on 2026-10-25 because none of it compiled (about 40
analyzer errors) and most of it was placeholder logic:

- `VirtualizedRenderer` and `VirtualizedDocument` generate fake "Line N: ..." text
  instead of showing a document's real lines.
- `EnhancedVirtualizedDocumentManager.saveDocument()` writes an empty list, which
  would erase the file it was given.
- `ClipboardManager.pasteContent()` doesn't insert anything.
- The tests call private methods of other libraries, which Dart doesn't allow.

It's kept for reference only. The app in `lib/` doesn't import it, and the analyzer
skips it (see `analysis_options.yaml`).
