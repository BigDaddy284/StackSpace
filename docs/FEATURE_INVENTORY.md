# FEATURE INVENTORY

## Overview
This document outlines the features of AppFlowy as identified during the audit phase. The goal is to create a comprehensive inventory to understand what needs to be preserved or replicated in our Windows replacement.

## Core Features

### Workspaces and Navigation
- Workspaces, pages, subpages, folders and navigation structure
- Hierarchical organization of documents
- Workspace switching and management

### Rich Text Editing
- Rich-text editing and formatting capabilities
- Headings, lists, checklists, quotes and links
- Formatting tools and styles

### Code Blocks and Scripts
- Code blocks for programming languages
- Support for large scripts (>5,000 lines)
- Syntax highlighting
- Line numbers
- Monospaced text support

### Tables and Databases
- Tables, databases, properties, views
- Sorting, filtering and grouping capabilities
- Database integration with various data sources

### Search and Navigation
- Search functionality within documents and workspaces
- Navigation tools and shortcuts

### Media and Attachments
- Images, attachments and embedded content support
- File import and export capabilities

### Clipboard Operations
- Copy, paste, cut functionality
- Handling of large clipboard contents
- Cross-application clipboard integration

### Import and Export
- Document import from various formats
- Export to multiple formats
- Template support

### Keyboard Shortcuts
- Standard keyboard shortcuts for editing
- Customizable shortcuts

### Undo/Redo
- Comprehensive undo/redo functionality
- Multi-level undo/redo operations

### Autosave and Recovery
- Auto-save capabilities
- Document recovery after unexpected shutdowns
- Versioning and conflict detection

### Settings and Customization
- User preferences and settings
- Customization options for interface and behavior

### AI Integration
- Existing AI features where practical
- Integration with various AI services

### Collaboration and Extensions
- Synchronization capabilities
- Collaboration features
- Extension and integration support

## Technical Features

### Storage System
- Local storage mechanisms
- Database persistence
- File format specifications

### Performance Characteristics
- Current performance with large documents
- Known freezing and crash scenarios
- Memory usage patterns

### Platform Support
- Cross-platform compatibility
- Specific Windows requirements for this replacement

## Missing or Deferred Features
- Features that are not currently supported but could be implemented later
- Features that may require additional research

## Implementation Status (2026-10-25)

| Feature | Status |
|---|---|
| Workspace, pages, folders, sidebar navigation | Implemented and tested (pages are files in a folder) |
| Block editor: headings, paragraphs, bullet / numbered / todo lists with nesting, quotes, code blocks, dividers, images, tables (raw), inline bold / italic / code / strike / link styling, Markdown shortcuts, autosave | Implemented and tested (Task 3) |
| Large scripts and pages | Editable block by block; only the blocks on screen are built and every row's height is known up front, so scrollbar drags and jumps are cheap (Task 8: a 50,000-paragraph page opens, jumps to its end and takes typing in the release build without a pause). Over 250k lines / 16 MB: read-only viewer |
| AI assistant (local models via Ollama): chat, page/selection context, create/edit/rename/delete pages, undo | Implemented; tested against a fake Ollama, not yet a real model |
| Search across pages | Partial: available to the assistant, no search box in the UI yet |
| Keyboard shortcuts | Ctrl+J assistant, Ctrl+S save, Ctrl+N new page; in text: Ctrl+B bold, Ctrl+I italic, Ctrl+E inline code, Ctrl+Shift+X strikethrough, Ctrl+K link, Tab / Shift+Tab indent, Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z, Ctrl+Shift+Up / Down move a block, Shift+Enter soft break; in code: Ctrl+Enter leaves the block, arrows at the edges move between blocks (Task 7) |
| Undo/redo in the editor | Implemented: document-level undo/redo (Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z), typing coalesced per second |
| Settings | Partial: theme (Windows / light / dark), workspace folder, Ollama address, context length, delete confirmation |
| Light / dark themes, accessibility (WCAG AA contrast, screen-reader labels, 150% text) | Implemented and tested |
| Slash menu (13 commands, aliases, search, keyboard and mouse) | Implemented and tested (Tasks 4-5) |
| Code spaces: distinct background, monospace, line numbers, syntax highlighting for 30 languages, searchable language picker, **automatic language detection for typed or pasted code** (written into the fence, "auto" shown, picker overrides), copy button, wrap toggle, caption on the fence line, context menu (copy / copy all / cut / paste / select all / wrap / language / caption / delete), exact paste and copy, page-wide undo/redo, Ctrl+Enter to leave the block, Backspace on an empty block back to text; `.py` / `.json` / ... files open as one code space with the language from the extension | Implemented and tested (Task 6) |
| Floating formatting toolbar on a selection (bold, italic, strikethrough, inline code, link, turn into) | Implemented and tested (Task 9) |
| Block handle and menu (turn into, duplicate, move up / down, delete) | Implemented and tested (Task 9) |
| Table editing as a grid (Tab / Enter / arrows between cells, add / remove row and column, padded Markdown kept in the page) | Implemented and tested (Task 10) |
| Table column widths by dragging the borders (kept in the page), multi-cell selection, copy / cut / paste as tab-separated text (Excel compatible) | Implemented and tested (v0.3.6-test.1) |
| Images: insert from a file picker, path or link; outside files copied next to the page; alt-text field | Implemented and tested (Task 10) |
| Links: bare URLs and `[label](url)` shown as links, Ctrl+click opens (http / https / mailto), URL pasted over words links them, Ctrl+K links / unlinks | Implemented and tested (Bug 2) |
| Folding sections: a chevron beside every heading hides the blocks up to the next heading of the same level; Collapse / Expand in the block menu | Implemented and tested (Task 11) |
| Drag and drop: drag the block handle to move a block, insertion line, auto-scroll at the edges | Implemented and tested (Task 11) |
| Sidebar shows pages only: pictures, archives and other binary files (and folders holding only those) are hidden | Implemented and tested (Task 12) |
| Sidebar like File Explorer: drag pages and folders into and out of folders (Ctrl copies), cut / copy / paste / duplicate with subpages, Ctrl+ and Shift+click multi-select | Implemented and tested |
| Columns (side-by-side blocks) | Deferred: no Markdown syntax |
| Databases, views | Deferred |
| Images, attachments, templates | Deferred |
| AppFlowy backup import | Implemented (File > Import, zip or folder); export deferred |
| Sync, collaboration, extensions | Deferred |

## Notes
This inventory will be expanded as we analyze the original repository more thoroughly. The focus is particularly on identifying performance bottlenecks related to large documents and clipboard handling.