# Bug-fix phase report (2026-10-26)

Five bugs reported from test build 2 on Windows, taken one at a time. Each entry gives the root
cause, the files changed, the fix, the tests, the actual results, and what is still uncertain.
"Live" means the Linux release build driven with real X key and mouse events; no Windows machine
was available, so every Windows statement below is marked as such. Test build 3 (v0.3.0-test.1,
version 0.3.0+3) carries all of this.

Full suite at the end of the phase: 174 passed, 2 skipped (the two skipped are the Ollama live
tests, as before); `dart analyze` clean.

## Bug 1 — Backspace in code blocks: FIXED, verified
- **Root cause** (confirmed by tests that failed before the fix). Two causes.
  (a) The code editor package builds its keyboard shortcut map once and then changes it *in place*
  when its key set changes. Our key set left Backspace out while a block was empty and added it once
  text was typed. Flutter's `ShortcutManager` compares the old and new maps by content, so a map
  changed in place was never re-indexed: Backspace stayed unbound in every code block that started
  empty (slash menu, ``` shortcut, Turn into). (b) A paragraph turned into a code block kept its focus
  node; the code editor only opens its keyboard connection on a focus *change*, so such a block never
  received typed text at all (pasted text arrived through a shortcut, which is how code got in and
  could not be deleted).
- **Files**: `lib/ui/editor/code_block.dart`, `lib/ui/editor/block_editor.dart`.
- **Fix**: the key set is constant and always includes Backspace; the empty-block case is decided at
  key time in an override of the delete action, which asks the block editor to turn the block back into
  a paragraph. Code spaces get their own focus nodes, so a conversion is a focus change.
- **Tests**: `test/code_block_test.dart` +2. Both failed before the fix and pass after.
- **Actual results**: live: typed into a fresh code block, Backspace deleted, emptying the block then
  one more Backspace made it a paragraph, one more merged with the paragraph above. Repeated in the
  combined pass.
- **Uncertainty**: not run on Windows; the key handling is framework code that is the same there.

## Bug 2 — Links: paste as links, create, open: FIXED, verified
- **Root cause**: missing behaviour rather than a regression. Links were styled but nothing opened
  them, bare URLs were plain text, a pasted URL stayed plain text, and a link could not be removed.
- **Files**: new `lib/editor/links.dart`; `lib/ui/editor/block_editor.dart`,
  `lib/ui/editor/inline_markdown.dart`, `lib/ui/editor/format_toolbar.dart`, `lib/ui/home_page.dart`
  (shortcut list). Package `url_launcher` 6.3.3 (BSD-3) added, recorded in DECISIONS.md.
- **Fix**: a URL pasted over selected words becomes `[words](url)`; a URL pasted or typed alone stays a
  bare link; Ctrl+K and the toolbar Link button link a selection, link a selected URL, or unlink;
  Ctrl+click (Cmd on Mac) opens a link in the system browser; on a read-only page a plain click
  opens. Only `http`, `https` and `mailto` are ever opened; `javascript:`, `file:` and anything else
  are refused with a message, and the exact destination is passed to the launcher.
- **Tests**: `test/links_test.dart` (11), including the exact URI handed to the launcher.
- **Actual results**: live with a stand-in browser registered as the system handler: Ctrl+click on a
  Markdown link and on a bare URL each launched it with `https://example.com/page`; a plain click did
  not; in-app copy and paste of the URL over a double-clicked word gave
  `[page](https://example.com/page)` in the saved file.
- **Regression found and fixed in the combined pass**: typing a URL one letter at a time was turned
  into `[https://](https://e)` at the ninth letter, because the paste check took that one-letter change
  for a paste of `https://e` over `https://`. A change that adds a single character is now never a
  paste. Covered by a new editor test and three helper cases; re-checked live on the rebuilt app.
- **Uncertainty / limit**: hyperlinks copied from a web page paste as their visible text, because
  Flutter's desktop clipboard carries plain text only (a URL copied from the address bar works).
  Hovering does not yet show a link's destination.

## Bug 3 — Folder expand / collapse state: FIXED, verified
- **Root cause** (confirmed): the folded set lived only in the panel widget's state. Hiding the panel
  removes that widget, so the set was lost; nothing was saved, so a restart lost it too.
- **Files**: `lib/app/settings.dart`, `lib/ui/sidebar.dart`, `lib/ui/home_page.dart`.
- **Fix**: the folded folders are saved per workspace (keyed by the workspace root) in the existing
  settings store, using folder paths as the identifier (a folder on disk has no other stable id).
  The panel loads the set when built, saves on every toggle, moves entries on rename or move
  (including nested folders), drops them on delete, and reloads when the workspace changes.
- **Tests**: `test/home_page_test.dart` +1 (fold, hide and show, nested, rename, move, delete, restart).
- **Actual results**: live: folded `docs`, hid and showed the panel, killed and restarted the app;
  folded each time; the settings file holds the list.
- **Uncertainty**: none known. Folders renamed outside the app while it is closed come back expanded,
  which is the intended default.

## Bug 4 — Create New Folder does nothing: FIXED, verified
- **Root cause** (confirmed): the whole path worked and the folder was created on disk, but the
  panel hid every folder with no page under it (a rule meant for folders holding only pictures), so
  a new, empty folder never appeared. Also found on the same path: a duplicate name was silently
  accepted, a name the file system refuses raised an unhandled exception, and the prompt dialog
  disposed its text controller during its closing animation. `File > New folder` with the panel
  hidden did nothing because the panel did not exist.
- **Files**: `lib/ui/sidebar.dart`, `lib/workspace/workspace.dart`, `lib/ui/dialogs.dart`,
  `lib/ui/home_page.dart`.
- **Fix**: empty folders are listed (only a folder whose contents are all binaries stays hidden);
  errors are reported in the status bar; a blank or duplicate name is refused with a message; the
  folder menu gains "New folder here"; the File menu shows the panel first.
- **Tests**: `test/home_page_test.dart` +1 (root, nested, typed path, cancel, blank, duplicate, fold,
  rename, restart, delete). Failed before the fix, passes after.
- **Actual results**: live: `notes` appeared at once and on disk; creating `notes` again showed
  `"notes" already exists.`; still listed after a restart.
- **Uncertainty**: none known.

## Bug 5 — Intermittent black-and-white start-up: HARDENED, root cause not established
- **What was tried**: 14 consecutive launches of the Linux release build (some after dropping the OS
  file cache, some with the dark theme saved, one with a damaged settings file), each one sampled for
  pixel colours in the panel, editor and status bar; every launch rendered correctly. The screenshot
  shows a window whose client area Flutter never painted (dark title bar from the runner, unpainted
  white and black areas, no text), which points at something before the first frame.
- **Candidate causes**: (a) start-up stalled or threw before the first frame. The old `main()` awaited
  the settings file before `runApp`; a settings file that cannot be parsed (left by a crash, or by two
  instances started in quick succession) threw with nothing drawn. (b) The workspace could not be
  opened and the old loading state never changed. (c) A graphics fault in the Windows embedder, which
  the app cannot fix but can now show in its log.
- **Files**: `lib/main.dart`, `lib/app/app.dart`, `lib/app/settings.dart`, new
  `lib/app/startup_log.dart`, `lib/ui/home_page.dart`, `windows/runner/win32_window.cpp` and `.h`.
  Packages `path_provider`, `shared_preferences_platform_interface` (BSD-3).
- **Fix**: a themed start-up screen is drawn before anything is loaded; unreadable settings fall back to
  defaults with the reason logged; a workspace that cannot be opened shows "Workspace not available"
  with Try again; uncaught errors are logged; the Windows window paints its own background in the
  app's colour so an undrawn area is never white or black; `startup.log` records every launch step.
- **Tests**: `test/startup_test.dart` (4).
- **Actual results**: all 14 Linux launches and the combined-pass restart drew correctly; the damaged
  settings launch started with defaults and logged the parse error; the first frame is logged at
  24–36 ms. The first push of the runner change failed to compile on the Windows CI build (a static
  function setting a member); fixed, and test build 3 is cut only from a green Windows build.
- **Uncertainty**: the bug could not be reproduced, so this is prevention plus diagnosis, not a
  confirmed fix. If a launch shows a blank window again, please send
  `%APPDATA%\com.stackspace\stack_space\startup.log`: it says which step was reached.

## Data safety
No AppFlowy data was touched: the user's workspace zip is read-only test input and was not modified
or re-imported during this phase; all live runs used scratch workspaces.
