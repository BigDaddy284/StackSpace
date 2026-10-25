import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../ai/chat_controller.dart';
import '../workspace/workspace.dart';
import 'blocks.dart';
import 'page_document.dart';

/// Holds the page open in the editor: loads it into a [PageDocument],
/// autosaves edits, and reloads it when the assistant changes it on disk.
class PageEditorController extends ChangeNotifier {
  PageEditorController(this.workspace) {
    _changes = workspace.changes.listen(_onWorkspaceChange);
    document.addListener(_onDocumentChanged);
  }

  final Workspace workspace;
  final document = PageDocument();
  late final StreamSubscription<WorkspaceChange> _changes;

  /// Pages bigger than this open in a read-only line viewer.
  static const largeLineCount = 100000;
  static const largeCharCount = 8 * 1024 * 1024;
  static const _autosaveDelay = Duration(milliseconds: 600);

  static bool isMarkdown(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.md' || ext == '.markdown' || ext == '';
  }

  String? _path;
  String? get path => _path;

  /// The document version that matches the file on disk.
  int _savedVersion = 0;
  bool get dirty => _path != null && !isLarge && document.version != _savedVersion;
  bool _wasDirty = false;

  String? error;

  /// Lines of a page too large for the editor, or null for normal pages.
  List<String>? largeLines;
  bool get isLarge => largeLines != null;

  /// The block that has the caret and the selection inside it.
  int focusedBlock = 0;
  TextSelection selection = const TextSelection.collapsed(offset: 0);

  /// Fires on caret moves only, so the status bar and the composer's context
  /// chip can follow the caret without rebuilding the whole window.
  final caretChanges = _CaretNotifier();

  Timer? _autosave;

  Future<void> open(String path) async {
    await flush();
    error = null;
    try {
      final content = await workspace.read(path);
      _path = workspace.normalize(path);
      focusedBlock = 0;
      selection = const TextSelection.collapsed(offset: 0);
      _setContent(content);
    } on WorkspaceException catch (e) {
      error = e.message;
    }
    notifyListeners();
  }

  void close() {
    _autosave?.cancel();
    _path = null;
    largeLines = null;
    document.clear();
    _savedVersion = document.version;
    _wasDirty = false;
    notifyListeners();
  }

  void _setContent(String content) {
    if (content.length > largeCharCount || '\n'.allMatches(content).length >= largeLineCount) {
      largeLines = content.split('\n');
      document.clear();
    } else {
      largeLines = null;
      document.load(content, markdown: isMarkdown(_path!));
    }
    _savedVersion = document.version;
    _wasDirty = false;
  }

  void _onDocumentChanged() {
    if (_path == null || isLarge) return;
    final changed = dirty;
    if (changed) {
      _autosave?.cancel();
      _autosave = Timer(_autosaveDelay, flush);
    }
    if (changed != _wasDirty) {
      _wasDirty = changed;
      notifyListeners();
    }
  }

  /// Called by the editor whenever the caret moves.
  void setSelection(int block, TextSelection sel) {
    if (block == focusedBlock && sel == selection) return;
    focusedBlock = block;
    selection = sel;
    caretChanges.fire();
  }

  /// Saves pending edits now.
  Future<void> flush() async {
    _autosave?.cancel();
    final path = _path;
    if (path == null || !dirty) return;
    final version = document.version;
    final content = document.toMarkdown();
    try {
      await workspace.write(path, content);
      _savedVersion = version;
      error = null;
    } on Exception catch (e) {
      error = 'Could not save: $e';
    }
    _wasDirty = dirty;
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
        focusedBlock = focusedBlock.clamp(0, (document.length - 1).clamp(0, 1 << 30));
        selection = const TextSelection.collapsed(offset: 0);
        notifyListeners();
    }
  }

  /// The open page and the current selection, for the assistant.
  ChatContext get chatContext {
    final path = _path;
    if (path == null) return const ChatContext();
    if (isLarge) return ChatContext(pagePath: path, pageText: largeLines!.join('\n'));
    final text = document.toMarkdown();
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed || focusedBlock >= document.length) {
      return ChatContext(pagePath: path, pageText: text);
    }
    final block = document[focusedBlock];
    final end = sel.end.clamp(0, block.text.length);
    final start = sel.start.clamp(0, end);
    final selected = block.text.substring(start, end);
    final startLine = _lineOf(focusedBlock, start);
    final endLine = _lineOf(focusedBlock, selected.endsWith('\n') ? end - 1 : end);
    return ChatContext(
      pagePath: path,
      pageText: text,
      selection: selected,
      selectionStartLine: startLine,
      selectionEndLine: endLine,
    );
  }

  /// The file line that holds [offset] of block [index]. Block kinds whose
  /// Markdown has a lead line (code fences) count it.
  int _lineOf(int index, int offset) {
    final block = document[index];
    final before = block.text.substring(0, offset.clamp(0, block.text.length));
    final lead = block.kind == BlockKind.code && !document.plain ? 1 : 0;
    return document.startLine(index) + lead + '\n'.allMatches(before).length;
  }

  /// Line and column of the cursor in the saved file, 1-based.
  (int, int) get cursor {
    if (_path == null || isLarge || document.length == 0) return (1, 1);
    final index = focusedBlock.clamp(0, document.length - 1);
    final block = document[index];
    final offset = (selection.isValid ? selection.extentOffset : 0).clamp(0, block.text.length);
    final before = block.text.substring(0, offset);
    final column = offset - (before.lastIndexOf('\n') + 1) + 1;
    return (_lineOf(index, offset), column);
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _changes.cancel();
    document.dispose();
    caretChanges.dispose();
    super.dispose();
  }
}

class _CaretNotifier extends ChangeNotifier {
  void fire() => notifyListeners();
}
