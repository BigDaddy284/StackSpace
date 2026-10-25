# PROJECT STATUS

_Last updated: 2026-10-25 (Improvement Phase 1, Tasks 1-6 done)_

## Current phase
Improvement Phase 1: advanced editor, slash menu, code spaces. Working one task at a time.
Test build 1 (v0.1.0-test.1) is published on GitHub and loads the user's AppFlowy workspace.

## Current task and scope
Tasks 1-6 done: research, plan, the block editor, the slash menu with its tests, and code spaces
(highlighting, automatic language detection, picker, copy, wrap, caption, menu) with their tests.
Next: Task 7, the remaining Markdown shortcuts (`**bold**`, `` `code` `` wrapping of a selection)
and any code space test gaps; then Task 8, large-page performance measurements.

## Task log (Phase 1)
| Task | Status | Tests | Files |
| --- | --- | --- | --- |
| 1. Baseline + research | Done 2026-10-25. `flutter analyze` clean, `flutter test` 49 passed, Linux debug build OK, Git checkpoint on `main`. | 49/49 | `docs/EDITOR_FEATURE_RESEARCH.md`, docs copied into `docs/` |
| 2. Matrix + plan + spikes | Done 2026-10-25. Feature matrix (§8), spikes (§11: `re_editor` handles 100k lines in ~30 ms per operation; `appflowy_editor` compiles from git but is ruled out), prioritised plan (§12). | 49/49 | `docs/EDITOR_FEATURE_RESEARCH.md` |
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
Task 7: close the code space test gaps (context menu actions, cut / paste through the editor,
arrow navigation out of a code space) and the remaining Markdown shortcuts (`**` and `` ` `` around a
selection). Then Task 8: measure 5k / 10k / 50k-line pages in tests and in the release build, and
revisit the 100k-line read-only threshold now that code spaces use `re_editor`.

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
