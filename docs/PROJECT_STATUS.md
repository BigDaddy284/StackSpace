# PROJECT STATUS

_Last updated: 2026-10-25 (Improvement Phase 1, Task 1 done)_

## Current phase
Improvement Phase 1: advanced editor, slash menu, code spaces. Working one task at a time.
Test build 1 (v0.1.0-test.1) is published on GitHub and loads the user's AppFlowy workspace.

## Current task and scope
Task 1 done: baseline confirmed and research written (`docs/EDITOR_FEATURE_RESEARCH.md`).
Next: Task 2, the prioritised implementation plan, then Task 3, the architecture decision
(block editor approach) with a spike.

## Task log (Phase 1)
| Task | Status | Tests | Files |
| --- | --- | --- | --- |
| 1. Baseline + research | Done 2026-10-25. `flutter analyze` clean, `flutter test` 49 passed, Linux debug build OK, Git checkpoint on `main`. | 49/49 | `docs/EDITOR_FEATURE_RESEARCH.md`, docs copied into `docs/` |

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

## Tests executed and actual results
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
Task 2: produce the feature comparison matrix (done inside the research doc) and the prioritised
implementation plan; then Task 3: audit the editor architecture and run the spike that decides
between adopting `appflowy_editor` (MPL-2.0) with a StackSpace code block, or a Markdown-first
editor (see research §9). The user has been asked to confirm the licence choice.

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
- Building the .exe: the user asked to wait. When ready, it needs Windows (or a GitHub Actions
  Windows runner once the code is in a repo).
