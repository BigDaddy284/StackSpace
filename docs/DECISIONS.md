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