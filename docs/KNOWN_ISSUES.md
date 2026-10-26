# KNOWN ISSUES

## Overview
This document tracks known issues and problems identified during the audit phase of the AppFlowy replacement project. Issues are categorized by severity and impact.

## Bugs reported from test build 2 on Windows (2026-10-26)

### Bug 1 — Backspace does not work in code blocks
**Status**: Fixed 2026-10-26. Two causes: the code editor's Backspace shortcut was added to its
shortcut map in place once an empty block got text and Flutter never re-indexed it, so Backspace
was ignored in every code block that started empty; and a paragraph turned into a code block kept
its focus node, so the code editor never opened its keyboard input (typed text went nowhere, pasted
text arrived). Covered by two tests in `test/code_block_test.dart`; verified live on Linux and confirmed by
the user on Windows with test build 3.

### Bug 2 — Links cannot be pasted as links and are not clickable
**Status**: Fixed 2026-10-26. Bare URLs and `[label](url)` render as links; Ctrl+click opens
them in the system browser (http, https and mailto only); a URL pasted over selected words links
them; Ctrl+K links, and unlinks an existing link. Remaining limit: text copied from a web page
pastes as plain text, because Flutter's desktop clipboard exposes no HTML, so those hyperlinks
lose their destinations (a URL copied from the address bar works). `test/links_test.dart`.
A regression from this fix, caught in the combined pass: typing a URL letter by letter became a
Markdown link halfway through. Fixed the same day (a one-character change is never a paste) and
covered by a test.

### Bug 3 — The pages panel forgets folder expansion when hidden and reopened
**Status**: Fixed 2026-10-26. The folded folders are saved per workspace in the settings, survive
hiding the panel and restarts, follow renames and moves, and are dropped on delete. Folder paths
are the identity (a folder on disk has nothing else). Test in `test/home_page_test.dart`.

### Bug 4 — The New folder button does not create a folder
**Status**: Fixed 2026-10-26. The folder was created but the panel hid folders without a page in
them (a Task 12 rule meant for picture folders). Empty folders now show; duplicate and invalid
names are reported; "New folder here" in a folder's menu; File > New folder works with the panel
hidden. Test in `test/home_page_test.dart`.
Confirmed by the user on Windows with test build 3.

### Bug 5 — Intermittent black-and-white startup (2nd-4th launch)
**Status**: Root cause found 2026-10-26 from build 7's `native.log`; fixed in test build 8
(v0.3.5-test.1), awaiting the user's check. Build 7 had seemed to fix it but still went blank
intermittently. Earlier status: hardened 2026-10-26; root cause not established (no Windows machine here; 14 Linux
launches all fine). The screenshot shows a window Flutter never painted (white parent strip, black
child view, dark title bar from the runner). Most likely a start that failed before the first
frame: the old `main()` awaited the settings file before `runApp`, so a damaged settings file
(crash mid-write, or two instances started in quick succession) threw before anything was drawn.
Now: a themed frame is drawn before any loading, a bad settings file falls back to defaults, a
workspace that cannot be opened shows a message with Try again, the Windows window paints its
background in the theme colour, and `startup.log` (app support folder) records every step and
error of each launch. If it happens again, that file says where the launch stopped.
The user reports no freezes with test build 3 on Windows so far.

**Lead found 2026-10-26**: the user reproduced it reliably with PowerToys FancyZones. With the
window snapped into a zone (one zone, or two zones spanning top to bottom), closing and reopening
the app showed an empty window in the app's background colour; the launch after that was fine.
Test build 4 (v0.3.1-test.1) reopened the window at its last bounds and re-sized the Flutter view
after start-up moves; it did not help. Its `startup.log` showed why: on the blank launches
FancyZones resized the window 29 ms after the first frame, Dart then received every later size
(including the user dragging the window edge) and still nothing was drawn for the rest of that
run. So a resize that reaches the Flutter view while it is still starting breaks the view for
the whole run. Test build 5 (v0.3.2-test.1): the window is shown in the app's background colour
first, and Flutter starts only once the window has been still for 150 ms (at most 1 s after it
appears), so FancyZones' move lands before there is any Flutter view to break. The last-bounds
restore (`HKCU\Software\StackSpace\Window`) stays. Build 5 did not fix it either: its log shows
no resize at all at start-up (the window already had its zone's size) and the window still came
up blank on some launches, so FancyZones moving the main window is not the cause. Test build 6
(v0.3.3-test.1) adds `native.log` next to `startup.log`: the Flutter engine's own error output
plus the runner's view of the window (bounds, visibility, DWM cloaking, DPI, other StackSpace
windows or processes still running, when Flutter starts, when its first frame is presented, and
the window and view state 1 s and 4 s in). The user was also asked to try excluding
`stack_space.exe` in FancyZones to confirm whether FancyZones is involved at all.
Build 6 itself did not start on Windows: the log redirect called
`FlutterDesktopResyncOutputStreams`, which reopens stderr on a console and ends a process that has
none, leaving an empty `native.log`. Test build 7 (v0.3.4-test.1) drops that call.

**Result**: build 7 seemed fixed at first, then went blank again intermittently. Its `native.log`
showed the cause. On every blank launch, the Flutter view (the child window Flutter draws into)
was visible and filled the window when it was created, and 30 ms later it was hidden and moved to
(1107, -2) inside the window, which is the FancyZones zone's screen position (1100, -2) plus the
frame. The main window never moved. Flutter creates its view as a separate window before the runner
makes it a child; FancyZones takes it for a new StackSpace window, and its "move newly created
windows to their last known zone" applies the zone to it (asynchronously, so it lands after the
view is a child). The app kept drawing into a hidden, misplaced view. This is a race, so it was
intermittent from the start, and it explains the original white strip too.

Fix in test build 8 (`windows/runner/win32_window.cpp`): the view is subclassed, and any move,
resize or hide that would not leave it filling the client area is turned into one that does
(`native.log` says "kept the Flutter view in place" when that happens); for the first 10 s after
Flutter starts, and at the 1 s and 4 s checks, a view that is still out of place is put back and
redrawn ("Flutter view out of place … putting it back"). Builds 4 and 5's changes (reopen at last
bounds, start Flutter after the window settles) stay but were not the fix.

## Current issues in the StackSpace app (2026-10-25)

### Not tested with a real Ollama model
**Status**: Open. The cloud environment can't download models, so the assistant was tested against a
fake Ollama server that follows the documented API. Small local models may call tools less reliably.

### Very large files are read-only in the editor
**Status**: Open. Pages over 250,000 lines or 16 MB open in a virtualised read-only viewer (raised
from 100,000 / 8 MB after the Task 8 measurements). Below that, the block editor lays out only the
blocks on screen and knows every row's height up front. The assistant can still edit any size.
Pictures in image blocks are shown in a 300 px high box (scaled to fit) so the row height is known
without decoding the file.

### Windows build only run on GitHub Actions
**Status**: Partly done. `flutter build windows` and the whole test suite pass on the GitHub
windows-latest runner (test builds 1 and 2). Nobody has yet run the built app on a real Windows 11
machine with Ollama; that is the first thing to check with test build 2.

### Editor limits after Task 3 (block editor)
**Status**: Open, being worked through Phase 1.
- Code spaces (Task 6): a tab character renders narrow (Flutter draws `\t` as one small space);
  the saved text keeps the tab. Typing `{` or `(` pairs the closing bracket and Enter inside the pair
  auto-indents, like an IDE; pasted text is never changed. The language guess can be wrong for very
  short snippets (under 12 characters nothing is guessed) or for look-alike languages (C vs C++,
  JavaScript vs TypeScript); the picker overrides it and the choice is kept. Selection and find
  inside a code space do not cross into the surrounding page.
- The slash menu opens only when `/` is typed at the start of a block or after a space, so
  `http://` never opens it. It does not open on a pasted `/`.
- Raw HTML is edited as its text in a boxed field. Table cells hold one line each; a table with more
  columns than fit shows narrow cells (the text scrolls inside the cell) and there is no column
  width or alignment control yet (alignments in the file are kept).
- A folded section is remembered only while the page is open: switching pages, reloading after an
  assistant edit, or restarting the app unfolds everything. Folding is not written to the file.
- Dragging a block to a point far down a long page scrolls the list while the pointer sits near its
  bottom edge; there is no drop onto a folded section's hidden blocks (they unfold on the drop).
- Pictures and other binary files are hidden from the sidebar (Task 12), as is a folder holding
  nothing but them; an empty folder shows (Bug 4). There is no way to open a picture from the app
  yet. A text file with an unusual extension still shows and opens as text.
- Links open with Ctrl+click (Bug 2); a hover does not yet show the destination. Images show when
  the file exists next to the page, otherwise the path is shown.
- Selection cannot span blocks; Ctrl+A selects the current block.
- Arrow Up / Down move to the neighbouring block from the first / last *logical* line of a block.
  In a long paragraph that wraps, Up on the first logical line jumps to the previous block even if
  the caret is on a lower wrapped line.
- If the editor changes a field's text itself (a `- ` shortcut, Enter) while characters are still
  on their way from the platform, the late characters are mapped onto the new text. On a very slow
  machine one character can still be lost in that instant; it never corrupts other blocks.

### AppFlowy import limits
**Status**: Open. File > Import reads AppFlowy's workspace export (`relation_map.json` +
`collab_jsons/`). The export has no image files, so images become links to missing files (the
import lists them). Grid, board and calendar views come in as empty pages. Tested against the
user's 45-page export: all pages and all text came through.

## Issues found in AppFlowy during the audit

## Critical Issues

### 1. Large Document Performance
**Issue**: AppFlowy freezes or crashes when opening, copying, pasting or editing documents containing scripts exceeding approximately 5,000 lines.
**Impact**: Core functionality affected - prevents use of large scripts and documents.
**Status**: Confirmed - repository analysis shows full document loading without virtualization.

### 2. Clipboard Handling Problems  
**Issue**: Copy/paste operations with large content cause freezing or crashes.
**Impact**: Basic editing functionality severely impacted.
**Status**: Likely root cause identified in FFI integration layer.

## High Priority Issues

### 1. Memory Management
**Issue**: Unbounded memory growth when handling large documents.
**Impact**: Can lead to application crashes and system instability.
**Status**: Confirmed - repository analysis shows entire document loaded into memory.

### 2. UI Responsiveness  
**Issue**: UI thread blocking during document processing operations.
**Impact**: Poor user experience, makes application feel sluggish.
**Status**: Confirmed - FFI calls can cause blocking behavior.

## Medium Priority Issues

### 1. Document Rendering
**Issue**: Inefficient rendering of large documents or complex formatting.
**Impact**: Performance degradation with larger content.
**Status**: Identified - main editor loads entire document structures without virtualization.

### 2. Storage System Efficiency
**Issue**: Potential inefficiencies in document storage and retrieval mechanisms.
**Impact**: May affect overall application performance.
**Status**: Identified through FFI integration analysis.

## Low Priority Issues

### 1. Feature Completeness
**Issue**: Some features may not be implemented or may have limited functionality.
**Impact**: May require additional work to match AppFlowy's full feature set.
**Status**: Not specifically identified in current audit - will be addressed during implementation.

### 2. Cross-Platform Compatibility
**Issue**: Windows 11 specific optimizations may be needed.
**Impact**: Ensures proper operation on target platform.
**Status**: Will be addressed in architecture planning.

## Identified Root Causes from Repository Analysis

### 1. Document Loading Architecture
**Root Cause**: The main editor (`editor_page.dart`) loads entire document structures into memory without virtualization or lazy loading.
- Entire document tree is loaded at initialization time
- No chunking or streaming of content for large documents
- Memory usage grows linearly with document size

### 2. FFI Integration Bottlenecks  
**Root Cause**: Rust integration via FFI (`appflowy_backend`) may cause blocking behavior:
- Direct calls to native libraries can block UI thread
- Large data serialization/deserialization in FFI layer
- No asynchronous processing for heavy operations

### 3. Clipboard Operations
**Root Cause**: Full document serialization during clipboard operations:
- Copy operations serialize entire document structure
- Paste operations deserialize entire content
- No chunked processing for large clipboard contents

## Data Integrity Considerations

### 1. Recovery Mechanisms
**Issue**: Need to understand existing recovery mechanisms.
**Impact**: Critical for data safety.
**Status**: Identified through architecture review.

### 2. Backup and Migration
**Issue**: How does AppFlowy handle data backup and migration?
**Impact**: Important for user experience.
**Status**: Identified through storage system analysis.

## Next Steps

1. Complete repository audit of original AppFlowy
2. Document specific technical bottlenecks found
3. Validate which issues are confirmed problems vs. potential areas for optimization
4. Prioritize fixes based on severity and impact
5. Update this document with findings from the audit

## Issue Tracking Process

### Documentation Standards
- Each issue must have clear description
- Include impact assessment
- Document current status
- Note any reproduction steps if known

### Update Frequency
- Update after each significant finding during audit
- Review and prioritize issues regularly
- Remove resolved issues from this document

### Resolution Tracking
- Track which issues are addressed in implementation
- Document solutions applied to each issue
- Verify fixes through testing

## Windows title bar colour is untested
The runner colours the title bar through DWM (`windows/runner/flutter_window.cpp`, channel
`stackspace/window`). It was written without a Windows machine, so check it on the first Windows
build. Caption colours need Windows 11; Windows 10 only gets the dark/light flag.

