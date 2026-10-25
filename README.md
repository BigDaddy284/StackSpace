# StackSpace

A Windows 11 notes and scripts app meant to replace AppFlowy, with a built-in assistant
that runs on local models through [Ollama](https://ollama.com).

## What works today

- **Workspace**: a folder on disk (default `Documents\StackSpace`). Every text file in it
  is a page, and sub-folders group pages. Create, rename and delete pages from the sidebar
  (right-click for the menu). Deleted pages go to the workspace's `.trash` folder.
- **Editor**: plain-text editor with autosave, keeping each file's line endings (CRLF stays CRLF).
  Files over 20,000 lines or 2 MB open in a fast read-only viewer instead (see Known limits).
- **Assistant** (bottom dock):
  - Open it with the **Assistant** button or **Ctrl+J**. Minimise it to a bar, maximise it
    over the editor, or close it. Drag the line above it to resize.
  - The header shows whether Ollama is connected, the model in use and the thinking level.
  - Pick the model and thinking level (Off / Low / Medium / High) under the message box.
    Low / Medium / High are sent as levels to models that take them (gpt-oss), and as
    "thinking on" to other thinking models.
  - The open page and any text you've selected are sent with your message, shown as chips
    you can remove. "This" in your message means the selection.
  - The model can list, read, search, create, edit, rename and delete pages. Every change
    shows as a card in the chat with an **Undo** button. Deletes ask you first (Settings can
    turn that off), and the editor is locked while the assistant is working.

## Look and accessibility

- Uses the Stills & Reels look: deep navy surfaces, a blue accent and a blue-to-violet
  gradient on the Assistant button and the focused message box.
- Light and dark themes. The button next to Settings cycles between following Windows,
  light and dark; Settings has the same choice.
- Every text colour reaches WCAG AA contrast (4.5:1) on the surfaces it's used on, and
  borders and icons reach 3:1. `test/theme_contrast_test.dart` checks the palette, and
  `test/accessibility_test.dart` checks the running app in both themes for contrast,
  screen-reader labels, 24x24 click targets, and layout at 150% text size.
- Keyboard: Ctrl+J opens and closes the assistant, Enter sends, Shift+Enter adds a line,
  and F2 / Delete rename or delete the focused page in the sidebar.

## Using it with Ollama

1. Install Ollama for Windows and pull a model that supports tools, for example
   `ollama pull qwen3:8b` (tools + thinking) or `ollama pull gpt-oss:20b` (tools + thinking levels).
2. Start StackSpace. It connects to `http://127.0.0.1:11434` by default (change it in Settings).
3. Models without tool support can still answer questions, but can't change pages; the chat
   shows "No tools" for them.

## Developing

```bash
flutter pub get
flutter analyze
flutter test                                   # all tests
flutter test test/workspace_tools_test.dart    # one file
flutter test --plain-name "replace_text"       # one test
flutter run -d windows
flutter build windows --release                # build\windows\x64\runner\Release\stack_space.exe
```

Building the Windows .exe needs a Windows machine with Visual Studio's
"Desktop development with C++" workload.

## Known limits

- Very large files (20,000+ lines) are read-only in the editor for now. The assistant can
  still read and edit them through its tools.
- No rich text, databases, tables or AppFlowy import yet. See `FEATURE_INVENTORY.md`.
- `legacy/` holds the earlier prototype, which never compiled. It's not part of the build.

## Licence and AppFlowy

StackSpace is MIT licensed (see `LICENSE`). It is an independent app, not affiliated with or
endorsed by AppFlowy. It contains no AppFlowy code: AppFlowy was used only as a reference for which
features to offer. The importer reads AppFlowy's export file format so you can bring your own pages
across. The `windows/` runner is Flutter's standard project template.
