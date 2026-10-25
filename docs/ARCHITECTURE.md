# ARCHITECTURE

## Overview
This document outlines the architectural approach for developing a Windows 11 replacement for AppFlowy that addresses performance issues with large documents and scripts while preserving core functionality.

## Current State: Audit Phase
We are currently in the audit phase where we're analyzing the original AppFlowy architecture to understand:
- Technology stack used
- Document editor implementation details  
- Clipboard handling mechanisms
- Storage and persistence systems
- Performance bottlenecks in large document handling

## Editor architecture as built (2026-10-25)

```
file on disk (Markdown)
   │ Workspace.read / write (CRLF kept, paths checked)
   ▼
PageEditorController        opens a page, autosaves 600 ms after the last edit, reloads on AI changes,
   │                        holds the caret (focused block + selection) and builds the assistant's context
   ▼
PageDocument                the list of Blocks, undo/redo snapshots (typing coalesced per second),
   │                        split / merge / convert / indent / move, cached Markdown and line starts
   ▼
blocks.dart                 Block model + parseMarkdown / writeMarkdown (line based, exact round trip)

BlockEditor (lib/ui/editor/block_editor.dart)
   ListView.builder keyed by block id (findChildIndexCallback) → only visible blocks are built
   one TextField per text / table / raw block, InlineMarkdownController styles **bold**,
   _italic_, `code`, ~~strike~~ and [links] while keeping the markers in the text
   code blocks are CodeBlockView (lib/ui/editor/code_block.dart): header (language + "auto",
         wrap, copy, menu), re_editor CodeEditor body with line numbers and re_highlight colours,
         optional caption field; language guessed by lib/editor/code_languages.dart 500 ms after
         the last edit when the fence had none
   divider and image blocks are focusable widgets
   keys: Backspace at start (merge / demote), Tab / Shift+Tab (indent), arrows between blocks,
         Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z, Ctrl+Shift+Up/Down (move block)
   text: newline splits (Shift+Enter keeps a soft break), shortcuts convert, late platform
         updates are reconciled
   selection toolbar (lib/ui/editor/format_toolbar.dart): shown in an Overlay above or below the
         selected text (RenderEditable boxes), Bold / Italic / Strike / Code / Link + "Turn into";
         buttons never take focus, so the field keeps its selection; closes on collapse, scroll, blur
   block handle + menu (lib/ui/editor/block_menu.dart): 24 px gutter left of every row, a
         drag-handle button visible on hover or focus, popup with Turn into / Duplicate /
         Move up / Move down / Delete; edits go through PageDocument so undo covers them
```

Every row of the list has a height computed before it is built (`lib/ui/editor/block_metrics.dart`:
the same styles, struts, paddings and marker sizes as the widgets, measured with a TextPainter at
the row's width; short single-line rows skip the layout). The list is a `ListView.builder` with
`itemExtentBuilder`, so dragging the scrollbar to the end of a 50,000-block page lays out only the
rows that show there. Heights are cached per block object and recomputed in one pass per edit;
`test/block_metrics_test.dart` checks them against the rendered rows to the pixel. Each row is an
`OverflowBox`, so a height that was off would overlap the next row rather than squeeze a field.

Pages over 250,000 lines or 16 MB open in the read-only line viewer; the assistant can still edit them.

## Proposed Architecture for Replacement

### Core Components

#### 1. Application Framework
- Flutter desktop app (Windows 11 first); the design is a port of the Stills & Reels look
- Cross-platform compatibility layer if needed
- Modern application lifecycle management

#### 2. Document Engine
- Virtualized rendering system to handle large documents efficiently
- Incremental document updates
- Efficient text buffer management
- Lazy loading of content sections

#### 3. Editor Components
- Rich text editor with virtualization support
- Dedicated script editor for large code blocks
- Syntax highlighting engine
- Line number display and scrolling optimization

#### 4. Storage System
- Local file-based storage with proper transaction handling
- Efficient document serialization/deserialization
- Backup and recovery mechanisms
- Version control for document changes

#### 5. Clipboard Integration
- Optimized clipboard handling for large content
- Chunked processing of paste operations
- Asynchronous clipboard operations
- Memory-efficient serialization

#### 6. Performance Monitoring
- Real-time performance metrics
- Memory usage tracking
- Responsiveness monitoring
- Profiling tools for identifying bottlenecks

### Key Design Principles

#### Performance First
- Never block the UI thread with expensive operations
- Asynchronous processing of heavy tasks
- Background parsing and syntax highlighting
- Efficient memory management for large documents

#### Large Document Handling
- Virtualized rendering to avoid loading entire documents into memory
- Incremental updates instead of full re-renders
- Chunked processing for clipboard operations
- Memory-efficient text representation

#### Data Integrity
- Safe database transactions
- Protection against partial writes
- Recovery after unexpected shutdowns
- Versioning and conflict detection

#### Windows 11 Compatibility
- Native Windows 11 UI components
- Proper window management and scaling
- Clipboard integration with Windows
- File path handling for Windows systems

### Technology Stack Considerations

#### Frontend
- WinUI 3 or similar modern Windows UI framework
- Custom rendering components for virtualization
- Rich text editing components (possibly leveraging existing libraries)

#### Backend
- Rust or C++ for performance-critical components
- Modern C++ for Windows native performance
- Database engine for local storage (SQLite, etc.)

#### Tooling
- Build systems optimized for Windows 11
- Performance testing frameworks
- Memory profiling tools

## Data Flow Architecture

### Document Loading
1. File system access layer
2. Document parsing and validation
3. Virtualized rendering engine
4. Memory management for large content

### Editing Operations
1. User input handling
2. Command processing pipeline
3. Asynchronous background operations
4. Update propagation to rendering engine

### Clipboard Operations
1. Content serialization
2. Chunked transfer for large content
3. Background processing
4. Memory management during operations

## Performance Targets

### Response Times
- Normal typing and keyboard interaction: < 100ms response time
- Scrolling and selection: < 100ms response time
- Opening 5,000 lines: within 2 seconds
- Opening 10,000 lines: within 4 seconds
- Pasting 5,000 lines: within 3 seconds
- Pasting 10,000 lines: within 5 seconds

### Memory Usage
- Efficient memory management for large documents
- No unbounded memory growth during editing
- Proper resource cleanup when documents close

## Risk Mitigation

### Known Risks
- Performance regressions in replacement vs. original
- Data loss during clipboard operations
- Memory leaks in large document handling
- UI freezing during heavy operations

### Mitigation Strategies
- Comprehensive testing with large document benchmarks
- Memory profiling and monitoring
- Asynchronous processing to avoid UI blocking
- Backup and recovery mechanisms

## Next Steps
1. Complete audit of original AppFlowy repository
2. Document specific performance bottlenecks identified
3. Finalize architecture recommendations based on findings
4. Begin implementation planning with smallest sensible task