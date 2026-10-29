import 'package:flutter/foundation.dart';

import 'blocks.dart';

/// Where the caret should go after an edit: a block and an offset in its text.
typedef Caret = ({int block, int offset});

/// The blocks of the open page, with undo and redo.
///
/// A Markdown page is a list of blocks. Any other file (a script, JSON, a
/// plain text note) is one code block edited as a whole, so nothing in it is
/// ever reinterpreted as Markdown.
class PageDocument extends ChangeNotifier {
  List<Block> _blocks = const [];
  List<Block> get blocks => _blocks;
  int get length => _blocks.length;
  Block operator [](int i) => _blocks[i];

  bool _plain = false;

  /// True when the file is not Markdown and is held as a single code block.
  bool get plain => _plain;

  /// Changes once per edit, so listeners can tell edits from reloads.
  int version = 0;

  final _undo = <_Snapshot>[];
  final _redo = <_Snapshot>[];
  static const _maxHistory = 300;
  DateTime? _lastTypedAt;
  int? _lastTypedBlock;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Replaces the content, clearing the history. [markdown] is false for files
  /// that are not Markdown pages.
  void load(String content, {bool markdown = true, String? language}) {
    _plain = !markdown;
    _blocks = markdown
        ? parseMarkdown(content)
        : [
            Block(
                kind: BlockKind.code,
                language: language,
                text: content.endsWith('\n') ? content.substring(0, content.length - 1) : content)
          ];
    if (_blocks.isEmpty) _blocks = [Block(kind: BlockKind.paragraph)];
    _undo.clear();
    _redo.clear();
    _lastTypedAt = null;
    version++;
    notifyListeners();
  }

  void clear() {
    _blocks = const [];
    _undo.clear();
    _redo.clear();
    version++;
    notifyListeners();
  }

  String? _markdown;
  int _markdownVersion = -1;
  List<int>? _lineStarts;
  int _lineStartsVersion = -1;

  /// The page as it will be saved. Cached until the next edit, because the
  /// status bar and the assistant's context ask for it often.
  String toMarkdown() {
    if (_markdown == null || _markdownVersion != version) {
      _markdown = _plain ? '${_blocks.map((b) => b.text).join('\n')}\n' : writeMarkdown(_blocks);
      _markdownVersion = version;
    }
    return _markdown!;
  }

  /// 1-based line in the saved file where [index]'s block starts.
  int startLine(int index) {
    if (_plain) return 1;
    if (_lineStarts == null || _lineStartsVersion != version) {
      final starts = List<int>.filled(_blocks.length, 1);
      var line = 1;
      for (var i = 0; i < _blocks.length; i++) {
        starts[i] = line;
        if (i + 1 < _blocks.length) {
          line += '\n'.allMatches(blockToMarkdown(_blocks[i])).length + 1 + gapBetween(_blocks[i], _blocks[i + 1]);
        }
      }
      _lineStarts = starts;
      _lineStartsVersion = version;
    }
    return index < _lineStarts!.length ? _lineStarts![index] : 1;
  }

  Map<int, int>? _index;
  int _indexVersion = -1;

  /// Index of the block with [id], or -1. A map built once per edit makes
  /// this cheap for the list, which asks for every visible row on each build.
  int indexOf(int id) {
    if (_index == null || _indexVersion != version) {
      _index = {for (var i = 0; i < _blocks.length; i++) _blocks[i].id: i};
      _indexVersion = version;
    }
    return _index![id] ?? -1;
  }

  // ---- edits ----------------------------------------------------------------

  void _commit(List<Block> next, {Caret? before, Caret? after, bool typing = false, int? block}) {
    final now = DateTime.now();
    final coalesce = typing &&
        block == _lastTypedBlock &&
        _lastTypedAt != null &&
        now.difference(_lastTypedAt!) < const Duration(seconds: 1) &&
        _undo.isNotEmpty;
    if (!coalesce) {
      _undo.add(_Snapshot(_blocks, before, after));
      if (_undo.length > _maxHistory) _undo.removeAt(0);
    }
    _lastTypedAt = typing ? now : null;
    _lastTypedBlock = typing ? block : null;
    _redo.clear();
    _blocks = List.unmodifiable(next);
    version++;
    notifyListeners();
  }

  List<Block> _copy() => List.of(_blocks);

  /// After a structural edit the blank lines recorded from the file may no
  /// longer fit, so the touched blocks go back to the default spacing.
  void _resetGaps(List<Block> next, Iterable<int> indices) {
    for (final i in indices) {
      if (i >= 0 && i < next.length && next[i].gapBefore != null) next[i] = next[i].copyWith(clearGap: true);
    }
  }

  /// Replaces the text of a block as the user types. Consecutive keystrokes in
  /// the same block within a second form one undo step.
  void updateText(int index, String text, {Caret? caret}) {
    if (_blocks[index].text == text) return;
    final next = _copy();
    next[index] = next[index].copyWith(text: text);
    _commit(next, typing: true, block: index, after: caret);
  }

  /// Replaces a whole block (kind, checked state, language and so on).
  void replace(int index, Block block, {Caret? after}) {
    final next = _copy();
    next[index] = block.id == _blocks[index].id ? block : block.copyWith();
    if (block.kind != _blocks[index].kind) _resetGaps(next, [index, index + 1]);
    _commit(next, after: after);
  }

  /// Replaces the blocks from [start] up to [end] (exclusive) with [blocks] in
  /// one undo step: an edit of a selection that spans blocks. The block after
  /// them goes back to the default spacing unless [resetGaps] is false (only
  /// the blocks' text changed).
  void replaceRange(int start, int end, List<Block> blocks, {Caret? before, Caret? after, bool resetGaps = true}) {
    final next = _copy()..replaceRange(start, end, blocks);
    if (resetGaps) _resetGaps(next, [start + blocks.length]);
    if (next.isEmpty) next.add(Block(kind: BlockKind.paragraph));
    _commit(next, before: before, after: after);
  }

  void insert(int index, Block block) {
    final next = _copy()..insert(index, block);
    _resetGaps(next, [index, index + 1]);
    _commit(next, after: (block: index, offset: 0));
  }

  /// Removes a block. The page always keeps at least one block.
  Caret remove(int index) {
    final next = _copy()..removeAt(index);
    _resetGaps(next, [index]);
    if (next.isEmpty) next.add(Block(kind: BlockKind.paragraph));
    final target = (index - 1).clamp(0, next.length - 1);
    final caret = (block: target, offset: next[target].text.length);
    _commit(next, after: caret);
    return caret;
  }

  /// Splits a block at [offset]. The part after the caret keeps the block's
  /// identity (so the field with the caret is reused) and continues a list,
  /// or becomes a paragraph after a heading or quote. The part before gets a
  /// new identity. Returns the caret in the second block.
  Caret split(int index, int offset) {
    final block = _blocks[index];
    final head = block.text.substring(0, offset);
    final tail = block.text.substring(offset);
    final first = block.clone().copyWith(text: head, gapBefore: block.gapBefore);
    final Block second;
    if (block.isList) {
      second = block.copyWith(text: tail, gapBefore: 0, clearNumber: true);
    } else if (block.kind == BlockKind.quote) {
      second = Block(id: block.id, kind: BlockKind.quote, text: tail);
    } else {
      second = Block(id: block.id, kind: BlockKind.paragraph, text: tail);
    }
    final next = _copy();
    next[index] = first;
    next.insert(index + 1, second);
    _resetGaps(next, [index + 2]);
    final caret = (block: index + 1, offset: 0);
    _commit(next, before: (block: index, offset: offset), after: caret);
    return caret;
  }

  /// Joins a block onto the end of the one before it. Returns the caret at the
  /// join, or null when there is nothing to merge with.
  Caret? mergeWithPrevious(int index) {
    if (index == 0) return null;
    final prev = _blocks[index - 1];
    final cur = _blocks[index];
    if (!prev.isText || !cur.isText) {
      if (cur.text.isEmpty) return remove(index);
      return null;
    }
    final next = _copy();
    next[index - 1] = prev.copyWith(text: prev.text + cur.text);
    next.removeAt(index);
    _resetGaps(next, [index]);
    final caret = (block: index - 1, offset: prev.text.length);
    _commit(next, before: (block: index, offset: 0), after: caret);
    return caret;
  }

  /// Turns a block into another kind, keeping its text.
  void convert(int index, BlockKind kind, {int level = 0, String? language, Caret? caret}) {
    final block = _blocks[index];
    final next = _copy();
    next[index] = Block(
      id: block.id,
      kind: kind,
      text: block.text,
      level: level,
      language: language,
      checked: false,
      marker: block.marker,
      gapBefore: block.isList && next[index].isList ? block.gapBefore : null,
    );
    if (!(block.isList && kind == block.kind)) _resetGaps(next, [index, index + 1]);
    _commit(next, after: caret ?? (block: index, offset: block.text.length));
  }

  /// Changes a list item's nesting by [delta] levels.
  void indent(int index, int delta, {Caret? caret}) {
    final block = _blocks[index];
    if (!block.isList) return;
    final level = (block.level + delta).clamp(0, 8);
    if (level == block.level) return;
    final next = _copy();
    next[index] = block.copyWith(level: level, clearNumber: true);
    _commit(next, after: caret);
  }

  void toggleChecked(int index) {
    final block = _blocks[index];
    if (block.kind != BlockKind.todo) return;
    final next = _copy();
    next[index] = block.copyWith(checked: !block.checked);
    _commit(next);
  }

  void move(int from, int to) {
    if (to < 0 || to >= _blocks.length || from == to) return;
    final next = _copy();
    final block = next.removeAt(from);
    next.insert(to, block);
    _resetGaps(next, [from, from + 1, to, to + 1]);
    _commit(next, after: (block: to, offset: 0));
  }

  // ---- history ---------------------------------------------------------------

  /// Undoes the last edit; returns where the caret was before it.
  Caret? undo() {
    if (_undo.isEmpty) return null;
    final snap = _undo.removeLast();
    _redo.add(_Snapshot(_blocks, snap.before, snap.after));
    final current = _blocks;
    _blocks = snap.blocks;
    _lastTypedAt = null;
    version++;
    notifyListeners();
    return snap.before ?? _firstDifference(current, snap.blocks);
  }

  Caret? redo() {
    if (_redo.isEmpty) return null;
    final snap = _redo.removeLast();
    _undo.add(_Snapshot(_blocks, snap.before, snap.after));
    final current = _blocks;
    _blocks = snap.blocks;
    _lastTypedAt = null;
    version++;
    notifyListeners();
    return snap.after ?? _firstDifference(current, snap.blocks);
  }

  /// The caret at the first block that differs between two states.
  Caret? _firstDifference(List<Block> from, List<Block> to) {
    if (to.isEmpty) return null;
    for (var i = 0; i < to.length; i++) {
      if (i >= from.length || from[i] != to[i]) return (block: i, offset: to[i].text.length);
    }
    return (block: to.length - 1, offset: to.last.text.length);
  }
}

class _Snapshot {
  _Snapshot(this.blocks, this.before, this.after);
  final List<Block> blocks;
  final Caret? before;
  final Caret? after;
}
