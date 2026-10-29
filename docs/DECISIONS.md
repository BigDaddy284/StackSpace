# DECISIONS

## Overview
This document records architectural and implementation decisions made during the audit phase of the AppFlowy replacement project.

## Key Decisions

### 1. Audit Approach
**Decision**: Follow the strict one-task-at-a-time workflow as specified in the project instructions.
**Rationale**: Ensures methodical analysis without skipping important steps or rushing implementation.
**Status**: Implemented

### 2. Repository Analysis Focus
**Decision**: Begin by thoroughly analyzing the original AppFlowy repository to understand its architecture and identify performance bottlenecks.
**Rationale**: Must fully understand the problem before implementing a solution.
**Status**: In Progress

### 3. Windows 11 Compatibility First
**Decision**: Prioritize Windows 11 specific requirements in our analysis.
**Rationale**: The project explicitly states that Windows 11 is the primary target platform.
**Status**: Implemented

### 4. Large Document Performance Focus
**Decision**: Specifically focus on identifying and addressing freezing/crash issues with large documents (>5,000 lines).
**Rationale**: This is the core problem statement for this replacement project.
**Status**: Implemented

### 5. Architecture Documentation First
**Decision**: Create comprehensive architecture documentation before beginning implementation.
**Rationale**: Ensures we have a clear plan and understanding of what needs to be built.
**Status**: In Progress

### 6. Testing Framework Establishment
**Decision**: Establish test plans and benchmarks before implementing features.
**Rationale**: Enables measurable progress and ensures performance targets are met.
**Status**: In Progress

## Technical Decisions

### 1. Virtualization Approach
**Decision**: Plan to use virtualized rendering for large documents to avoid loading entire documents into memory.
**Rationale**: Direct loading of large documents causes the freezing issues described in requirements.
**Status**: Planned

### 2. Asynchronous Processing
**Decision**: Implement asynchronous processing for heavy operations to prevent UI blocking.
**Rationale**: Critical for maintaining responsiveness with large document handling.
**Status**: Planned

### 3. Clipboard Optimization
**Decision**: Design optimized clipboard handling for large content with chunked processing.
**Rationale**: Clipboard operations are identified as a source of freezing/crashes.
**Status**: Planned

### 4. Memory Management
**Decision**: Implement efficient memory management strategies for large documents.
**Rationale**: Prevents memory leaks and unbounded growth during editing sessions.
**Status**: Planned

## Resource Allocation Decisions

### 1. Separate Development Environment
**Decision**: Use a completely separate directory from existing AppFlowy installations.
**Rationale**: Protects original data and ensures clean development environment.
**Status**: Implemented

### 2. Version Control Usage
**Decision**: Use version control with meaningful checkpoints throughout development.
**Rationale**: Essential for tracking progress and maintaining stability.
**Status**: Implemented

### 3. Documentation Maintenance
**Decision**: Maintain PROJECT_STATUS.md continuously with updates after each task.
**Rationale**: Required by project specification for tracking progress.
**Status**: Implemented

## Risk Management Decisions

### 1. Data Safety First
**Decision**: Never modify or delete existing AppFlowy installation or personal data.
**Rationale**: Explicit requirement to protect user's original installation.
**Status**: Implemented

### 2. Performance Validation
**Decision**: Establish clear performance targets and validate against them.
**Rationale**: Required by project specification to ensure solutions meet needs.
**Status**: Planned

### 3. Gradual Implementation
**Decision**: Implement features incrementally, testing each before moving to next.
**Rationale**: Follows the one-task-at-a-time workflow requirement.
**Status**: Implemented

## Decisions made 2026-10-25

### Replace the prototype instead of patching it
**Decision**: Move `lib/plugins` and its tests to `windows_app/legacy/` and build new code in `lib/`.
**Rationale**: The prototype had about 40 compile errors and never ran. Its renderer showed generated
"Line N" text instead of the document, `saveDocument()` wrote an empty list (it would have erased
files), and paste did nothing. The tests called other files' private methods, which Dart forbids.
**Status**: Done. Kept for reference only.

### Pages are plain files in a workspace folder
**Decision**: A workspace is a folder (default `Documents\StackSpace`); each text file is a page.
**Rationale**: Scripts and notes stay usable outside the app, the assistant can edit them with simple
file tools, and nothing depends on AppFlowy's CRDT storage. Rich text and databases come later.
**Status**: Done.

### Local AI through Ollama's REST API
**Decision**: Talk to Ollama over HTTP (`/api/chat` streaming, `tools`, `think`), default `http://127.0.0.1:11434`.
**Rationale**: The user asked for local models via Ollama. `127.0.0.1` avoids Windows resolving
`localhost` to IPv6 when Ollama only listens on IPv4.
**Status**: Done.

### Thinking level mapping
**Decision**: Off sends `think: false`. Low/Medium/High send the level string to gpt-oss models and
`think: true` to other thinking models. Models without the `thinking` capability get no `think` field.
**Rationale**: Ollama rejects `think` for non-thinking models, and only some models take levels.
**Status**: Done.

### Safety for AI changes
**Decision**: Deletes go to `.trash` and ask the user first (can be turned off). Every AI change
has an Undo button. The editor is read-only while the assistant runs. Paths can't leave the workspace.
**Rationale**: The assistant can create, edit and delete pages, so every change must be reversible.
**Status**: Done.

### Stills & Reels look, copied from its source
**Decision**: Take every colour value-for-value from Stills & Reels' `src/Theme.cs` (dark and light
palettes), and rebuild its controls from `src/UiControls.cs`: ThemedButton (normal, primary gradient,
checked, compact), the glowing mode pill, section labels, toggles, the 60px top bar and 46px status bar,
and the Windows title bar colour. An earlier version sampled colours from a screenshot and looked off.
**Accessibility deviations** (kept deliberately, both small):
- Stills & Reels uses Muted for small labels; it is below 4.5:1 (3.9 dark, 3.0 light), so StackSpace
  uses SubText for text and keeps Muted for disabled controls.
- Stills & Reels' selected pill cell lightens towards (90,150,255), leaving its white label at 3.6:1.
  StackSpace darkens that gradient slightly so the label is at least 4.5:1.
- White on the primary gradient is 4.66 at the blue end but 4.03 at the purple end in dark mode,
  the same as Stills & Reels. It passes the large-text level only; left as is to match.
**Status**: Done. `test/theme_contrast_test.dart` pins the palette and checks the pairs.

## Decisions made 2026-10-25 (Improvement Phase 1, Task 3)

### No code from other note apps; StackSpace has its own block editor
**Decision**: The editor is written for StackSpace (`lib/editor/`, `lib/ui/editor/`). Nothing is
copied from AppFlowy, Notion or any other note app, and `appflowy_editor` (AGPL-3.0 / MPL-2.0) is
not used, even though it compiles from git. Ordinary open-source Flutter packages under permissive
licences (MIT, BSD, Apache-2.0) may be used; each one is listed here when it is added.
**Rationale**: The user's rule ("we can't reuse code from other apps", "fine if the Flutter licences
allow it"). It also keeps the whole editor under the MIT licence of the repo.
**Status**: Done. Packages in use: `http`, `shared_preferences`, `path`, `archive`, `collection`,
`file_selector`, `url_launcher` (all BSD-3); from Task 6 also `re_editor` 0.10.0 and `re_highlight`
0.0.3 (both MIT, Reqable). `flutter_svg`, `provider` and `intl` were unused and removed.

### Markdown stays the file format; blocks are the editing view
**Decision**: A page file stays plain Markdown. The editor reads it into a list of blocks (heading,
paragraph, bullet / numbered / todo item with nesting, quote, code fence with language, divider,
image, table, raw HTML) and writes blocks back. The reader records the blank lines between blocks
and the bullet character, so an unedited page writes back byte for byte. Anything unknown is kept
verbatim as a raw block. Files that are not Markdown (`.py`, `.json`, ...) open as one code block.
**Rationale**: The assistant and its tools keep working on plain text; the user's imported AppFlowy
pages stay readable outside the app; and a page with thousands of lines of code lays out only the
blocks on screen instead of one giant text run (AppFlowy's freeze).
**Status**: Done. `test/blocks_test.dart` round-trips every one of the 45 imported pages identically
when `STACKSPACE_PAGES` points at the import folder.

### Enter, list continuation and Markdown shortcuts act on the text, not on key events
**Decision**: The editor splits a block when a newline arrives *in the text update* from the
platform, not when it sees the Enter key. The same goes for `# `, `- `, `1. `, `[ ] `, `> `,
`---` and ``` shortcuts. When the editor changes a field's text itself (clearing `- `, moving the
caret's text to a new block), it remembers the change and maps any late update from the platform
that was still based on the old text onto the new one.
**Rationale**: On desktop the platform's text input holds its own copy of the text and sends key
events ahead of text updates. Handling Enter as a key dropped or misplaced characters typed in the
same instant (found under a virtual display at 20 keys per second). The text-ordered path, the
reconciliation and one stable widget tree around every field (so a paragraph turning into a
heading never recreates its text field) fixed it: three replays at 40 keys per second in a release
build came out identical.
**Status**: Done. `test/block_editor_test.dart` covers it.

### Caret moves do not rebuild the window
**Decision**: Caret and selection changes fire a separate notifier (`caretChanges`) that only the
status bar and the composer's context chip listen to. The page's Markdown and block line numbers
are cached per document version.
**Rationale**: Rebuilding the whole window and re-encoding the page on every keystroke made the
editor fall behind fast typing.
**Status**: Done.

## Next Steps Based on Decisions

1. Complete analysis of original AppFlowy repository
2. Document specific performance bottlenecks identified  
3. Finalize architecture recommendations based on findings
4. Begin implementation planning with smallest sensible task

## Decision Review Process

### Review Frequency
- Review decisions after each major milestone
- Update as new information becomes available during audit
- Ensure alignment with project requirements

### Decision Change Protocol
- Any changes to documented decisions must be recorded with rationale
- All decisions should align with the core project mission
- Maintain consistency with Windows 11 compatibility focus
## Decisions made 2026-10-25 (Improvement Phase 1, Task 6)

### Code spaces use `re_editor` for the body and `re_highlight` for colours
**Decision**: A code block's body is a `re_editor` `CodeEditor` (MIT) with line numbers, horizontal
scrolling or wrapping, bracket pairing and auto-indent, highlighted by `re_highlight` (MIT port of
highlight.js). Everything around it is StackSpace code: the header (language label, wrap, copy,
menu), the searchable language picker, captions, the context menu, and the keys that tie it into the
page (Ctrl+Enter leaves the block, Backspace on an empty block turns it back into a paragraph,
arrows at the edges move between blocks). The editor's own undo/redo and Ctrl+Enter bindings are
turned off so the page keeps one history.
**Rationale**: The spike in `EDITOR_FEATURE_RESEARCH.md` §11 showed `re_editor` lays out 100,000
lines in tens of milliseconds, which a plain TextField cannot; both packages are permissively
licensed and are generic editor components, not note-app code. Writing a highlighter for 30
languages would have cost the rest of the phase.

### The language of typed or pasted code is guessed, and the picker overrides it
**Decision**: A code block without a language in its fence is guessed 500 ms after the last edit
(`lib/editor/code_languages.dart`): a JSON check, then signature patterns for the common cases
(shebangs, `using UnityEngine`, `def ...:`, `<?php`, `#include`, `SELECT ... FROM`, PowerShell verbs,
...), then highlight.js' relevance scoring with a threshold. The guess is written into the fence
(` ```csharp `) so other tools see it, and the header shows "auto". Picking a language by hand stops
the guessing for that block; "Auto-detect" in the picker turns it back on. A language that came from
the file is never re-guessed. Files such as `.py` or `.json` take their language from the extension.
**Rationale**: The user's request ("auto pick up language for typed/pasted code") with the picker as
the override; a guess that keeps changing under a user who chose a language would be worse than none.

### Every row's height is known before it is built (Task 8)
**Decision**: The block list gives each row a fixed extent computed by `BlockMetrics`, which mirrors
the row widgets exactly (theme input style merged like a TextField does, strut, paddings, marker
sizes) and is verified against rendered rows by a test. Rows are wrapped in an `OverflowBox` so a
wrong number could only overlap, never squeeze a field. Pictures are shown in a fixed 300 px box.
**Rationale**: Flutter's variable-height list lays out every child between the current position and
a jump target, so dragging the scrollbar to the end of a 5,000-paragraph page took 60 s in the test
VM (seconds in release). With known extents the jump costs a sum of numbers: 0.85 s for 50,000
paragraphs in the test VM, immediate in the release build. The alternative of estimating heights and
correcting them as rows appear would make the page jump under the user.
**Status**: Done. Read-only threshold raised to 250,000 lines / 16 MB on the measurements.

### The toolbar and block menu edit Markdown text, not styles (Task 9)
**Decision**: The floating toolbar applies the same marker edits as the keys (`**`, `_`, `~~`,
`` ` ``, `[text](url)`) around the selected words, and "Turn into" rewrites the block's kind in the
document; the block menu duplicates, moves and deletes blocks through `PageDocument`. Underline is
not offered because Markdown has no marker for it. Writes to disk are serialised: a flush that
starts while another is still writing waits, then writes the newest text.
**Rationale**: Pages stay plain Markdown that the assistant and other tools can read; every action is
one undo step; a slow disk can never leave an older version on top of a newer one (found by the
block-menu test, which edits faster than the file system answers).
**Status**: Done; `test/block_menu_test.dart`.

### Tables are edited as cells but stored as padded Markdown (Task 10)
**Decision**: A table block keeps its Markdown lines as its text. The editor shows them as a grid
of single-line cells and writes padded `| a | b |` lines back on every change; alignments (`:---`)
and escaped pipes survive the round trip. Cells hold one line (Markdown tables have no multi-line
cells). Images picked from outside the workspace are copied to an `images/` folder next to the page
and referenced relative to the page, so the page and its pictures move together.
**Rationale**: The page stays plain Markdown that renders anywhere and that the assistant can edit;
an unedited table writes back exactly as read. Copying pictures in keeps a workspace self-contained
and portable, which is what the AppFlowy export did too.
**Status**: Done; `test/table_image_test.dart`.

### Table column widths and multi-cell copy and paste (v0.3.6-test.1)
**Decision**: Column borders drag to set a width in logical pixels; the widths are written on one
`<!-- table-widths: 120,200 -->` line right under the table's rows, and only once a border has been
dragged (double-clicking a border removes the line and the columns are even again). A table wider
than the page scrolls sideways. Cells are selected like a spreadsheet: a mouse drag across cells,
Shift+click, Shift+Up/Down, or Ctrl+A twice. A selection copies (Ctrl+C) and cuts as tab-separated
text, Delete empties it, typing starts the first cell afresh, and Ctrl+V pastes tab-separated text
over it: one value fills every cell, a block that fits a whole number of times repeats, anything
else pastes once from the top-left, adding rows and columns past the edge. Pasting tab-separated
text into a single cell fills the cells from there; plain text still pastes at the caret.
**Rationale**: Tab-separated text is what Excel, Google Sheets and Notion put on the clipboard, so
cells move both ways. An HTML comment is hidden by other Markdown readers, so the page still reads
as a plain table; a table that was never resized writes back exactly as before.
**Status**: Done; `test/table_image_test.dart`.

### A selection across blocks belongs to the editor (v0.3.9-test.1)
**Decision**: Each block keeps its own text field, and a selection that leaves the block it started
in becomes the editor's: it is held as a start and end (block and offset), painted by the editor
behind the text of every field it covers (the fields' own selection is hidden while it is up), and
its keys are handled before the field sees them. It starts with a mouse drag into another block
(the page scrolls near its top and bottom edges), Shift+click in another block, Shift+arrow past
the first or last line, or Ctrl+A when the block is already all selected. Ctrl+C copies it as the
Markdown it would be saved as; pasting that text back (while it is the last thing copied from a
selection) brings the blocks back rather than putting the lines into one block. Delete, Backspace,
Ctrl+X, typing and Enter replace it in one undo step, the text before it and after it joining into
one block. Ctrl+B / I / E / Shift+X and the toolbar mark every selected line (or unmark them when
all of them already are), and "Turn into" changes every selected block; into a code block the lines
join into one.
**Rationale**: One field per block is what keeps very long pages fast (Task 8), so the page is not
turned into one big field. Copying Markdown keeps lists, headings and formatting when pasted into
another Markdown editor, and reads fine as plain text.
**Status**: Done; `lib/editor/block_range.dart`, `test/block_range_test.dart`.

### Folding is view state, not a file format (Task 11)
**Decision**: A heading folds the blocks up to the next heading of the same or a higher level. The
folded state lives in the editor for the open page and is never written to the file; there is no
`<details>` HTML or marker. A caret move into a folded block (arrows, undo, a drop) unfolds it, and
dragging a folded heading moves only the heading.
**Rationale**: AppFlowy and Notion toggles are a block type; in Markdown the closest thing is
`<details>`, which would turn the section into raw HTML that no other tool edits well. Folding by
heading gives the same reading experience on every page without changing what is stored. The cost is
that the fold is forgotten when the page is closed, noted in KNOWN_ISSUES.md.
**Status**: Done; `test/sections_drag_test.dart`.

### Captions live on the fence line
**Decision**: A caption is stored after the language on the fence line (` ```python Download helper `),
which CommonMark allows and GitHub ignores. A caption on a block with no language writes `text`
first so the caption can be read back. Plain script files have no caption.
**Rationale**: Keeps pages plain Markdown with nothing hidden in comments or side files.

### Links are Markdown text; Ctrl+click opens them (Bug 2)
**Decision**: A link is its Markdown (`[label](url)`) or a bare URL in the text; there is no link
object or hidden metadata. A URL pasted over selected words becomes `[words](url)`; Ctrl+K wraps or
unwraps. In the editor a plain click places the caret and Ctrl+click opens the link, so editing a
link's text never opens it; on a read-only page any click opens. Only `http`, `https` and `mailto`
are opened, through `url_launcher` as an external application.
**Rationale**: The page stays plain Markdown and saves byte for byte; Ctrl+click is what VS Code,
Word and most editors do in edit mode. Unsafe schemes are refused before reaching the OS.
**Status**: Done; `lib/editor/links.dart`, `test/links_test.dart`.

### The first frame is drawn before anything is loaded (Bug 5)
**Decision**: `runApp` runs a themed start-up screen before the settings or the workspace are read;
every loading step can fail into a visible message (defaults for unreadable settings, a
"Workspace not available" page with Try again), and each launch writes a timed `startup.log`.
**Rationale**: The Windows runner shows the window on the first frame; anything awaited before
`runApp` that fails or stalls leaves an unpainted window and no trace. The log makes the next
occurrence diagnosable without a debugger.
**Status**: Done; `test/startup_test.dart`. Packages added: `path_provider`,
`shared_preferences_platform_interface` (BSD-3).
