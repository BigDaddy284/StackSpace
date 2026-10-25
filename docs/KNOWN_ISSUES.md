# KNOWN ISSUES

## Overview
This document tracks known issues and problems identified during the audit phase of the AppFlowy replacement project. Issues are categorized by severity and impact.

## Current issues in the StackSpace app (2026-10-25)

### Not tested with a real Ollama model
**Status**: Open. The cloud environment can't download models, so the assistant was tested against a
fake Ollama server that follows the documented API. Small local models may call tools less reliably.

### Large files are read-only in the editor
**Status**: Open. Pages over 20,000 lines or 2 MB open in a virtualised read-only viewer, because
Flutter's TextField lays out the whole text. The assistant can still edit them. Next task.

### Windows build not yet run
**Status**: Open. `flutter build windows` needs a Windows machine with Visual Studio C++ tools.

### Editor is plain text
**Status**: Open. No rich text, syntax highlighting, line numbers in the editable view or databases.
Imported AppFlowy pages are Markdown, so links and tables show as Markdown text.

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

