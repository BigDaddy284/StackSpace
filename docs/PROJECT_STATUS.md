# PROJECT STATUS

_Last updated: 2026-10-25 (Improvement Phase 1, Tasks 1-12 done; test build 2 tagged)_

## Current phase
Improvement Phase 1: advanced editor, slash menu, code spaces. Working one task at a time.
Test build 1 (v0.1.0-test.1) is published on GitHub and loads the user's AppFlowy workspace.
Test build 2 (v0.2.0-test.1, version 0.2.0+2) carries everything from Phase 1; see the GitHub release.

## Current task and scope
Tasks 1-11 done: research, plan, the block editor, the slash menu, code spaces, formatting keys,
the performance pass with its fix for long pages, the floating formatting toolbar and the block
option menu, table editing and images, folding sections and block drag-and-drop. The Phase 1 plan
(EDITOR_FEATURE_RESEARCH.md §12) is complete except columns, which are deferred (see below).
Final report: `docs/PHASE1_REPORT.md`.

## Task log (Phase 1)
| Task | Status | Tests | Files |
| --- | --- | --- | --- |
| 12. Sidebar clean-up + test build 2 | Done 2026-10-25. Pictures and other binary files (`WorkspaceEntry.binaryExtensions`: images, PDF, archives, media, fonts, executables) are no longer pages: the sidebar hides them and any folder that holds nothing but them, the assistant's search skips them and the first page opened is never one of them. They stay in the folder and the assistant's list tool still shows them. Version bumped to 0.2.0+2 and tag `v0.2.0-test.1` pushed for the GitHub Actions Windows build. | 134/134 (+2) + 21 timing tests | `lib/workspace/workspace.dart`, `lib/ui/sidebar.dart`, `test/workspace_test.dart`, `test/home_page_test.dart`, `pubspec.yaml` |
| 11. Folding sections + drag-and-drop | Done 2026-10-25. Every heading has a chevron in the gutter (on hover or focus; always while folded) that folds the blocks up to the next heading of the same or a higher level; the block menu has Collapse / Expand section; folded rows take no space in the list; a caret move into a folded block (arrows, undo, a drop) unfolds it; folding changes nothing in the file. The block handle can be dragged: a chip with the block's first line follows the pointer, the source row is dimmed, a line shows where the block will land (upper half: above, lower half: below, the space after the last block: at the end), the list scrolls while the pointer is near its top or bottom edge, and the drop is one undo step. Also fixed on the way: row heights now account for the caret margin a text field keeps at its right, which a borderline-wrapping to-do item exposed at 1100 px / 150 %. | 132/132 (+4) + 21 timing tests | `lib/ui/editor/block_menu.dart`, `block_editor.dart`, `block_metrics.dart`, `test/sections_drag_test.dart`; screenshots 19-20 |
| 10. Tables + images | Done 2026-10-25. A Markdown table is a grid of single-line cells under a header strip ("Table 4 × 3" and, on hover or focus, Add row / Add column / Delete row / Delete column / Delete table); Tab and Shift+Tab move between cells (Tab on the last cell adds a row), Enter moves down (and adds a row at the bottom), arrows leave at the edges; every change is written back as padded Markdown and each row / column change is its own undo step. `lib/editor/table_data.dart` reads and writes the lines (escaped pipes, alignments, ragged rows repaired). Images: the slash command opens a dialog with "Choose a file…" (system picker) or a typed path / link; a file from outside the workspace is copied to `images/` next to the page, a workspace file is referenced relative to the page, a link stays; a description field under every picture edits the alt text. | 128/128 (+8) + 21 timing tests | `lib/editor/table_data.dart`, `lib/ui/editor/table_block.dart`, `lib/ui/editor/image_dialog.dart`, `lib/ui/editor/header_button.dart`, `block_editor.dart`, `block_metrics.dart`, `slash_commands.dart`, `test/table_image_test.dart`; screenshots 17-18 |
| 9. Formatting toolbar + block menu | Done 2026-10-25. A toolbar floats above (or below) a text selection with Bold / Italic / Strikethrough / Inline code / Link and a "Turn into" menu (Text, Heading 1-3, Bulleted, Numbered, To-do, Quote, Code block); it follows the selection, never takes focus, and closes on a collapsed caret, scroll or blur. Every row has a drag-handle button in a 24 px gutter (visible on hover or while the block has focus) that opens the block menu: Turn into, Duplicate, Move up / down (Ctrl+Shift+arrows), Delete. Also fixed on the way: markers hug the words when a selection drags in spaces; saves are serialised so a slow write can never land an older version over a newer one; text lines are at least 24 px so one-line blocks stay WCAG tap targets next to the handle. | 119/119 (+5) + 21 timing tests | `lib/ui/editor/format_toolbar.dart`, `lib/ui/editor/block_menu.dart`, `block_editor.dart`, `block_metrics.dart`, `page_editor_controller.dart`, `test/block_menu_test.dart`, `test/block_editor_test.dart`; screenshots 15-16 |
| 1. Baseline + research | Done 2026-10-25. `flutter analyze` clean, `flutter test` 49 passed, Linux debug build OK, Git checkpoint on `main`. | 49/49 | `docs/EDITOR_FEATURE_RESEARCH.md`, docs copied into `docs/` |
| 2. Matrix + plan + spikes | Done 2026-10-25. Feature matrix (§8), spikes (§11: `re_editor` handles 100k lines in ~30 ms per operation; `appflowy_editor` compiles from git but is ruled out), prioritised plan (§12). | 49/49 | `docs/EDITOR_FEATURE_RESEARCH.md` |
| 8. Performance + regression | Done 2026-10-25. Timing tests for 5k-100k lines; found and fixed the O(n) jump in long pages with pre-measured row heights (`lib/ui/editor/block_metrics.dart`, `block_editor.dart` list with `itemExtentBuilder`, cached extents per edit, id→index map in `PageDocument`, lazy pruning); image rows fixed at 300 px; read-only threshold 250k lines / 16 MB. Live run in the release build with 10k-line code, 10k-line mixed and 50k-paragraph pages. | 114/114 (+4 metrics) + 21 timing tests | `lib/ui/editor/block_metrics.dart`, `block_editor.dart`, `code_block.dart`, `inline_markdown.dart`, `page_document.dart`, `page_editor_controller.dart`, tests |
| 7. Formatting keys + code space tests | Done 2026-10-25. Ctrl+B / Ctrl+I / Ctrl+E / Ctrl+Shift+X wrap or unwrap the selection (`**`, `_`, `` ` ``, `~~`), Ctrl+K inserts `[text](url)`; arrows at the first / last line or character of a code space move to the neighbouring block (found that `re_editor` consumed arrows on desktop, so the editor's cursor-move action is overridden); context-menu Copy all / Cut / Paste tested with tabs and Unicode. | 110/110 (+3) | `lib/ui/editor/block_editor.dart`, `lib/ui/editor/code_block.dart`, tests |
| 6. Code spaces | Done 2026-10-25. `lib/ui/editor/code_block.dart` (header with language label + "auto", wrap, copy, menu; `re_editor` body with line numbers and `re_highlight` colours; caption field; context menu; searchable language picker with "Auto-detect"), `lib/editor/code_languages.dart` (30 languages, fence aliases, extensions, `detectLanguage`), fence captions in `blocks.dart`, language from the file extension for `.py` / `.json` / ..., keys in `block_editor.dart` (Ctrl+Enter leaves the block, Backspace on an empty block makes a paragraph, arrows at the edges, page-wide Ctrl+Z / Ctrl+Y). Packages `re_editor` 0.10.0 + `re_highlight` 0.0.3 (MIT) added. | 107/107 (+24) | see files; screenshots 11-13 |
| 4-5. Slash menu + tests | Done 2026-10-25. `lib/editor/slash_commands.dart` (13 commands: Text, Heading 1-3, Quote, Callout, Bulleted, Numbered, To-do, Code block, Divider, Table, Image; aliases such as h1, ul, todo, ```), `lib/ui/editor/slash_menu.dart` (panel anchored to the slash, flips at the bottom edge, categories, icons, descriptions, hover and click), tracking in `block_editor.dart` (opens on `/` at the start of a block or after a space, filters while typing, closes on Escape / slash deleted / focus lost, never in code blocks or plain files). | 83/83 (+14) | see files |
| 3. Block editor | Done 2026-10-25. Own block model with exact Markdown round trip, document with undo/redo, block-by-block editor pane, controller refactor, caret path made cheap. Live-tested in a Linux release build at 40 keys/s (3 identical runs). | 69/69 (+20) | `lib/editor/blocks.dart`, `lib/editor/page_document.dart`, `lib/editor/page_editor_controller.dart`, `lib/ui/editor/block_editor.dart`, `lib/ui/editor/inline_markdown.dart`, `lib/ui/editor_pane.dart`, `lib/ui/home_page.dart`, `lib/ui/chat/composer.dart`, tests, docs |

## Completed work
- Installed Flutter 3.47.8 (Dart 3.13.7) in the cloud environment so tests actually run.
- Fixed the build setup: Dart 3 SDK constraint, `http` dependency, generated the `windows/`
  runner, current `flutter_lints`.
- Moved the broken prototype (`lib/plugins`, its six tests) to `windows_app/legacy/`, which is
  excluded from the build and analyzer.
- New code in `windows_app/lib/`:
  - `workspace/workspace.dart`: folder-backed pages, safe paths, CRLF kept, deletes to `.trash`.
  - `ai/ollama_client.dart`: `/api/version`, `/api/tags`, `/api/show`, streamed `/api/chat`
    with tools and `think`.
  - `ai/workspace_tools.dart`: 10 tools (list, read, search, create, write, replace_text,
    edit_lines, insert_lines, rename, delete) with undo records.
  - `ai/chat_controller.dart`: tool loop (max 15 rounds), open page + selection as context,
    thinking-level mapping, retry without tools/thinking if a model rejects them, stop, undo.
  - `editor/page_editor_controller.dart`: open/autosave/reload pages; read-only viewer for 20k+ lines.
  - `ui/`: sidebar, editor pane, chat dock (closed / minimised / open / maximised, Ctrl+J),
    composer with model and thinking pickers, settings dialog.

- Theme and accessibility pass: Stills & Reels palette (`lib/app/theme.dart`), light and dark
  modes with a Windows / Light / Dark switch, screen-reader labels, 24x24 click targets, F2/Delete
  in the sidebar, one selectable chat transcript, and a header that no longer overflows at 150% text.

## Files changed
See `git log` in `windows_app/` (5 commits on `main`).

## Tests executed and actual results (Task 12)
- `flutter analyze`: no issues. `flutter test` (without the timing file): 134 passed, 2 skipped by
  design.
- New: `workspace_test.dart` lists a `.PNG` and an `images/a.jpg` in `entries` but not in `pages`;
  `home_page_test.dart` pumps the app with `cover.png`, `images/shot.jpg`, `docs/pic.gif` and
  `docs/readme.md` and checks the sidebar shows `hello.py`, `docs` and `readme.md` and none of the
  pictures or the `images` folder.
- GitHub Actions (windows-latest): the suite had failed on Windows since Task 6 for two reasons that
  never showed on Linux: temp-folder deletion raced the autosave still holding the file
  (`PathAccessException`), and tests read the saved file before the slower Windows write finished.
  Fixed with `test/support/temp.dart` (`deleteTemp` retries, `waitSaved` waits for `dirty` to clear);
  the workflow now turns failing tests into annotations so the cause is visible without the log.
  Run 40244110488 on commit 0a41d24: analyze, 134 tests, build all green.
- Test build 2 was published from that commit with the workflow's manual `release_tag` input
  (`gh workflow run windows-build.yml -f release_tag=v0.2.0-test.1`): a plain tag push is blocked
  from this environment, so the release's tag was created by the release action on the same commit.

## Tests executed and actual results (Task 11)
- `flutter analyze`: no issues. `flutter test` (without the timing file): 132 passed, 2 skipped by
  design. `test/performance_test.dart`: 21 timing tests passed.
- New `test/sections_drag_test.dart` (4): the chevron folds a heading's section (the blocks are not
  built, the rows take no space, the next heading of the same level stays, the file is unchanged),
  Arrow Down from the folded heading unfolds it, Collapse section from the block menu and the chevron
  unfold again; folding a section with the caret inside moves the caret to the heading; dragging a
  handle onto the lower half of a row puts the block below it and saves, onto the upper half above it;
  a block dropped where it was changes nothing (document version unchanged).
- Regression found and fixed: with the wider gutter a to-do item that wrapped at the edge measured
  two lines but rendered three at 1100 px / 150 % text, because a text field keeps 3 px for the
  caret at its right; `BlockMetrics` now subtracts that margin.
- Accessibility: the handle and the chevron are 24 x 24 px (the handle was 20 px tall, which the
  guideline did not see while it sat at the list's edge); the four accessibility tests pass.
- Live run (Linux release build, `docs/screenshots/19-folded-section-dark.png` and
  `20-drag-block-dark.png`): Collapse section from the block menu folds "Planning" down to its
  heading with a blue chevron, the chevron unfolds it; dragging "Budget review" by its handle shows
  the chip and the insertion line under "Two risks are open." and the file on disk has the item
  there after the drop.

## Tests executed and actual results (Task 10)
- `flutter analyze`: no issues. `flutter test` (without the timing file): 128 passed, 2 skipped by
  design. `test/performance_test.dart`: 21 timing tests passed.
- New `test/table_image_test.dart` (8): `TableData` reads and writes a table keeping escaped pipes and
  alignments, repairs a table without a separator or with ragged rows, adds and removes rows and
  columns (never the header or the last column); in the editor a table shows as cells, typing writes
  padded Markdown and the file follows; Tab / Shift+Tab / Enter / arrows move between cells, Tab on the
  last cell adds a row, Up from the header and Down from the last row leave the table and the
  neighbours' arrows enter it; the header buttons add and remove rows and columns, Ctrl+Z undoes one
  change at a time, Delete table removes the block; `/table` inserts a table with the caret in the
  first cell; the description field under a picture saves as the alt text and Enter below it adds a
  paragraph; `importImage` copies an outside file into `images/` next to the page (a taken name gets
  a number), keeps links, references workspace files relative to the page and keeps a path that
  leads nowhere.
- `test/block_metrics_test.dart` now covers the table grid and the always-present description
  field (image rows are 4 + 24 px taller than before).
- Live run (Linux release build, `docs/screenshots/17-table-dark.png` and `18-image-dark.png`):
  typing in a cell, Tab to the next, Tab on the last cell adding a row, the file on disk padded;
  `/image` with a path from outside the workspace copied the file to `images/outside_photo.png`
  and the page shows the picture with "outside photo" as its description.
- Noted: the sidebar lists every file, so a copied image shows there too (see KNOWN_ISSUES.md).

## Tests executed and actual results (Task 9)
- `flutter analyze`: no issues. `flutter test` (without the timing file): 119 passed, 2 skipped by
  design. `test/performance_test.dart`: 21 timing tests passed (no change from Task 8 within noise).
- New `test/block_menu_test.dart` (5): toolbar appears on a selection, Bold / Italic / Code buttons
  wrap the text and the file matches, it goes when the caret collapses; Turn into changes the kind
  and keeps the text; no toolbar in a plain file, a read-only page or on a collapsed caret; the handle
  shows on hover or focus, Duplicate / Move up / Move down / Delete from the menu change the document
  and the saved file; Turn into from the menu converts a list item to a code block and back.
- Regression found and fixed: the handle beside each row stopped the text field merging with its
  padding in the accessibility tree, so a one-line paragraph was a 23 px target; text lines are now
  at least 24 px (`BlockMetrics.minLineHeight`) and the four accessibility tests pass again.
- Bug found and fixed while testing: a save that was still writing when the next edit's save
  started could finish last and leave the older text on disk. `PageEditorController.flush` now
  waits for the write in flight and then writes the newest content.
- Live run (Linux release build, `docs/screenshots/15-format-toolbar-dark.png` and
  `16-block-menu-dark.png`): drag-selected words show the toolbar, Bold wraps them and the file on
  disk follows; hovering a bullet shows its handle, the menu duplicates the item. Note for Windows
  builds: a stale icon-font subset in `build/` left the new icons blank until the cached
  `MaterialIcons-Regular.otf` was deleted; `flutter clean` does the same.

## Tests executed and actual results (Task 8)
- `flutter analyze`: no issues. `flutter test` (without the timing file): 114 passed (4 of them the new metrics checks), 2 skipped by
  design. `test/performance_test.dart`: 21 timing tests passed.
- Model timings (test VM, JIT debug; release is faster). Columns: blocks, parse, write, load, one
  edit, toMarkdown, undo, in ms:

| shape | lines | blocks | parse | write | load | edit | toMarkdown | undo |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| code | 5,000 | 2 | 14 | 2 | 3 | 1 | 0 | 0 |
| paragraphs | 5,000 | 5,000 | 11 | 7 | 9 | 0 | 1 | 0 |
| mixed | 5,000 | 2,310 | 3 | 0 | 3 | 0 | 4 | 0 |
| code | 10,000 | 2 | 2 | 2 | 2 | 0 | 0 | 0 |
| paragraphs | 10,000 | 10,000 | 9 | 1 | 8 | 0 | 0 | 0 |
| mixed | 10,000 | 4,620 | 4 | 3 | 4 | 0 | 0 | 0 |
| code | 50,000 | 2 | 18 | 8 | 36 | 0 | 0 | 0 |
| paragraphs | 50,000 | 50,000 | 51 | 7 | 81 | 1 | 9 | 0 |
| mixed | 50,000 | 23,082 | 25 | 26 | 44 | 0 | 8 | 0 |
| code | 100,000 | 2 | 49 | 22 | 53 | 0 | 0 | 0 |
| paragraphs | 100,000 | 100,000 | 122 | 16 | 137 | 4 | 16 | 0 |
| mixed | 100,000 | 46,158 | 79 | 22 | 81 | 5 | 24 | 0 |

- Editor timings (test VM; "key" includes the test's tap and two frames, "jump" is a scrollbar-style
  jump to the end and "scroll" that plus the jump back), in ms:

| shape | lines | first frame | key | jump to end | jump + back |
| --- | --- | --- | --- | --- | --- |
| code | 5,000 | 728 | 220 | 3 | 5 |
| paragraphs | 5,000 | 583 | 330 | 559 | 939 |
| mixed | 5,000 | 311 | 194 | 358 | 672 |
| code | 10,000 | 109 | 65 | 1 | 2 |
| paragraphs | 10,000 | 553 | 354 | 694 | 1,170 |
| mixed | 10,000 | 607 | 359 | 402 | 707 |
| code | 50,000 | 373 | 249 | 1 | 3 |
| paragraphs | 50,000 | 624 | 437 | 852 | 1,351 |
| mixed | 50,000 | 646 | 314 | 597 | 999 |

  Before the fix the 5,000-paragraph jump took 59,424 ms and the mixed one 31,928 ms (every block
  between the top and the end was laid out). The first jump still measures each row once (a text
  layout for rows that may wrap, nothing for short ones); later jumps and scrolling read cached
  numbers.
- Release build under Xvfb: a 50,000-paragraph page (1.4 MB) opened from the sidebar, dragging the
  scrollbar thumb to the bottom showed the last paragraphs within the 0.7 s wait of the script,
  typing there saved at line 99,997; a 10,000-line mixed page (headings, lists, code blocks) dragged
  to its end likewise; a 10,000-line Python page took Ctrl+End and typing at the end. Screenshot
  `docs/screenshots/14-50k-paragraphs-end-dark.png`.
- Regression: every earlier test green; the metrics test pins row heights for all block kinds at
  two widths and two text scales. The user's imported pages were not re-run here (they live on the
  user's machine); the fence parser did not change in this task.
- Not measured: Windows itself (no Windows machine in this environment) and memory use.

## Tests executed and actual results (Task 7)
- `flutter analyze`: no issues. `flutter test`: 110 passed, 2 skipped by design.
- New tests: inline formatting keys (block_editor_test), arrows out of a code space and the
  context menu's cut / paste / copy all (code_block_test).
- Found while writing the arrow test: on desktop `re_editor` binds the arrow keys itself, so the
  Task 6 arrow code never ran there (the widget tests had used the Android key path). Fixed by
  overriding the editor's cursor-move action; the tests now run with the Windows key bindings.
- Release build under Xvfb: Ctrl+B on a selected word → `**bold**`; Up from the first code line and
  Down from the last moved to the paragraphs around the code; the saved file was correct.

## Tests executed and actual results (Task 6)
- `flutter analyze`: no issues. `flutter test`: 107 passed, 2 skipped by design (the real-zip and
  real-pages tests that need the user's local copies).
- New: `test/code_languages_test.dart` (13), `test/code_block_test.dart` (11). Updated for the new
  code body: `home_page_test.dart` (the `.py` page is a `CodeEditor`, the composer is the only
  TextField), `block_editor_test.dart`, `slash_menu_test.dart`.
- Found and fixed while testing: `re_editor` bound Ctrl+Enter, Ctrl+Z / Ctrl+Y and Backspace itself,
  so the page never saw them; those bindings are now removed in the code space (Backspace only while
  the block is empty) and the page's one history handles undo. A test that pasted 5,000 lines first
  "lost" the text: it only waited 1 s while language detection (500 ms) restarts the 600 ms autosave;
  the test now waits 2 s. Nothing was lost in the app.
- Linux release build under Xvfb with `xdotool`: typed Unity C# into an empty code space → header
  "C# auto", highlighted, fence saved as ` ```csharp `; pasted a Python file (tabs, `✓`) through the X
  clipboard → "Python auto", saved text byte-identical to the source; status bar line numbers match
  the file; picker search "type" → TypeScript; context menu shows copy / copy all / cut / paste /
  select all / wrap / language / caption / delete. Screenshots `docs/screenshots/11-13`.
- Regression: all earlier tests green; the real-pages round trip (45/45) is unchanged because the
  fence parser only gained an optional caption.

## Tests executed and actual results (Tasks 4-5)
- `flutter analyze`: no issues. `flutter test`: 83 passed, 2 skipped by design.
- Release build under Xvfb: `/hea` + Down + Enter made a Heading 2, `/tod` a to-do list that
  continued on Enter, `/div` a divider, `/code` a code block; the saved Markdown matched.

## Tests executed and actual results (Task 3)
- `flutter analyze`: no issues.
- `flutter test`: 69 tests passed, 2 skipped by design (the real-zip import test and the real-pages
  round-trip test run only when `STACKSPACE_AFZIP` / `STACKSPACE_PAGES` point at local copies of the
  user's export; both were run locally: 45/45 pages imported, 45/45 pages round-trip identical).
- New: `test/blocks_test.dart` (10), `test/page_document_test.dart` (5), `test/block_editor_test.dart` (6).
- Linux release build under Xvfb with `xdotool` at 25 ms per key: the typing sequence (text, `- `
  list, Tab, nested item, triple Enter, `## ` heading, ``` code block, two code lines) produced the
  same correct Markdown in three runs; Ctrl+Z twice removed the last two edits. Debug builds under
  software rendering are slower and can still drop a character typed in the instant a block
  converts; see KNOWN_ISSUES.md.
- Regression: the previous 49 tests (workspace, tools, Ollama, chat, home page, contrast,
  accessibility, import) are unchanged and green.

## Earlier results (kept for reference)
- `flutter analyze`: no issues.
- `flutter test`: 40 tests, all passed (workspace 7, tools 9, Ollama client 4, chat controller 6,
  UI 2, palette contrast 6, accessibility 6). The accessibility tests run Flutter's contrast and
  label guidelines plus a WCAG 2.2 24x24 target check on the live app in light and dark, and a
  150% text-size run. The UI tests drive the real HomePage: open/minimise/maximise/close the dock, and send
  a message that makes the model edit the open page, check the file and editor changed, then Undo.
- Ran the Linux debug build under Xvfb against a fake Ollama server (scripted replies): selected
  lines 5-10 of a script, asked for a change, and the page was edited on disk and reloaded.
- NOT tested: a real Ollama model (model downloads are blocked in the cloud environment),
  and the Windows build (needs a Windows machine).

## Outstanding failures and known issues
See KNOWN_ISSUES.md. Main ones: no real-model test yet; large files are read-only; no rich text.

## Current build status
Analyzer clean and tests green on Linux. `flutter build windows` not yet run.

## Next single task
Try test build 2 on Windows with a real Ollama model and record what is found. Columns
(side-by-side blocks) stay deferred: Markdown has no syntax for them, so they would need HTML in
the page.

## Exact commands to resume
```bash
# repo: https://github.com/BigDaddy284/StackSpace (also mirrored in the project folder windows_app/)
cd stackspace
flutter pub get
flutter analyze
flutter test
flutter run -d windows        # on Windows, with Ollama running
```

## Outstanding decisions or blockers
- None for Task 4. Test builds come from the GitHub Actions workflow (`release_tag` input).
- Task 6 chose `re_editor` + `re_highlight` (MIT) for the code space body; see DECISIONS.md.
- Code spaces auto-close brackets and auto-indent like an IDE when typing (pasting is exact). Tell
  me if you would rather have them type exactly what is pressed.
