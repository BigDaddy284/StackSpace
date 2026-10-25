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
| Plain-text / code editing with autosave | Implemented and tested |
| Large scripts (20k+ lines) | Partial: read-only virtualised viewer; editing is the next task |
| AI assistant (local models via Ollama): chat, page/selection context, create/edit/rename/delete pages, undo | Implemented; tested against a fake Ollama, not yet a real model |
| Search across pages | Partial: available to the assistant, no search box in the UI yet |
| Keyboard shortcuts | Partial: Ctrl+J assistant, Ctrl+S save, Ctrl+N new page |
| Undo/redo in the editor | Partial: TextField's built-in undo only |
| Settings | Partial: theme (Windows / light / dark), workspace folder, Ollama address, context length, delete confirmation |
| Light / dark themes, accessibility (WCAG AA contrast, screen-reader labels, 150% text) | Implemented and tested |
| Rich text, headings/lists formatting, tables, databases, views | Deferred |
| Images, attachments, templates | Deferred |
| AppFlowy backup import / export | Deferred (prototype code in legacy/ never worked) |
| Sync, collaboration, extensions | Deferred |

## Notes
This inventory will be expanded as we analyze the original repository more thoroughly. The focus is particularly on identifying performance bottlenecks related to large documents and clipboard handling.