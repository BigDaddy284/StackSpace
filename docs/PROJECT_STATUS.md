# PROJECT STATUS

_Last updated: 2026-10-26 (Bug-fix phase: Bugs 1-5 fixed; Bug 5 confirmed with test build 9)_

## Current phase
Bug-fix phase (2026-10-26): five bugs reported from test build 2 on Windows, fixed one at a time in
the order given (code block keys, links, folder state, New folder, startup rendering). Phase 1 is
complete; see the Phase 1 sections below.

## Bug-fix log
| Bug | Status | Root cause | Fix and files | Tests and actual results |
| --- | --- | --- | --- | --- |
| 1. Backspace in code blocks | **Fixed 2026-10-26** (verified by tests and a live run on Linux; the reporter's machine is Windows, where the same framework code runs). | Two causes, both confirmed by a test that failed before the fix. (a) The code editor (`re_editor`) builds its shortcut map once and mutates it in place when its key set changes; our key set dropped Backspace while the block was empty and added it once text was typed, and Flutter's `ShortcutManager` compares the old and new map by content, so a map changed in place was never re-indexed. Any code block created empty (slash menu, ``` shortcut, Turn into) and typed into therefore ignored Backspace for good; a block emptied by deleting kept swallowing it instead of becoming a paragraph. (b) A paragraph turned into a code block keeps its id and so kept its `FocusNode`; the code editor only opens its text-input connection on a focus *change*, so a code block made from a focused paragraph never received typed text at all (keys that are shortcuts, such as paste, still worked, which is how code could get in and then not be deleted). | (a) `lib/ui/editor/code_block.dart`: the key set is now constant (`_CodeShortcuts()` always includes Backspace); the empty-block case is decided at key time in an override of the delete action, which calls `onBackspaceEmpty` (new `CodeBlockView` callback) and the block editor converts the block. (b) `lib/ui/editor/block_editor.dart`: code spaces get their own focus nodes (`_codeFocus`), so a conversion in either direction is a focus change and the new editor attaches its input. | `test/code_block_test.dart` +2: "Backspace deletes in a code block that started empty, and still converts it once emptied" (a key event before typing indexes the shortcuts the way a real keyboard does; Backspace at the end, in the middle, over a multi-line selection; Delete, Home, End; emptying then converting) and "a code space made from a paragraph takes the keyboard input straight away" (the attached input client must be the delta-model one, text sent through the platform channel lands in the block, Backspace works, and after converting back the paragraph takes input). Both failed before the fix (`Actual: 'abc'` / no delta client) and pass after. Full suite 136 passed, 2 skipped; analyzer clean. Live (Linux release build, real X key events): ``` → typed `print(1)` → three Backspaces left `print` → Delete at Home → `rint` → six Backspaces emptied and converted the block → one more merged with the paragraph above → typing continued there; saved file correct. Enter, Tab, arrows, undo / redo covered by the existing code block tests. |
| 2. Links: paste, create, open | **Fixed 2026-10-26** (tests + live run on Linux with a stand-in browser registered as the system handler). | Not a regression but missing behaviour: the editor styled `[label](url)` but nothing opened a link, a bare `https://…` was plain text, a pasted URL was plain text, and there was no way to remove a link. The clipboard gives Flutter plain text only, so links copied from a web page arrive as their text (destinations are not available to the app; a copied address bar URL is). | New `lib/editor/links.dart`: `linksIn` / `linkAt` (Markdown links and bare `http(s)://` / `www.` URLs, trailing punctuation excluded), `pastedUrl` (a change that inserted exactly one URL and what it replaced), `safeUri` (only `http`, `https`, `mailto`; `javascript:`, `file:` and the rest are never opened), `openLink` (url_launcher, external application; failures reported in a snackbar). `inline_markdown.dart` styles bare URLs as links. `block_editor.dart`: a URL pasted over selected words becomes `[words](url)` (not inside an existing link, not over several lines); Ctrl+K / the toolbar's Link button wraps the selection, or with a URL selected makes `[text](url)` with `text` selected, or on an existing link removes it and keeps the label; Ctrl+click (Cmd on Mac) on a link opens it, a plain click only places the caret, on a read-only page any click opens; Help > Keyboard shortcuts lists them. Package `url_launcher` 6.3.3 (BSD-3) added. | New `test/links_test.dart` (10): helpers (finding, caret lookup, paste detection with shared letters such as "here" → "https", safe schemes, launcher called with the exact URI and never for unsafe ones, renderer styles); editor: paste over words links them, a URL pasted alone stays bare, multi-line paste keeps text and links, ordinary paste unchanged, saved file exact; Ctrl+click opens the exact destination, plain click only edits, bare URL opens, Ctrl+click on plain text opens nothing; read-only page opens on a click; Ctrl+K link / link a selected URL / unlink, save, reopen. `block_menu_test.dart` tooltip updated. Full suite 146 passed, 2 skipped; analyzer clean. Live (Linux release build, stand-in browser registered as the `x-scheme-handler/https` default): Ctrl+click on the bare URL and on the Markdown link launched the handler with `https://example.com/page` and `https://docs.example.com/x`; a plain click did not; the URL copied inside the app and pasted over a double-clicked word gave `Read the [manual](https://example.com/page) today.` in the file. Limitation: hyperlinks copied from a web page paste as their text (Flutter's clipboard has no HTML on desktop). **Regression found in the combined pass and fixed the same day**: typing a URL one letter at a time turned `https://` + `e` into `[https://](https://e)`, because the paste check took the one-letter change for a paste of `https://e` over `https://`. `pastedUrl` now ignores any change that adds a single character (a paste adds the whole URL at once); `links_test.dart` +1 editor test and +3 helper cases (typing a URL letter by letter stays as typed). Full suite 174 passed, 2 skipped. |
| 3. Folder expand / collapse state | **Fixed 2026-10-26** (test + live run). | Confirmed: the folded set was a field of the panel's widget state (`SidebarState._collapsed`). Hiding the panel removes the `Sidebar` widget from the tree, so the state was thrown away and every folder came back expanded; nothing was ever written to disk, so a restart did the same. | `lib/app/settings.dart`: `collapsedFolders(root)` / `setCollapsedFolders(root, set)` keep the folded folders per workspace (keyed by the workspace root) in shared_preferences. A folder on disk has no identity other than its path, so paths are stored; `lib/ui/sidebar.dart` loads the set when the panel is built, saves it on every toggle (dropping folders that no longer exist), moves entries on a rename / move of a folder (`WorkspaceChangeKind.renamed`, including nested entries) and removes them on a delete, and reloads when the workspace changes. New folders are expanded unless saved otherwise; nothing is expanded on start except what the saved set leaves open. `lib/ui/home_page.dart` passes the settings to the panel. | `test/home_page_test.dart` +1: fold two of three folders → saved at once (`collapsedFolders:<root>` = `[alpha, gamma]`); hide and show the panel → the same two stay folded and the third open; unfold / fold nested folders and open a page; rename a folded folder and move a folded nested folder → both stay folded under the new paths; delete one → its entry is gone; a fresh app on the same settings restores the folded set and folders still toggle. Full suite 147 passed, 2 skipped; analyzer clean. Live (Linux release build, fresh settings home): folded `alpha`, hid and showed the panel (toggle in the top bar), killed and restarted the app: `alpha` folded each time; `shared_preferences.json` holds `collapsedFolders:<root>: ["alpha"]`. One workspace at a time is supported; the key is per workspace, so switching workspaces in Settings restores each one's own set. |
| 4. New folder button | **Fixed 2026-10-26** (test + live run). | Confirmed. The button, its dialog and `Workspace.createFolder` all worked: the folder was created on disk. But the panel (since Task 12) hid every folder that had no page below it, meant for folders holding only pictures, so a new, empty folder never appeared and the click looked like it did nothing. Two smaller defects on the same path: a duplicate name was silently accepted (`Directory.create(recursive: true)` does nothing for an existing folder) and a name the file system refuses raised an uncaught `FileSystemException`; and the prompt dialog disposed its text controller on pop, during its closing animation (an assertion in debug builds). `File > New folder` with the panel hidden did nothing because the panel's state did not exist. | `lib/ui/sidebar.dart`: empty folders show (only a folder whose contents are all binaries stays hidden); `newFolder([parent])` reports `WorkspaceException` and `FileSystemException` in a snackbar; the folder context menu gains "New folder here". `lib/workspace/workspace.dart`: `createFolder` refuses an empty name and an existing path with a clear message. `lib/ui/dialogs.dart`: the prompt dialog is a widget that owns its controller. `lib/ui/home_page.dart`: `File > New folder` shows the panel first when hidden. | `test/home_page_test.dart` +1: click New folder → "Notes" shows at once and exists on disk; Cancel creates nothing; a blank name creates nothing; "New folder here" on Notes → Notes/2026; a typed path Notes/2026/Q4; a duplicate name shows "already exists"; the folder folds / unfolds, renames to Ideas, survives a restart, a nested folder deletes; existing pages untouched. Failed before the fix (`Found 0 widgets with text "Notes"`), passes after. `test/workspace_test.dart` green. Full suite 148 passed, 2 skipped; analyzer clean. Live (Linux release build): New folder → typed `Projects` → Enter: the folder appeared in the panel at once, `ws4/Projects` on disk, still listed after a restart. |
| 5. Black-and-white startup | **Hardened 2026-10-26; root cause not established.** The symptom could not be reproduced: no Windows machine here, and 14 launches of the Linux release build rendered correctly every time. | What the screenshot shows: a window with the dark title bar (so the immersive-dark flag had been set, which the runner does from the registry before Flutter draws), a white strip about 180 px wide on the left and black elsewhere, no text or controls, title `stack_space` (the runner's fixed window title; normal). That is a window whose client area was never painted by Flutter: white and black are the unpainted parent window and the child view, not any theme. Candidate causes, in order of likelihood, all consistent with "worked on the fifth try": (a) start-up stalled or failed before the first Flutter frame. In the previous build `main()` awaited the settings file before `runApp`; a settings file that cannot be parsed (truncated by a crash or by two instances started in quick succession writing it at once, which the 2nd–4th rapid launches could do) threw before any frame, and nothing was ever drawn. Reproduced on Linux: with a damaged `shared_preferences.json` the old flow would have thrown; the new flow logs `Settings could not be read, using defaults` and starts. (b) The workspace could not be read (folder locked / slow drive) and the old page stayed on a spinner. (c) A GPU / swap-chain fault in the Windows embedder: not something the app can fix, but it is now visible in the log (first frame line present but no UI) rather than silent. | `lib/main.dart`: `runZonedGuarded`, `FlutterError.onError` and `PlatformDispatcher.onError` go to the log; `runApp` happens **before** any loading with a themed `StartupScreen` (dark window colour, spinner, "Loading settings…"), then the settings load and the real app replaces it. `lib/app/settings.dart`: `AppSettings.load` falls back to in-memory defaults when the settings file cannot be read and reports why. `lib/app/startup_log.dart` (new): `startup.log` in the app support folder (`%APPDATA%\com.stackspace\stack_space\startup.log` on Windows, `~/.local/share/com.stackspace.stack_space/startup.log` on Linux), one section per launch with the OS version and pid, timed lines for binding ready, first frame, settings loaded (theme, workspace), workspace opened (entry count), first page, assistant status, and every uncaught error; kept to the last 400 lines. `lib/ui/home_page.dart`: the loading state is themed and names the folder; a workspace that cannot be opened shows "Workspace not available" with the reason, Try again and Settings…, never an endless spinner. `windows/runner/win32_window.cpp/.h`: `WM_ERASEBKGND` paints the client area in the app's window colour (dark or light from the system setting) so an area Flutter has not drawn is never white or black. Packages added: `path_provider`, `shared_preferences_platform_interface` (BSD-3). Version 0.3.0+3. | `test/startup_test.dart` (new, 4): a preferences store that throws → defaults, problem reported, settings usable; `StartupScreen` draws the dark window colour and the message; a workspace path that is a file → themed "Opening …" state, then "Workspace not available" with the path and Try again, no spinner; fixing the folder and Try again opens the app; the log trims to 400 lines. Full suite 152 passed, 2 skipped; analyzer clean. Launch runs (Linux release build, fresh settings home, `xdotool` / `import`): 10 consecutive launches, every third after dropping the OS file cache, each sampled at the panel, editor and status bar and the editor area counted for distinct colours: all 10 identical and correct (panel 250,251,254 / editor 236,240,247 / 204 colours); 3 more with the dark theme saved: panel 14,19,37 / editor 9,12,24 / 199 colours, log line `settings loaded: theme dark`; 1 with a damaged settings file: app started with defaults and logged the parse error. `startup.log` has 14 sections, first frame at 25–36 ms, no errors. **Limitation**: none of this ran on Windows. The first push of the runner change did not compile on GitHub Actions (`UpdateTheme` was static and now sets a member); fixed in the next commit, which the Windows CI build must pass before test build 3 is cut. If it happens again, `startup.log` says which step was reached; please attach it. |

## Combined regression pass (2026-10-26, Linux release build, real X events)
One session on a fresh workspace and settings home: Bug 1: ``` → typed `abc` → Backspace left `ab` → three more emptied the block → one more turned it into a paragraph. Bug 2: typing `Go to https://example.com/page now` letter by letter stayed as typed and rendered as a link (this is where the typing regression above was caught; the pass was repeated on the fixed build); the URL selected and copied inside the app, pasted over a double-clicked word → `[page](https://example.com/page)` in the file; Ctrl+click on the Markdown link and on the bare URL each launched the registered handler with `https://example.com/page`. Bug 4: New folder → `notes` → listed at once and on disk; the same name again → "\"notes\" already exists." in the status bar. Bug 3: folded `docs`, hid and showed the panel → still folded; killed and restarted → still folded. Bug 5: the restart logged binding ready, settings loaded (theme dark), first frame at +24 ms, workspace ready (4 entries), first page, assistant offline; window drawn correctly. Full suite after the fixes: 174 passed, 2 skipped; analyzer clean. The per-bug report is `docs/BUGFIX_REPORT.md`.

## Phase 1 (complete)
Test build 1 (v0.1.0-test.1) is published on GitHub and loads the user's AppFlowy workspace.
Test build 2 (v0.2.0-test.1, version 0.2.0+2) carries everything from Phase 1; test build 3
(v0.3.0-test.1, version 0.3.0+3) carries the bug-fix phase; see the GitHub releases.

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
Analyzer clean and 136 tests green on Linux; the Windows build runs on GitHub Actions.

## Windows confirmation of test build 3 (2026-10-26)
The user ran v0.3.0-test.1 on Windows: no app freezes, folders appear when created, Backspace
works in code blocks. Bugs 1 and 4 are therefore confirmed on the target machine; Bug 5 has not
recurred so far. Links (Bug 2) and fold state (Bug 3) were not mentioned either way; they are
verified by tests and Linux runs only.

## Blank window after a FancyZones snap (2026-10-26)
The user found the trigger for Bug 5: a window snapped into a PowerToys FancyZones zone opens
blank on the next launch, and the launch after that is fine. Test build 4 (v0.3.1-test.1:
reopen at last bounds, re-size the view after start-up moves) did not fix it; its `startup.log`
showed FancyZones resizing the window 29 ms into start-up and the view never drawing again even
though Dart saw every later size. Test build 5 (v0.3.2-test.1, version 0.3.2+5) shows the window
first and starts Flutter only after the window has stopped moving
(`windows/runner/flutter_window.cpp/.h`); the last-bounds restore stays
(`windows/runner/win32_window.cpp/.h`). `lib/main.dart` logs the view size at the first frame and
on resizes in the first ten seconds. Built and tested on GitHub Actions only; see
`docs/KNOWN_ISSUES.md`, Bug 5. Build 5 still opened blank with no start-up resize at all, so test
build 6 (v0.3.3-test.1, version 0.3.3+6) adds a native log (`windows/runner/native_log.cpp/.h`,
`native.log` next to `startup.log`) with the engine's error output and the window's state.
Build 6 did not start (the log redirect ended the process); test build 7 (v0.3.4-test.1, version
0.3.4+7) fixes that. Build 7 still went blank intermittently, and its `native.log` showed why:
FancyZones moves and hides the Flutter view window itself (it sees it as a new StackSpace window
for a moment while Flutter creates it). Test build 8 (v0.3.5-test.1, version 0.3.5+8) guards the
view and puts it back. Build 8's blank launches look like an older copy of the app being started
(no guard lines at all); test build 9 (v0.3.5-test.2, version 0.3.5+9) logs the version and exe
path per launch. See `docs/KNOWN_ISSUES.md`, Bug 5.

## Table column widths and multi-cell copy and paste (2026-10-26)
Table build (v0.3.6-test.1, version 0.3.6+10) makes table columns resizable by dragging their borders (widths
are kept on a `<!-- table-widths: ... -->` line under the table) and adds spreadsheet-style cell
selection with copy, cut, delete and paste of tab-separated text. Built on top of test build 9 (v0.3.5-test.2).
See `docs/DECISIONS.md`, "Table column widths and multi-cell copy and paste".

## Next single task
Bug 5 is confirmed fixed with test build 9 (v0.3.5-test.2). If a blank launch ever returns, send `native.log` and
`startup.log` from `%APPDATA%\com.stackspace\stack_space\`. No code task is queued; the next
phase starts from the user's next request.

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
