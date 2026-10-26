# TEST PLAN

## Overview
This document outlines the testing approach for StackSpace, a Windows 11 notes app inspired by Notion and AppFlowy, built after other tools froze on scripts over 5,000 lines.

## Test Categories

### Performance Testing
Focus on large document handling and responsiveness:

#### Document Loading Tests
- Opening documents with 100 lines
- Opening documents with 1,000 lines  
- Opening documents with 5,000 lines
- Opening documents with 10,000 lines
- Opening documents with 25,000 lines
- Opening documents with 50,000 lines (where practical)

#### Editing Tests
- Typing and keyboard interaction response time
- Scrolling and selection performance
- Line navigation and editing

#### Clipboard Tests
- Copying 100 lines
- Copying 1,000 lines
- Copying 5,000 lines
- Copying 10,000 lines
- Pasting into empty document
- Pasting into existing content
- Pasting with formatting preserved

### Memory and Resource Testing
- Memory usage while opening large documents
- Memory growth during editing sessions
- Resource cleanup when documents close
- Long-running session testing (30+ minutes)

### Data Integrity Tests
- Document persistence after save/load cycles
- Recovery after unexpected shutdowns
- Import validation from original AppFlowy format
- Backup and restoration capabilities

### Windows 11 Specific Testing
- Installation and launch process
- Window resizing and display scaling
- Keyboard input handling
- Clipboard integration with Windows
- File path handling for Windows systems
- Unicode and special character support

## Performance Benchmarks

### Target Response Times
- Normal typing and keyboard interaction: < 100ms response time
- Scrolling and selection: < 100ms response time  
- Opening 5,000 lines: within 2 seconds
- Opening 10,000 lines: within 4 seconds
- Pasting 5,000 lines: within 3 seconds
- Pasting 10,000 lines: within 5 seconds

### Memory Usage Targets
- Efficient memory management for large documents
- No unbounded memory growth during editing
- Proper resource cleanup when documents close

## Test Fixtures

### Document Size Categories
- Small: 100 lines
- Medium: 1,000 lines  
- Large: 5,000 lines
- XLarge: 10,000 lines
- XXLarge: 25,000 lines
- XXXLarge: 50,000 lines (where practical)

### Content Types
- Plain text with varied line lengths
- Text with mixed formatting
- Code blocks with syntax highlighting
- Documents with Unicode and special characters
- Documents with tabs, blank lines, comments

## Test Automation Approach

### Unit Tests
- Core document parsing functions
- Storage and persistence mechanisms  
- Clipboard handling operations
- Memory management components

### Integration Tests
- End-to-end document workflows
- Editor functionality with large content
- Storage system integration
- Clipboard integration with Windows

### Performance Tests
- Benchmarking of document loading times
- Memory usage monitoring during editing
- Responsiveness testing under load
- Clipboard operation performance

### Regression Tests
- Core functionality validation after each change
- Performance benchmarks to ensure no regressions
- Compatibility testing with various document types

## Editor tests in place (Phase 1, Task 3)

| File | What it checks |
| --- | --- |
| `test/blocks_test.dart` | Markdown → blocks → Markdown round trip: headings, inline marks kept as typed, lists (markers, nesting, numbers, checkboxes), blank-line counts kept exactly, quotes, callouts, dividers, code fences (language, tabs, CR, Unicode, Markdown characters inside, longer fences, `~~~`, unterminated), images, tables, HTML, block start lines. With `STACKSPACE_PAGES=<folder>` it round-trips every `.md` page in that folder (45/45 imported pages identical). |
| `test/page_document_test.dart` | split / merge / convert keep the Markdown consistent; typing coalesces into one undo step; non-Markdown files save byte for byte; last block removal; indent, check, move. |
| `test/block_editor_test.dart` | Typing keeps every character and autosaves; Enter splits, `- ` / `## ` / ``` shortcuts convert, Tab indents, Enter on an empty item outdents then ends the list, Shift+Enter keeps a soft break; Backspace at the start demotes then merges, Ctrl+Z / Ctrl+Y; a `.py` file is one code space where Enter is a newline; a late platform update based on the old text is moved onto the new; a paragraph turning into a heading / list / quote / numbered item keeps the same text field. |
| `test/home_page_test.dart`, `test/accessibility_test.dart` | Unchanged and still green with the block editor (dock, AI edit + reload, contrast, labels, 24 px targets, 150 % text). |

| `test/slash_menu_test.dart` (Task 5) | Filtering (category order, label prefix beats alias prefix beats contains, no match); in the editor: `/` opens, typing filters, arrows wrap, Enter applies and removes `/query`, Escape keeps the text, mid-text query turns the block into a quote, no menu inside a word / in a code block / in a plain file, deleting the slash closes it, empty state and Enter on no match, click inserts a divider and focuses a new paragraph, an empty paragraph is replaced by an inserted table, image asks for a path, the panel opens below the slash and flips above it near the bottom edge, losing focus closes it. |

| `test/code_languages_test.dart` (Task 6) | Fence names and aliases (`c#`, `js`, `sh`, `xml`), extensions, picker filtering, and detection of C# (Unity), PowerShell, Python, JSON, HTML, SQL, Bash, TypeScript, JavaScript, CSS, YAML, Rust, Go; nothing guessed for short or plain prose. |
| `test/code_block_test.dart` (Task 6) | A fenced block shows its language, keeps text exact (tabs, Unicode, Markdown characters) and saves the fence; typed C# is guessed, written to the fence and shown as "auto", picking PowerShell stops guessing, "Auto-detect" resumes it; a language from the file is never re-guessed; the copy button puts the exact code on the clipboard and shows "Copied"; the wrap toggle flips the editor and grows the block; a caption is saved on the fence line and read back; undo / redo across a code edit; Backspace in an empty block turns it into a paragraph and Ctrl+Enter adds a paragraph below; `/`, `- ` and `# ` do nothing inside code; a `.py` file is one highlighted code space; a 5,000-line paste keeps every line and the block stays within its maximum height. |

| `test/block_metrics_test.dart` (Task 8) | Pumps a page with every block kind (headings 1-3, short / long / soft-break paragraphs with inline marks, nested bullets, numbered, to-dos, quote, divider, missing images with and without alt text, table, HTML, code with caption, a 300-character code line, an empty paragraph) at 700 px and 1100 px and text scale 1.0 and 1.5, and checks every computed row height equals the rendered one within half a pixel. |
| `test/performance_test.dart` (Task 8) | Model: parse, write, load, one edit, toMarkdown and undo for 5k / 10k / 50k / 100k lines as one code block, one-line paragraphs and a mix; each under 5 s. Editor: open, first frame, one keystroke, jump to the end and back, autosave for 5k / 10k / 50k lines; first frame under 5 s and a keystroke under 2 s in the test VM. Rows are printed as a table and appended to `stackspace_perf_rows.txt` in the system temp folder. |
| `test/sections_drag_test.dart` (Task 11) | The chevron folds a heading's section (hidden rows are not built and take no space, the next same-level heading stays, the file is unchanged); Arrow Down from a folded heading unfolds it; Collapse section in the block menu; folding with the caret inside moves the caret to the heading; dragging a handle onto the lower / upper half of a row puts the block below / above it and the file follows; a drop where the block was changes nothing. |
| `test/table_image_test.dart` (Task 10) | `TableData` round trip (escaped pipes, alignments, no separator, ragged rows), row and column insert / remove rules; in the editor: cells show the table and typing writes padded Markdown to the file; Tab / Shift+Tab / Enter / arrows between cells, Tab on the last cell adds a row, arrows leave and enter at the edges; header buttons add and remove rows and columns, one undo step each, Delete table; `/table` from the slash menu puts the caret in the first cell; the image description field saves as alt text and Enter below it adds a paragraph; `importImage` copies, numbers, keeps links and relative paths. Column widths: the widths comment line round trip, widths follow added and removed columns, dragging a border sets one width that is saved and read back, double-click makes columns even. Cells: tab-separated copy and parse (quotes, CRLF), spreadsheet paste (fill, repeat, grow); in the editor a drag selects cells, Ctrl+C / Delete / Ctrl+V over a selection (one undo step each), Shift+arrows grow it, Shift+click selects from the caret, typing replaces the first cell, pasting rows into one cell adds rows and plain text still pastes at the caret. |
| `test/block_menu_test.dart` (Task 9) | The toolbar appears when words are selected, its Bold / Italic / Inline code buttons wrap them and the saved file matches, and it goes when the caret collapses; Turn into (Heading 2, Bulleted) changes the kind and keeps the text; no toolbar in a plain file, a read-only page or on a collapsed caret; the handle is invisible until hover or focus, and Duplicate, Move up, Move down and Delete from its menu change the document and the saved file; Turn into from the menu makes a code block of a list item and a paragraph of a code block. `block_editor_test.dart`: a selection that drags in spaces gets its markers around the words. |
| Task 7 additions | `block_editor_test.dart`: Ctrl+B / Ctrl+I / Ctrl+E / Ctrl+Shift+X wrap the selection in `**` / `_` / `` ` `` / `~~`, press again (markers inside or just outside the selection) removes them, no selection inserts the pair with the caret between, Ctrl+K makes `[text](url)` with `url` selected, saved file matches. `code_block_test.dart`: Up on the first line / Down on the last line / Right at the end of a code space move to the neighbouring block while arrows inside move the caret; the context menu's Copy all, Cut and Paste put and take the exact text (tab, Unicode) through the clipboard and the file matches. |

| Bug-fix phase, Bug 1 | `code_block_test.dart`: a code block that started empty handles Backspace after a key event has been seen (end, middle, multi-line selection), Delete / Home / End, emptying then converting to a paragraph; a code space made from a paragraph attaches the delta-model input client and takes text sent through the platform channel, and the paragraph takes input again after converting back. Live (Linux release build, `xdotool`): see PROJECT_STATUS.md Bug-fix log. |

| Bug-fix phase, Bug 2 | `links_test.dart`: link finding and caret lookup, pasted-URL detection, safe schemes, launcher called only with safe URIs, renderer styles; in the editor: URL pasted over words → `[words](url)`, URL alone stays bare, multi-line and plain pastes untouched, file exact; Ctrl+click opens the exact destination (Markdown and bare), plain click only edits, nothing opens on plain text, read-only page opens on a click; Ctrl+K link / link a selected URL / unlink, save and reopen. Typing a URL letter by letter stays as typed (regression test, helper and editor). Live: Ctrl+click launched the registered system handler with the exact URLs; in-app copy and paste over a word produced the link; a URL typed letter by letter stayed text. |

| Bug-fix phase, Bug 3 | `home_page_test.dart`: fold two folders, hide and show the panel, nested fold / unfold, rename and move folded folders, delete one, restart the app on the same settings; the saved list is checked at each step. Live: fold, hide / show, restart. |

| Bug-fix phase, Bug 4 | `home_page_test.dart`: New folder shows at once and exists on disk; Cancel and a blank name create nothing; nested via "New folder here" and via a typed path; duplicate name reported; fold / rename / restart / delete. Live: button → name → folder listed, on disk, listed after restart. |

| Bug-fix phase, Bug 5 | `startup_test.dart`: settings fallback when the store throws; the start-up screen's colour and message; a workspace path that is a file → "Workspace not available" with Try again, then opens after the folder is fixed; log trimming. Launch runs: 10 consecutive Linux release launches (3 after cache drops) + 3 dark-theme + 1 damaged-settings launch, pixels sampled and the editor area's colour count checked each time; `startup.log` inspected. Not run on Windows. |
| Bug-fix phase, combined | One live session on the Linux release build covering all five areas in turn (code block keys, typed and pasted links, Ctrl+click, New folder and a duplicate name, fold state across hide / show and a restart, start-up log of the restart); results in PROJECT_STATUS.md "Combined regression pass". |

Manual run for Task 7 (release build under Xvfb): Ctrl+B on a selected word wrote `**bold**`; Up from
the first code line moved to the paragraph above and Down from the last line to the paragraph below;
text typed after each landed in the right block and the saved file was correct.

Manual code space run (release build under Xvfb): typed Unity C# into an empty block → guessed
`csharp`, highlighted, fence saved as ` ```csharp `; pasted a Python file with tabs and `✓` through
the X clipboard → guessed `python`, file byte-identical to the source; language picker search
"type" → TypeScript; context menu. Screenshots `11-code-spaces-dark.png`, `12-language-picker-dark.png`,
`13-code-menu-dark.png`.

Manual slash run (release build under Xvfb): Enter, `/hea`, Down, Enter, heading text, `/tod` to-do items, `/div`, `/code` and code text produced the expected Markdown. Screenshots `9-slash-menu-dark.png`, `10-slash-result-dark.png`.

Manual run (Linux release build under Xvfb, `xdotool` at 25 ms per key): typed text, a bullet with
`- `, Tab, nested item, Enter ×3 to end the list, `## ` heading, ``` code block with two lines; three
runs produced the same correct file. Screenshot: `docs/screenshots/8-block-editor-dark.png`.

## Test Execution Process

### Pre-Test Setup
1. Create test fixtures with different document sizes
2. Configure test environment for Windows 11
3. Set up performance monitoring tools
4. Prepare backup of original AppFlowy data

### Test Execution
1. Run performance benchmarks for each document size
2. Execute clipboard operation tests
3. Monitor memory usage and response times
4. Validate data integrity after operations

### Post-Test Analysis
1. Record actual results vs. targets
2. Identify performance bottlenecks
3. Document findings in KNOWN_ISSUES.md
4. Update test plans based on discoveries

## Test Tools and Frameworks

### Performance Monitoring
- Memory profiling tools
- CPU usage monitoring
- Response time measurement tools
- Custom logging for performance metrics

### Testing Frameworks
- Unit testing framework (likely Rust or C++ based)
- Integration testing infrastructure
- Automated benchmarking system
- Regression test suite

## Test Coverage Requirements

### Must Test
- Large document opening and editing
- Clipboard operations with large content
- Memory usage patterns
- Windows 11 specific compatibility
- Data integrity during all operations

### Should Test  
- Undo/redo functionality with large documents
- Search and find operations on large content
- Export/import workflows
- Backup and recovery mechanisms

### Could Test (if time permits)
- Collaboration features
- AI integration capabilities
- Extension support
- Customization options

## Test Reporting

### Test Results Format
Each test result should include:
- Document size and type
- Hardware and software environment
- Actual performance metrics
- Memory usage data
- Any errors or issues encountered
- Comparison to target benchmarks

### Issue Tracking
- Record all performance regressions
- Document identified bottlenecks
- Track fixes and improvements
- Update KNOWN_ISSUES.md with findings

## Test Schedule

### Phase 1: Initial Audit (Completed)
- Repository analysis
- Feature identification
- Architecture planning

### Phase 2: Performance Testing Setup
- Set up test environments
- Create test fixtures
- Configure monitoring tools

### Phase 3: Core Functionality Testing  
- Document loading tests
- Basic editing tests
- Clipboard operations

### Phase 4: Performance Optimization
- Identify bottlenecks
- Implement optimizations
- Re-test performance targets

### Phase 5: Regression and Final Testing
- Validate all functionality
- Ensure no regressions
- Final performance validation