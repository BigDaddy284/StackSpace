# Improvement Phase 1 — final report

_2026-10-25. Advanced editor, slash menu, code spaces and the AppFlowy / Notion feature research._
_Repository: https://github.com/BigDaddy284/StackSpace (branch `main`, commits 85a004d … a3f12c6)._

## What was investigated

- **What AppFlowy and Notion offer** for documents, code, slash menus and databases, classified
  into must-have / nice-to-have / out of scope (`EDITOR_FEATURE_RESEARCH.md` §3–7).
- **Building blocks on pub.dev** with their licences (§8), and two spikes (§11): `re_editor`
  lays out 100,000 lines in about 30 ms per operation; `appflowy_editor` compiles from git but was
  ruled out because the rule for this project is no code from other note apps.
- **Where the time goes in long pages** (Task 8): Flutter's variable-height list lays out every
  block between the current position and a jump target, so a scrollbar drag to the end of a
  5,000-paragraph page took 60 s in the test VM. Measured parse / write / load / edit for 5k–100k
  lines in three page shapes and open / first frame / keystroke / jump in the editor.
- **Three bugs found by the new tests and fixed on the way**: overlapping autosaves could leave an
  older version on disk (Task 9); one-line rows had slipped under the 24 px tap-target rule once the
  handle stopped them merging with their padding (Task 9); row heights ignored the 3 px caret margin
  a text field keeps at its right, so a to-do item wrapping at the edge measured one line short
  (Task 11).

## What was implemented

| Task | Result |
| --- | --- |
| 3 | Own block editor: Markdown ↔ blocks with an exact round trip, undo / redo, one field per block, keyed virtual list, Enter / Backspace / Tab / arrows / Ctrl+Shift+arrows, Markdown shortcuts (`# `, `- `, `1. `, `[] `, `> `, ``` ```, `---`). |
| 4–5 | Slash menu with 13 commands, aliases, search, keyboard and mouse, edge flipping, never inside code or plain files. |
| 6 | Code spaces: distinct background, line numbers, highlighting for 30 languages, searchable language picker, **automatic language detection for typed or pasted code** (written into the fence, "auto" shown), copy button, wrap toggle, caption on the fence line, context menu; `.py` / `.json` / … files open as one code space. |
| 7 | Ctrl+B / I / E / K and Ctrl+Shift+X wrap or unwrap the selection with Markdown markers; arrows leave a code space at its edges; clipboard tests with tabs and Unicode. |
| 8 | Pre-measured row heights (`BlockMetrics`) so a jump to any point of a 50,000-block page lays out only the rows that show there; read-only threshold raised to 250k lines / 16 MB. |
| 9 | Floating toolbar on a selection (Bold, Italic, Strikethrough, Inline code, Link, Turn into) and a block handle with a menu (Turn into, Duplicate, Move up / down, Delete). |
| 10 | Tables as a grid of cells (Tab / Enter / arrows between cells, add / remove row and column, padded Markdown kept in the page); images from a file picker, path or link, outside files copied to `images/` next to the page, alt-text field under every picture. |
| 11 | Folding sections (a chevron beside every heading, Collapse / Expand in the block menu; view state only) and block drag-and-drop with an insertion line and auto-scroll. |

Everything is in `windows_app/lib/` (35 Dart files); the editor is `lib/editor/` (model) and
`lib/ui/editor/` (widgets). Packages added: `re_editor` 0.10.0 and `re_highlight` 0.0.3 (MIT),
`file_selector` (BSD-3). No code from AppFlowy, Notion or any other note app.

## What was preserved

- The page is always plain Markdown on disk: an unedited page writes back byte for byte (CRLF,
  blank lines, bullet characters, fence languages, table lines); folding, the toolbar, the block
  menu and the grid are all view state. The assistant keeps editing Markdown and the editor reloads
  from the file.
- The working app from before the phase: pages sidebar, Ollama assistant with tools, settings,
  light / dark themes, accessibility checks, AppFlowy import. All of its tests still pass.
- Your AppFlowy workspace export was never modified; every experiment ran on copies or test data in
  temporary folders.

## Tests and their actual results

| Run | Result |
| --- | --- |
| `flutter analyze` | No issues |
| `flutter test` (without the timing file) | 132 passed, 2 skipped by design (were 49 at the start of the phase) |
| `flutter test test/performance_test.dart` | 21 timing tests passed |
| Live runs | Linux release build under Xvfb after each task; screenshots 8–20 in `docs/screenshots/` |

Per-task results with the exact numbers are in `PROJECT_STATUS.md`; the test matrix is in
`TEST_PLAN.md`.

## Performance (test VM, JIT; the release build is faster)

| Page | Parse | Open to first frame | One keystroke | Jump to end |
| --- | --- | --- | --- | --- |
| 10,000-line code block | 2 ms | 109 ms | 65 ms | 1 ms |
| 10,000 paragraphs | 9 ms | 553 ms | 354 ms | 694 ms |
| 50,000 paragraphs | 51 ms | 624 ms | 437 ms | 852 ms |
| 100,000 paragraphs | 122 ms | – (read-only threshold is 250k lines) | – | – |

The jump to the end of 5,000 paragraphs went from 60 s to 0.56 s. In the release build a
50,000-paragraph page opens, jumps to its end and takes typing without a visible pause.

## Limitations (all in `KNOWN_ISSUES.md`)

- Selection cannot span blocks; Ctrl+A selects the current block. Links are styled but not
  clickable.
- Table cells hold one line and columns share the width equally; alignments in the file are kept
  but cannot be set from the grid.
- A folded section is remembered only while the page is open.
- The sidebar lists every file, so a picture copied into `images/` shows there too.
- Columns (side-by-side blocks) are deferred: Markdown has no syntax for them.
- Not run on Windows in this environment (no Windows machine); no real Ollama model test yet.

## Suggested next task

Task 12: hide non-text files from the sidebar and open them in the system viewer, then run
`flutter build windows` on a Windows machine with a real Ollama model and record the results.
