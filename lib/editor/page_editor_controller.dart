import 'dart:async';

import 'package:flutter/widgets.dart';

import '../ai/chat_controller.dart';
import '../workspace/workspace.dart';

/// Holds the page open in the editor: loads it, autosaves edits, and reloads
/// it when the assistant changes it on disk.
class PageEditorController extends ChangeNotifier {
  PageEditorController(this.workspace) {
    _changes = workspace.changes.listen(_onWorkspaceChange);
    text.addListener(_onTextChanged);
  }

  final Workspace workspace;
  final text = TextEditingController();
  late final StreamSubscription<WorkspaceChange> _changes;

  /// Pages bigger than this open in a read-only line viewer, because Flutter's
  /// TextField lays out the whole text and becomes unusable on very large files.
  static const largeLineCount = 20000;
  static const largeCharCount = 2 * 1024 * 1024;
  static const _autosaveDelay = Duration(milliseconds: 600);

  String? _path;
  String? get path => _path;

  bool _dirty = false;
  bool get dirty => _dirty;

  String? error;

  /// Lines of a page too large for the text editor, or null for normal pages.
  List<String>? largeLines;
  bool get isLarge => largeLines != null;

  bool _loading = false;
  String _savedText = '';
  Timer? _autosave;

  Future<void> open(String path) async {
    await flush();
    _loading = true;
    error = null;
    try {
      final content = await workspace.read(path);
      _path = workspace.normalize(path);
      _setContent(content);
    } on WorkspaceException catch (e) {
      error = e.message;
    } finally {
      _loading = false;
    }
    notifyListeners();
  }

  void close() {
    _autosave?.cancel();
    _path = null;
    largeLines = null;
    _dirty = false;
    _loading = true;
    text.clear();
    _loading = false;
    notifyListeners();
  }

  void _setContent(String content) {
    _savedText = content;
    _dirty = false;
    _loading = true;
    if (content.length > largeCharCount || '\n'.allMatches(content).length >= largeLineCount) {
      largeLines = content.split('\n');
      text.clear();
    } else {
      largeLines = null;
      final old = text.selection;
      text.value = TextEditingValue(
        text: content,
        selection: old.isValid && old.end <= content.length ? old : const TextSelection.collapsed(offset: 0),
      );
    }
    _loading = false;
  }

  void _onTextChanged() {
    if (_loading || _path == null || isLarge) return;
    final changed = text.text != _savedText;
    if (changed != _dirty) {
      _dirty = changed;
      notifyListeners();
    } else {
      // Selection moved; the composer shows the selection, so let it know.
      notifyListeners();
    }
    if (changed) {
      _autosave?.cancel();
      _autosave = Timer(_autosaveDelay, flush);
    }
  }

  /// Saves pending edits now.
  Future<void> flush() async {
    _autosave?.cancel();
    final path = _path;
    if (path == null || !_dirty || isLarge) return;
    final content = text.text;
    try {
      await workspace.write(path, content);
      _savedText = content;
      _dirty = text.text != content;
      error = null;
    } on Exception catch (e) {
      error = 'Could not save: $e';
    }
    notifyListeners();
  }

  Future<void> _onWorkspaceChange(WorkspaceChange change) async {
    final path = _path;
    if (path == null) return;
    final affected = change.path == path || path.startsWith('${change.path}/');
    if (!affected) return;
    switch (change.kind) {
      case WorkspaceChangeKind.deleted:
        close();
      case WorkspaceChangeKind.renamed:
        _path = change.newPath! + path.substring(change.path.length);
        notifyListeners();
      case WorkspaceChangeKind.modified || WorkspaceChangeKind.created:
        if (change.source != ChangeSource.ai) return;
        final content = await workspace.read(path);
        _setContent(content);
        notifyListeners();
    }
  }

  /// The open page and the current selection, for the assistant.
  ChatContext get chatContext {
    final path = _path;
    if (path == null) return const ChatContext();
    if (isLarge) return ChatContext(pagePath: path, pageText: largeLines!.join('\n'));
    final value = text.value;
    final sel = value.selection;
    if (!sel.isValid || sel.isCollapsed) return ChatContext(pagePath: path, pageText: value.text);
    final before = value.text.substring(0, sel.start);
    final selected = value.text.substring(sel.start, sel.end);
    final startLine = '\n'.allMatches(before).length + 1;
    final endLine = startLine + '\n'.allMatches(selected.endsWith('\n') ? selected.substring(0, selected.length - 1) : selected).length;
    return ChatContext(
      pagePath: path,
      pageText: value.text,
      selection: selected,
      selectionStartLine: startLine,
      selectionEndLine: endLine,
    );
  }

  /// Line and column of the cursor, 1-based.
  (int, int) get cursor {
    final offset = text.selection.isValid ? text.selection.extentOffset : 0;
    final before = text.text.substring(0, offset.clamp(0, text.text.length));
    final line = '\n'.allMatches(before).length + 1;
    final column = offset - (before.lastIndexOf('\n') + 1) + 1;
    return (line, column);
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _changes.cancel();
    text.dispose();
    super.dispose();
  }
}
