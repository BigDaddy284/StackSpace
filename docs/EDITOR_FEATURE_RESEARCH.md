# Editor feature research: AppFlowy, Notion and StackSpace

_Written 2026-10-25 for Improvement Phase 1, Task 1. Sources are listed at the end; every row says whether it was verified in source code or documentation, or is an assumption._

## 1. What was investigated

| Source | How it was examined |
| --- | --- |
| AppFlowy app, `AppFlowy-IO/AppFlowy` (commit 5cf3a36, Jun 2026) | Cloned. Read `frontend/appflowy_flutter/lib/plugins/document/presentation/editor_plugins/` (slash menu items, code block UI, block option menu, toolbar, export/import types). |
| AppFlowy Editor, `AppFlowy-IO/appflowy-editor` (v6.1.0 in repo, 6.2.0 on pub.dev) | Cloned. Read the slash command, selection menu, character/command shortcuts, block components, Markdown encoder/decoder and page rendering. |
| AppFlowy Editor Plugins, `AppFlowy-IO/AppFlowy-plugins` (code block plugin) | Cloned. Read the code block component, its shortcuts, language list and highlighting path. |
| AppFlowy docs (docs.appflowy.io) and "What's new" (appflowy.com/what-is-new) | Fetched. The docs are mostly contributor docs; the release notes gave the feature timeline. |
| Notion help: writing and editing basics, slash commands, code blocks, keyboard shortcuts, databases | Fetched. Notion is closed source, so Notion rows are documentation-only. |
| StackSpace (this repo, commit ef0f406) | Read `lib/editor/page_editor_controller.dart`, `lib/ui/editor_pane.dart`, `lib/import/appflowy_import.dart`, `lib/ai/*`. |
| Flutter packages for code editing and highlighting | pub.dev pages for `re_editor`, `re_highlight`, `flutter_code_editor`, `highlight`, `flutter_highlight`, `code_forge`, `markdown`. |

Legend for the "StackSpace" column and the classification:

- **Done**: already implemented and working.
- **Partial**: present but incomplete.
- **Missing, worth it**: missing and worth implementing in this phase or the next.
- **Missing, low**: missing but low priority.
- **N/A**: not applicable to the current architecture (local Markdown files, single user, no server).

## 2. How each product is built (verified)

**AppFlowy.** The document is a tree of `Node`s; each node has a `type`, `attributes` and a `delta` (Quill-style rich text). Every node type is a `BlockComponentBuilder` that returns a widget. The page renders its top-level blocks with `ScrollablePositionedList.builder` (`page_block_component.dart:98`), so blocks off screen are not built. A block's text is one `AppFlowyRichText`, so a single huge block is still laid out in full. Edits go through `Transaction`s with an undo manager. The `/` key is a `CharacterShortcutEvent` (`slash_command.dart`); the menu is an `OverlayEntry` (`selection_menu_service.dart`) that filters items by `name` and `keywords` with `contains` (`selection_menu_widget.dart:335`), handles Enter / Escape / Backspace / arrows / Tab (`:526-615`), flips above the caret when it would run off the bottom and to the left when it would run off the right (`:215-258`). Markdown in and out is built in (`document_markdown.dart`; parsers for heading, list, todo, quote, code, divider, image, table). Code blocks are a plugin (`appflowy_editor_plugins`): the whole block is re-parsed with `highlight.parse` on every build (`code_block_block_component.dart:441`), rendered as one rich text, with a language picker of 46 names (`:16-64`) plus `auto`, a copy button, Tab inserts two spaces, Ctrl+A selects the block, and paste keeps text. There is no line-wrap toggle and no caption in the code block plugin (verified by reading the plugin; AppFlowy's own UI adds a language search screen and a copy button). This re-parse-everything design is the likely cause of the freezes the user saw with 5,000-line scripts (assumption; consistent with the code, not benchmarked here).

**Notion.** Documentation only. Blocks with a `⋮⋮` handle (turn into, colour, copy link, duplicate, move to, delete, comment). `/` opens a menu listing blocks with recently used at the top; `Esc` closes it; typing filters; aliases like `/h1`, `/bullet`, `/num`, `/todo`, `/toggle`, `/div`, `/quote`, `/code`, `/page`, `/link`, `/mention`, `/date`, `/equation`, `/emoji`, `/image`, `/file`, `/embed`, `/toc`, `/button`, and action commands `/delete`, `/duplicate`, `/moveto`, `/turn…`, `/color` ( `/red` ). Code blocks: `/code` or Ctrl+Shift+8, a language name at the top left that opens a searchable list, a Copy button, a Wrap code toggle, a Caption, and a `•••` menu. Markdown shortcuts documented: `**b**`, `*i*`, `` `code` ``, `~s~`, `- `/`* `/`+ `, `[] `, `1. `, `# `/`## `/`### `, `> ` (toggle list in Notion), `" ` (quote), `---`.

**StackSpace today.** A page is a Markdown file. The editor is one Flutter `TextField` over the whole file (`editor_pane.dart`), monospaced, no formatting, no blocks, no syntax highlighting. Pages over 20,000 lines or 2 MB open in a read-only virtualised line viewer. Autosave after 600 ms. Ctrl+N / Ctrl+S / Ctrl+J / F2 / Delete. The assistant edits pages by line and text replacement, which depends on the file staying Markdown. The AppFlowy importer turns the export into Markdown with headings, lists, code fences with language, tables, callouts (as quotes), bold/code/links and page links.

## 3. A. Document editing and presentation

| Feature | AppFlowy | Notion | StackSpace | Classification |
| --- | --- | --- | --- | --- |
| Paragraphs, rich text | Yes: paragraph block with delta (bold, italic, underline, strikethrough, code, link, colours). Verified. | Yes. Verified (docs). | Plain text only. | Missing, worth it |
| Headings | H1–H3 blocks (`heading_items.dart`, `#`/`##`/`###` shortcuts). Toggle headings since v0.6 (unverified version). | H1–H3, toggle headings. Verified. | Typed as `# ` Markdown, no styling. | Partial |
| Bold / italic / underline / strike / inline code | All five, via toolbar, Ctrl+B/I/U/Shift+S/E and Markdown characters (`format_*.dart`). Verified. | All five, same shortcuts. Verified. | None (Markdown characters stay as typed). | Missing, worth it |
| Text and background colour | Toolbar colour picker; `/` colour options since v0.11.7. Verified. | Drag-handle Color, `/red`. Verified. | None. | Missing, low |
| Bulleted / numbered / nested lists | Blocks with Tab/Shift+Tab nesting. Verified. | Same. Verified. | Markdown text. | Partial |
| Checklists | `todo_list` block, `[] ` shortcut. Verified. | To-do, `[] `. Verified. | `- [ ]` as text (importer writes it). | Partial |
| Quotes, callouts | `quote` block (`> `?) and `callout` block with icon and colour. Verified. | Quote (`" `), callout with emoji and colour. Verified. | Importer writes `> ` and `> 🎮 text`; shown as text. | Partial |
| Dividers, page breaks | `divider` (`---`). No page break (unverified). | Divider (`---`). Page break for PDF export (unverified). | `---` text. | Partial |
| Hyperlinks, bookmarks, mentions | Links, link preview block, page mention (`@`), date mention. Verified. | Links, web bookmark, `@` mentions, link to page. Verified. | Markdown `[text](url)` as text; importer writes page links. | Partial |
| Images, captions, files, media | Image, photo gallery, file, video blocks; images stored in app data (export omits them, verified in the user's zip). | Image, file, PDF, video, audio, embed. Verified. | `![alt](path)` as text. Nothing renders. | Missing, worth it (images), low (video) |
| Tables | `simple_table` with header row/column, column widths, row colours, align. Verified in export data. | Simple tables and databases. Verified. | Markdown pipe tables as text. | Missing, worth it |
| Toggles / collapsible | `toggle_list` and toggle headings. Verified. | Toggle list (`> `), toggle headings. Verified. | None. | Missing, worth it (later) |
| Columns, block rearrangement | 2–4 columns (`simple_columns`), drag to reorder, multi-block drag since v0.13.0. Verified. | Drag blocks side by side for columns. Verified. | None. | Missing, low (columns), worth it (reorder, later) |
| Equations | `math_equation` block and inline equation (KaTeX). Verified. | `/equation`, `/math`, inline `$$`. Verified. | `$$` fences as text. | Missing, low |
| Page width, typography, spacing | Page style: font, line height, width, cover, icon. Verified in `page_style/`. | Font (default/serif/mono), small text, full width. Verified. | None. | Missing, low |
| Floating toolbar / context menus | Desktop floating toolbar on selection (`desktop_toolbar/`); block `⋮` option menu (turn into, colour, align, depth, duplicate, delete, move up/down, copy link, page width). Verified. | Formatting menu on highlight; `⋮⋮` menu. Verified. | None. | Missing, worth it |
| Keyboard and Markdown shortcuts | Markdown character shortcuts listed in §2; command shortcuts for bold, copy/paste, find/replace, undo/redo, select all. Verified. | Full list in §2. Verified. | Ctrl+N/S/J, F2, Delete, Enter in chat. | Partial |
| Drag-and-drop block movement, block actions | `drag_to_reorder/`, `block_action_*`. Verified. | Drag handle. Verified. | None. | Missing, worth it (later) |

## 4. B. Code presentation and editing

| Feature | AppFlowy | Notion | StackSpace | Classification |
| --- | --- | --- | --- | --- |
| Inline code vs code block | Both: `code` attribute (`` ` `` shortcut) and `code` block (`/code`, ``` ``` ```). Verified. | Both: Ctrl+E and `/code`. Verified. | Neither; the whole page is monospaced plain text. | Missing, worth it |
| Syntax highlighting | `highlight` package (highlight.js port, 2021), whole block re-parsed on each build. Verified. | Yes. Verified (docs). | None. | Missing, worth it |
| Language selection and search | 46 languages + auto; AppFlowy app adds a searchable picker (`code_block_language_selector.dart`). Verified. | Searchable list by typing. Verified. | Language kept in the Markdown fence only. | Missing, worth it |
| Copy button | Yes, copies plain text plus in-app JSON. Verified. | Yes. Verified. | Chat code blocks only. | Missing, worth it |
| Line wrapping control | Not in the plugin (verified; no wrap toggle in `code_block_block_component.dart`). | Wrap code toggle. Verified. | TextField always wraps. | Missing, worth it |
| Caption / description | Not in the plugin (verified). | Caption. Verified. | None. | Missing, low |
| Code block context menu | Block option menu (turn into disabled for code? unverified), copy, delete. | `•••`: wrap, caption, colour, duplicate, delete. Verified. | None. | Missing, worth it |
| Indentation and whitespace | Tab inserts two spaces; paste keeps text (`code_block_shortcuts.dart`). Verified. | Preserved. Assumption. | Preserved (plain TextField). | Done |
| Multiline editing and paste | Yes, inside one rich text run. Verified. | Yes. | Yes (plain). | Done |
| Very long code blocks | One `AppFlowyRichText` for the whole block, re-highlighted on every build: slow for thousands of lines. Verified in code; the user saw freezes. | Unknown; Notion pages are capped at a few thousand blocks (unverified). | Up to 20,000 lines editable but the whole TextField re-lays out; above that read-only. | Partial |
| Editing without affecting neighbours | Yes (separate node). | Yes. | No: one text field. | Missing, worth it |
| Markdown import/export of code blocks | `code_block_node_parser.dart` writes ``` ```lang ```. Verified. | Markdown export writes fences. Verified (docs, unverified detail). | Importer writes fences with language. Storage is Markdown. | Done |
| Large script without re-rendering the document | Blocks are virtualised, but the block itself is not. Verified. | Unknown. | No. | Missing, worth it |

**Which capabilities should be document blocks and which a dedicated component.** Paragraphs, headings, lists, quotes, callouts, dividers, tables and images belong to the document editor as blocks. The code block should be a block *container* (language, wrap, copy, caption, menu) whose body is a dedicated code-editing widget that lays out only visible lines and highlights incrementally. That is the one place where StackSpace must do better than AppFlowy, and it is also where AppFlowy's design is weakest.

## 5. C. Slash commands and insertion menus

| Behaviour | AppFlowy (verified in `slash_command.dart`, `selection_menu_service.dart`, `selection_menu_widget.dart`) | Notion (docs) | StackSpace |
| --- | --- | --- | --- |
| Opens on | Typing `/` in paragraph, heading, todo, bulleted, numbered, quote, callout, toggle blocks (whitelist `supportSlashMenuNodeTypes`). A non-collapsed selection is deleted first. | Typing `/` anywhere in text. | Nothing happens. |
| The `/` itself | Inserted into the text (`shouldInsertSlash`), removed on selection (`deleteSlashByDefault`); typed query also removed when the item says so. | Removed on selection. | — |
| Position | Overlay at the caret's bottom-right + (0,10); flips above the caret if it would overflow the editor's bottom; aligns right edge if it would overflow the right. | Near the caret; adjusts at edges (assumption). | — |
| Search | `name` and `keywords` matched with `contains`, case-insensitive; typing continues into the document and the query is read back from it; closes when the query has no matches for a few characters (unverified count). | Fuzzy by name and aliases; recently used on top. | — |
| Keyboard | Up/Down/Left/Right move, Tab moves, Enter selects, Escape closes, Backspace edits the query (closes when empty). | Up/Down, Enter, Esc. | — |
| Mouse | Hover highlights, click selects. | Same. | — |
| Categories | Flat list in the editor package; the app's redesigned menu (v0.11.4) groups items (basic, media, database, advanced; unverified names). Items: text, H1–H3, toggle list, toggle headings, bulleted, numbered, todo, quote, callout, divider, code block, simple table, 2/3/4 columns, image, photo gallery, file, link to page, sub page, grid, kanban, calendar, linked grid/kanban/calendar, date or reminder, emoji, math equation, outline, AI writer, continue writing. | Basic, inline, media, embeds, advanced, database, colour, actions ("turn into", "delete", "duplicate", "move to"). | — |
| Empty block vs mid-text | Same path; the block is replaced when its delta is empty (`replace: (_, node) => node.delta?.isEmpty`), otherwise the new block is inserted after. | Inserts a new block below when the line has text (assumption). | — |
| Plain slashes in URLs and paths | Not special-cased: the menu opens on every `/` in a text block, and typing on with no match closes it. Code blocks are excluded by the whitelist. | Menu opens; typing on dismisses it. | — |
| Accessibility | Keyboard complete; no screen-reader announcements found (unverified). | Unknown. | — |

## 6. D. Databases and workspace productivity

| Feature | AppFlowy | Notion | StackSpace | Classification |
| --- | --- | --- | --- | --- |
| Tables / structured data | Simple tables in documents; databases with grid, board, calendar, gallery, list, chart, feed, timeline views (release notes Jan–Sep 2026). Verified. | Databases with table, board, calendar, gallery, list, timeline. Verified. | Markdown tables as text. The user's export has 0 database views. | Simple table: worth it. Databases: low |
| Properties, sort, filter, group | Yes, including formulas, rollups, relations (2026 releases). Verified. | Yes. Verified. | None. | Missing, low (no database data to migrate) |
| Templates | Template gallery. Verified (docs). | Templates and buttons. Verified. | None. | Missing, low |
| Page hierarchy, cross-links | Tree in sidebar, page mentions, link to page. Verified. | Same. | Folders and files in the sidebar; page links written by the importer but not clickable. | Partial |
| Search | Workspace search (Ctrl+P). Verified in code (`search/`). | Quick find. | None (the assistant can search). | Missing, worth it (later) |
| Page history and recovery | Version history (v0.12.0), trash. Verified. | Page history, trash. Verified. | `.trash` folder for deletes; no page history. | Partial |
| Import / export | Import Markdown/text, CSV, Notion zip, AppFlowy database; export Markdown, HTML, JSON, text, PDF. Verified in code and docs. | Import Markdown/HTML/CSV/Word/etc.; export Markdown, HTML, PDF. Verified. | Import: AppFlowy workspace export. Pages are already Markdown files, so "export" is the file. | Done for the user's case |
| Reusable content | Templates, synced blocks (Notion only, unverified). | Synced blocks, templates. | None. | Missing, low |

## 7. E. Classification summary

**Done:** Markdown storage and import, whitespace preservation, large read-only viewer, autosave, assistant editing, trash.

**Partial:** headings/lists/quotes/tables/links as unstyled Markdown; keyboard shortcuts; page links; large editing (editable to 20k lines but one text field).

**Missing, worth implementing (this phase, in order):**
1. Block editor with rich text (bold, italic, underline, strikethrough, inline code, links), headings, lists, checklists, quotes, callouts, dividers.
2. Slash menu with the catalogue in §5.
3. Dedicated code block: distinct background, syntax highlighting, searchable language picker, copy, wrap toggle, caption, menu, virtualised body for thousands of lines.
4. Markdown shortcuts (`# `, `- `, `1. `, `[] `, `> `, ``` ``` ```, `**`, `` ` ``).
5. Floating formatting toolbar and block option menu (turn into, duplicate, delete, move up/down).
6. Simple tables with editing.
7. Images rendered from the workspace folder.
8. Toggle blocks, block drag-and-drop, columns.

**Missing, low priority:** colours, equations, page style settings, databases, templates, video/embeds, page history.

**N/A:** collaboration, comments, cloud sync, AI writer (StackSpace has its own assistant), publish.

## 8. Candidate building blocks (verified on pub.dev, Oct 2026)

| Package | What it gives | Licence | State | Notes |
| --- | --- | --- | --- | --- |
| `appflowy_editor` 6.2.0 | The AppFlowy block editor: nodes, rich text, selection, toolbar, slash menu, Markdown shortcuts, Markdown/HTML/Quill import and export, undo, block-level virtualisation. | **AGPL-3.0 or MPL-2.0 (dual)** | Dec 2025 on pub.dev, Aug 2026 on GitHub; 518 likes; appflowy.io verified publisher. | Under MPL-2.0 it can be used from an MIT app; only modified MPL files must be shared. It is a library dependency, not copied code. |
| `appflowy_editor_plugins` 0.0.6 | Code block plugin for the above (highlighting via `highlight`, language picker, copy). | AGPL-3.0 or MPL-2.0 | May 2024; depends on old `appflowy_editor` ^2.3; would need vendoring. | Its code block is the slow design described above, so StackSpace would write its own anyway. |
| `re_editor` 0.10.0 | Code editor widget: lazy line layout "optimised for large texts", highlighting via `re_highlight` (~100 languages), line numbers, wrap on/off, find/replace logic, folding, read-only, undo/redo, desktop shortcuts. | MIT | Jul 2026; 138 likes; reqable.com verified; 34 open issues. | Best fit for the code block body. |
| `re_highlight` 0.0.3 | highlight.js 11.9 port producing `TextSpan`s. | MIT | Feb 2024. | Used by `re_editor` and `code_forge`. |
| `flutter_code_editor` 0.3.5 | Highlighting via `highlight`, folding, autocomplete. | Apache-2.0/MIT | Sep 2025; 233 likes. | Built on `TextField`: lays out the whole text, so no better than today for large scripts. |
| `highlight` 0.7.0 / `flutter_highlight` 0.7.0 | highlight.js port, 2021. | MIT | Unmaintained since 2021. | What AppFlowy uses. |
| `code_forge` 10.14 | Rust rope editor, 1M-line claims, LSP. | MIT | Sep 2026; needs rustup and FFI; unverified uploader. | Too heavy a toolchain for this project. |
| `markdown` 7.3.1 | CommonMark + GitHub-flavoured parser (tables, fenced code, strikethrough). | BSD-3 | Mar 2026; Dart team. | Already used by `appflowy_editor`; also usable standalone. |

## 9. Implementation approaches considered

The current single `TextField` cannot host a code block with its own toolbar, nor a slash menu that inserts blocks, nor rich text, nor images. Flutter's `TextField` is one text run; widgets cannot be embedded in it and it lays out the whole text. So the editor pane needs a block editor. Three ways to get one:

**A. Adopt `appflowy_editor` under MPL-2.0 and replace its code block with a StackSpace code block built on `re_editor`.**
Pros: the slash menu, Markdown shortcuts, rich text, lists, quotes, tables, images, toggles, undo, block virtualisation and Markdown round-trip all exist and are maintained; weeks of work saved; the fixed code block removes AppFlowy's main weakness. Markdown stays the file format, so the assistant tools and the importer keep working.
Cons: a large dependency with its own look to restyle; dual AGPL/MPL licence must be stated in the README and third-party notices; Markdown round-trip loses a few block types (callout icon, toggles, columns) unless extended; the user is replacing AppFlowy and may not want AppFlowy's editor inside the replacement.

**B. Build a StackSpace block editor from scratch.**
Each block its own widget; a model of blocks parsed from Markdown. Full control and MIT. Cost: cross-block selection, IME input, undo across blocks, drag and drop, tables and rich text spans are each weeks of work and bug-prone; the slash menu and code block would wait behind them.

**C. Hybrid: keep Markdown text, add a code-aware overlay.**
Keep one editor but swap it for a `re_editor` code editor with Markdown highlighting, a slash menu that inserts Markdown snippets, and fenced code regions highlighted by language. Fast and robust for large files. Cost: no true rich text or rendered tables/images; it is a Markdown editor with helpers, not a Notion-style page.

Recommendation: **A**, confirmed by a spike in Task 3 (load the imported workspace, round-trip Markdown, measure a 10,000-line code block). If the spike fails on round-trip or performance, fall back to C for this phase and keep B as the long-term path.

## 10. Sources

- AppFlowy Editor source: https://github.com/AppFlowy-IO/appflowy-editor (files cited above under `lib/src/editor/…`)
- AppFlowy Editor Plugins (code block): https://github.com/AppFlowy-IO/AppFlowy-plugins (`packages/appflowy_editor_plugins/lib/src/code_block/`)
- AppFlowy app slash menu and code block UI: https://github.com/AppFlowy-IO/AppFlowy (`frontend/appflowy_flutter/lib/plugins/document/presentation/editor_plugins/{slash_menu,code_block,actions,desktop_toolbar}`)
- AppFlowy release notes: https://appflowy.com/what-is-new
- AppFlowy docs index: https://docs.appflowy.io/docs/llms.txt ; editor codebase overview: https://docs.appflowy.io/docs/blog-highlights/demystifying-appflowy-editors-codebase.md ; Notion import guide: https://docs.appflowy.io/docs/guides/import-from-notion.md
- Notion help: https://www.notion.com/help/writing-and-editing-basics , https://www.notion.com/en-gb/help/guides/using-slash-commands , https://www.notion.com/help/code-blocks , https://www.notion.com/help/keyboard-shortcuts , https://www.notion.com/help/category/databases
- Packages: https://pub.dev/packages/appflowy_editor , https://pub.dev/packages/appflowy_editor_plugins , https://pub.dev/packages/re_editor , https://pub.dev/packages/re_highlight , https://pub.dev/packages/flutter_code_editor , https://pub.dev/packages/highlight , https://pub.dev/packages/flutter_highlight , https://pub.dev/packages/code_forge , https://pub.dev/packages/markdown

## 11. Spike results (Task 3 evidence, run 2026-10-25 on Flutter 3.47.8)

Scratch project with `appflowy_editor` and `re_editor`, tests in `test/spike_test.dart` and `test/roundtrip_test.dart` of the spike (not in this repo).

| Check | Result |
| --- | --- |
| `appflowy_editor` 6.2.0 from pub.dev | **Does not compile** on Flutter 3.47.8 (`DeltaTextInputService` lacks `TextInputClient.onFocusReceived`, added in newer Flutter). |
| `appflowy_editor` from GitHub `main` (01eccc6, Aug 2026) | Compiles and runs. Must be pinned by commit in `pubspec.yaml`. |
| Markdown round-trip of the 45 imported pages, stock decoder | 6/45 identical. **Fenced code blocks are dropped** by the stock decoder (the code block lives in the plugins package, and the editor's Markdown decoder has no parser for it). |
| Round-trip with a 25-line custom `CodeFenceParser` (fence → `code` node with `language`) | 35/45 identical after whitespace normalisation. Remaining diffs are cosmetic or small: bullets written as `*` not `-`; table rule `|-|` not `|---|`; image alt text dropped and no blank line after an image; **nested list items lose their indentation on export** (must fix in the encoder). |
| `appflowy_editor` with a 10,000-line code node | Parse 29 ms, first build 792 ms (cold), inserting text in a paragraph then one frame 111 ms, in the code node 37 ms (as a plain node without highlighting). |
| `re_editor` 20,000 lines | Build 162 ms, insert a line 32 ms, wrap on 54 ms, select all 14 ms. |
| `re_editor` 100,000 lines (4.7 MB) | Build 34 ms, insert a line 18 ms, wrap on 20 ms, select all 28 ms. |

Conclusion: approach A is viable. `re_editor` is the right body for the code block. The integration work is: pin the git commit, write the code fence parser and a matching encoder, fix bullets/nested lists/images in the encoder, and restyle.

## 12. Prioritised implementation plan (Task 2)

One task at a time; each ends with tests green and `PROJECT_STATUS.md` updated.

| # | Task | Done when |
| --- | --- | --- |
| 3 | **Done 2026-10-25.** Own block editor (the user ruled out code from other apps, so `appflowy_editor` is not used): `lib/editor/blocks.dart` (model + exact Markdown round trip), `lib/editor/page_document.dart` (undo/redo, edits), `lib/ui/editor/block_editor.dart` (one field per block, keyed virtual list, keys and shortcuts). The assistant keeps editing Markdown; the editor reloads from the file as before. | Every imported page round-trips identically (45/45), 69 tests pass, pages ≥100k lines still use the viewer. |
| 4 | Slash menu: StackSpace-styled menu with categories (Text, Lists, Code, Media, Page), aliases, descriptions, keyboard and mouse, edge flipping, no-match empty state, closes on Escape / no match. Excluded inside code blocks. | Widget tests for open, filter, Enter, Esc, arrows, click, replacement of `/query`, empty and mid-text blocks. |
| 5 | Slash menu test and fix pass; TEST_PLAN.md section. | All slash tests pass; manual run under Xvfb with screenshots. |
| 6 | **Done 2026-10-25.** Code spaces: `re_editor` + `re_highlight` (MIT) body, 30-language catalogue with a searchable picker, automatic language detection for typed or pasted code (guess written to the fence, picker overrides, "Auto-detect" resumes), copy, wrap, caption on the fence line, context menu, page-wide undo/redo, Ctrl+Enter / Backspace / arrows to move between blocks, `.py`-style files highlighted from their extension. | 107 tests pass (24 new); live run: typed Unity C# → `csharp`, pasted Python with tabs and Unicode → `python`, file byte-identical. |
| 7 | Code block clipboard, formatting and persistence tests (largely done in Task 6: `test/code_block_test.dart`); remaining Markdown shortcuts (`# `, `- `, `1. `, `[] `, `> `, ``` ``` ```, `**`, `` ` ``). | Tests for paste with tabs and Unicode, undo/redo, no corruption of neighbours. |
| 8 | Performance and regression: 5k / 10k / 50k-line pages and multi-block pages measured in tests; existing workspace loads; autosave; launch/close. | Numbers recorded in PROJECT_STATUS.md; no regression against the baseline. |
| 9 | Floating formatting toolbar (B/I/U/S/code/link/headings) and block option menu (turn into, duplicate, delete, move up/down). | Tests and screenshots. |
| 10 | Simple tables (add/remove row and column, Tab between cells) and images from the workspace folder. | Round-trip tests; screenshots. |
| 11 | Toggles, block drag-and-drop, columns. | As above. |
| Later | Colours, equations, search, page style, databases. | — |
