import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../../app/theme.dart';
import '../../editor/block_range.dart';
import '../../editor/blocks.dart';
import '../../editor/links.dart';
import '../../editor/code_languages.dart';
import '../../editor/page_document.dart';
import '../../editor/page_editor_controller.dart';
import '../../editor/slash_commands.dart';
import '../../editor/spell_checker.dart';
import '../../editor/table_clip.dart';
import '../../editor/table_data.dart';
import 'block_menu.dart';
import 'block_metrics.dart';
import 'code_block.dart';
import 'format_toolbar.dart';
import 'inline_markdown.dart';
import 'image_dialog.dart';
import 'slash_menu.dart';
import 'spelling.dart';
import 'table_block.dart';

/// Edits a page block by block. Each block is its own text field, so a page
/// with thousands of lines of code lays out only the blocks on screen.
class BlockEditor extends StatefulWidget {
  const BlockEditor({super.key, required this.controller, required this.readOnly, this.pickImage});

  final PageEditorController controller;
  final bool readOnly;

  /// Asks the user for an image path or link; null when they cancel. The
  /// default is a small dialog.
  final Future<String?> Function(BuildContext context)? pickImage;

  @override
  State<BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends State<BlockEditor> {
  PageDocument get doc => widget.controller.document;

  final _texts = <int, InlineMarkdownController>{};
  final _focus = <int, FocusNode>{};
  final _scroll = ScrollController();

  /// Where the caret goes once the target block has been built.
  Caret? _pending;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    widget.controller.historyHandler = _history;
  }

  /// Undo or redo, with the caret put back where the change was.
  void _history({required bool redo}) {
    _setRange(null);
    final before = doc.blocks;
    final caret = redo ? doc.redo() : doc.undo();
    // In a table the caret goes to the cell that changed, not the last one.
    _pendingCell = null;
    if (caret != null && caret.block < doc.length && doc[caret.block].kind == BlockKind.table) {
      final table = doc[caret.block];
      final old = before.indexWhere((b) => b.id == table.id);
      _pendingCell = (table.id, old < 0 ? null : TableData.firstChange(before[old].text, table.text));
    }
    _moveCaret(caret);
  }

  /// The table block an undo or redo changed, and the cell in it for the caret.
  (int, (int, int, int)?)? _pendingCell;

  final _fieldKeys = <int, GlobalKey>{};

  // Code spaces: their editors, wrap setting, and which ones have a guessed
  // language (so a later edit may guess again).
  final _codes = <int, CodeLineEditingController>{};
  final _wrap = <int, bool>{};
  final _autoLanguage = <int>{};
  final _detectTimers = <int, Timer>{};
  static const detectDelay = Duration(milliseconds: 500);

  final _slashPortal = OverlayPortalController();
  final _toolbarPortal = OverlayPortalController();
  _ToolbarSession? _toolbar;

  /// Whether the mouse is over a row, one notifier per block, read by its handle.
  final _hovers = <int, ValueNotifier<bool>>{};
  _SlashSession? _slash;

  /// The open slash menu, for tests and the pane.
  bool get slashMenuOpen => _slash != null;

  @override
  void dispose() {
    if (widget.controller.historyHandler == _history) widget.controller.historyHandler = null;
    _autoScroll?.cancel();
    _selectScroll?.cancel();
    _scroll.removeListener(_onScroll);
    for (final h in _hovers.values) {
      h.dispose();
    }
    for (final c in _texts.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    for (final f in _codeFocus.values) {
      f.dispose();
    }
    for (final c in _codes.values) {
      c.dispose();
    }
    for (final t in _detectTimers.values) {
      t.cancel();
    }
    _scroll.dispose();
    super.dispose();
  }

  InlineMarkdownController _textFor(Block block) =>
      _texts.putIfAbsent(block.id, () => InlineMarkdownController(text: block.text));

  /// A code space has its own node (Bug 1): a block turned into a code space
  /// keeps its id, and with the paragraph's still-focused node the code
  /// editor would see no focus change and never open its keyboard input.
  final _codeFocus = <int, FocusNode>{};
  FocusNode _focusFor(Block block) => _isCode(block)
      ? _codeFocus.putIfAbsent(block.id, () => FocusNode(debugLabel: 'block ${block.id}'))
      : _focus.putIfAbsent(block.id, () => FocusNode(debugLabel: 'block ${block.id}'));

  final _tableKeys = <int, GlobalKey<TableBlockViewState>>{};
  GlobalKey<TableBlockViewState> _tableKeyFor(Block block) => _tableKeys.putIfAbsent(block.id, GlobalKey.new);

  /// The alt-text field of an image block.
  final _alts = <int, TextEditingController>{};
  final _altFocus = <int, FocusNode>{};
  TextEditingController _altFor(Block block) =>
      _alts.putIfAbsent(block.id, () => TextEditingController(text: block.alt));
  FocusNode _altFocusFor(Block block) =>
      _altFocus.putIfAbsent(block.id, () => FocusNode(debugLabel: 'alt ${block.id}'));

  CodeLineEditingController _codeFor(Block block) =>
      _codes.putIfAbsent(block.id, () => CodeLineEditingController.fromText(block.text));

  /// Whether the block's text lives in a code editor rather than a text field.
  bool _isCode(Block block) => block.kind == BlockKind.code;

  GlobalKey _fieldKeyFor(Block block) => _fieldKeys.putIfAbsent(block.id, GlobalKey.new);
  ValueNotifier<bool> _hoverFor(Block block) => _hovers.putIfAbsent(block.id, () => ValueNotifier(false));

  /// Code blocks whose caption field is open although the caption is empty.
  final _captions = <int>{};

  /// Measured row heights, keyed by block id; valid while the block object,
  /// width, text scale and code options are the same.
  final _heights = <int, _Measured>{};

  void _prune() {
    final live = {for (final b in doc.blocks) b.id};
    _fieldKeys.removeWhere((id, _) => !live.contains(id));
    _bodyKeys.removeWhere((id, _) => !live.contains(id));
    _rows.removeWhere((id, _) => !live.contains(id));
    _heights.removeWhere((id, _) => !live.contains(id));
    _captions.removeWhere((id) => !live.contains(id));
    for (final id in _hovers.keys.where((id) => !live.contains(id)).toList()) {
      _hovers.remove(id)!.dispose();
    }
    for (final id in _texts.keys.where((id) => !live.contains(id)).toList()) {
      _texts.remove(id)!.dispose();
    }
    _tableKeys.removeWhere((id, _) => !live.contains(id));
    for (final id in _alts.keys.where((id) => !live.contains(id)).toList()) {
      _alts.remove(id)!.dispose();
    }
    for (final id in _altFocus.keys.where((id) => !live.contains(id)).toList()) {
      _altFocus.remove(id)!.dispose();
    }
    for (final id in _focus.keys.where((id) => !live.contains(id)).toList()) {
      _focus.remove(id)!.dispose();
    }
    for (final id in _codeFocus.keys.where((id) => !live.contains(id)).toList()) {
      _codeFocus.remove(id)!.dispose();
    }
    for (final id in _codes.keys.where((id) => !live.contains(id)).toList()) {
      _codes.remove(id)!.dispose();
      _detectTimers.remove(id)?.cancel();
      _wrap.remove(id);
      _autoLanguage.remove(id);
    }
  }

  void _moveCaret(Caret? caret) {
    if (caret == null) return;
    setState(() {
      _reveal(caret.block);
      _pending = caret;
    });
  }

  /// Applies [_pending] to the block that now owns it, after it has been built.
  void _applyPending(int index) {
    final pending = _pending;
    if (pending == null || pending.block != index || index >= doc.length) return;
    _pending = null;
    final block = doc[index];
    final node = _focusFor(block);
    final text = _textFor(block);
    final cell = _pendingCell;
    _pendingCell = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (cell != null && cell.$1 == block.id) {
        final table = _tableKeyFor(block).currentState;
        if (table != null) {
          table.focusChange(cell.$2);
          return;
        }
      }
      // A field that already has focus keeps its caret: setting the selection
      // would also send the field's text back to the platform, over any
      // typing still on its way in.
      if (node.hasFocus) return;
      if (block.kind == BlockKind.table) {
        final table = _tableKeyFor(block).currentState;
        if (table == null) {
          node.requestFocus();
        } else if (pending.offset == 0) {
          table.focusFirst();
        } else {
          table.focusLast();
        }
        return;
      }
      node.requestFocus();
      if (_isCode(block)) {
        final code = _codeFor(block);
        if (pending.offset == 0) {
          code.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
        } else {
          final last = code.codeLines.length - 1;
          code.selection = CodeLineSelection.collapsed(index: last, offset: code.codeLines[last].text.length);
        }
        return;
      }
      final current = doc.indexOf(block.id);
      final editable = block.isText || block.kind == BlockKind.code || block.kind == BlockKind.raw;
      if (editable && current >= 0 && text.text == doc[current].text) {
        text.selection = TextSelection.collapsed(offset: pending.offset.clamp(0, text.text.length));
      }
    });
  }

  // ---- key handling ----------------------------------------------------------

  KeyEventResult _onKey(Block block, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final range = _range;
    if (range != null) {
      final result = _onRangeKey(range, event);
      if (result != null) return result;
    }
    // Callbacks may run before the list has rebuilt, so find the block now.
    final index = doc.indexOf(block.id);
    if (index < 0) return KeyEventResult.ignored;
    block = doc[index];
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final shift = keys.isShiftPressed;

    // Ctrl+A selects the block's text; once it is all selected, the page.
    if (ctrl && !shift && key == LogicalKeyboardKey.keyA && hasInlineText(block) && doc.length > 1) {
      final sel = _textFor(block).selection;
      if (block.text.isEmpty || (sel.isValid && sel.start == 0 && sel.end == block.text.length)) {
        _setRange(BlockRange((block: 0, offset: 0), (block: doc.length - 1, offset: doc[doc.length - 1].text.length)));
        _positionRangeToolbar();
        return KeyEventResult.handled;
      }
    }
    if (widget.readOnly) return KeyEventResult.ignored;

    final slash = _slash;
    if (slash != null && slash.blockId == block.id) {
      final items = slash.items;
      if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
        if (items.isNotEmpty) {
          final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
          setState(() => slash.selected = (slash.selected + step) % items.length);
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.tab) {
        _applySlash(index, block, slash.selected);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _closeSlash();
        return KeyEventResult.handled;
      }
    }

    if (ctrl && key == LogicalKeyboardKey.keyZ) {
      _history(redo: shift);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyY) {
      _history(redo: true);
      return KeyEventResult.handled;
    }
    if (ctrl && (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) && shift) {
      final to = index + (key == LogicalKeyboardKey.arrowUp ? -1 : 1);
      final offset = _texts[block.id]?.selection.extentOffset ?? 0;
      if (to >= 0 && to < doc.length) {
        doc.move(index, to);
        _moveCaret((block: to, offset: offset));
      }
      return KeyEventResult.handled;
    }

    if (_isCode(block)) return _onCodeKey(index, block, key, ctrl: ctrl, shift: shift);

    if (ctrl && block.isText && !doc.plain) {
      final marker = switch (key) {
        LogicalKeyboardKey.keyB => '**',
        LogicalKeyboardKey.keyI => '_',
        LogicalKeyboardKey.keyE => '`',
        LogicalKeyboardKey.keyX when shift => '~~',
        _ => null,
      };
      if (marker != null) {
        _toggleInline(index, block, marker);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyK) {
        _insertLink(index, block);
        return KeyEventResult.handled;
      }
    }

    // A table handles its own keys (Tab, Enter, arrows between cells).
    if (block.kind == BlockKind.table) return KeyEventResult.ignored;
    final editable = block.isText || block.kind == BlockKind.raw;
    if (!editable) return _onNonTextKey(index, block, key);

    final text = _textFor(block);
    final sel = text.selection;
    final value = text.text;

    // Enter is not handled here: the newline arrives with the typed text (see
    // [_onChanged]), which keeps it in order with characters still in flight
    // from the platform's text input.

    // Shift+arrow past the first or last line carries the selection on into
    // the next block.
    if (shift && !ctrl && sel.isValid && _startRangeByKey(index, block, key, sel)) return KeyEventResult.handled;

    if (key == LogicalKeyboardKey.backspace && sel.isValid && sel.isCollapsed && sel.start == 0) {
      if (block.isList && block.level > 0) {
        doc.indent(index, -1, caret: (block: index, offset: 0));
      } else if (block.isText && block.kind != BlockKind.paragraph) {
        doc.convert(index, BlockKind.paragraph, caret: (block: index, offset: 0));
      } else if (block.kind == BlockKind.code && !doc.plain && value.isEmpty) {
        doc.convert(index, BlockKind.paragraph, caret: (block: index, offset: 0));
      } else if (block.isText) {
        final caret = doc.mergeWithPrevious(index);
        _moveCaret(caret ?? (index > 0 ? (block: index - 1, offset: doc[index - 1].text.length) : null));
        return KeyEventResult.handled;
      } else {
        return KeyEventResult.ignored;
      }
      _moveCaret((block: index, offset: 0));
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.delete &&
        block.isText &&
        sel.isValid &&
        sel.isCollapsed &&
        sel.start == value.length) {
      if (index + 1 < doc.length && doc[index + 1].isText) {
        final caret = doc.mergeWithPrevious(index + 1);
        _moveCaret(caret);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.tab) {
      if (block.isList) {
        final offset = sel.isValid ? sel.extentOffset : 0;
        doc.indent(index, shift ? -1 : 1, caret: (block: index, offset: offset));
        _moveCaret((block: index, offset: offset));
        return KeyEventResult.handled;
      }
      if (block.kind == BlockKind.code && sel.isValid && !shift) {
        final next = value.replaceRange(sel.start, sel.end, '  ');
        text.expectChange(value, next);
        text.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: sel.start + 2));
        doc.updateText(index, next);
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled; // keep focus in the editor
    }

    if (key == LogicalKeyboardKey.arrowUp && !shift && sel.isValid && sel.isCollapsed) {
      if (!value.substring(0, sel.extentOffset).contains('\n') && index > 0) {
        _moveCaret((block: index - 1, offset: doc[index - 1].text.length));
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowDown && !shift && sel.isValid && sel.isCollapsed) {
      if (!value.substring(sel.extentOffset).contains('\n') && index + 1 < doc.length) {
        _moveCaret((block: index + 1, offset: 0));
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowLeft &&
        !shift &&
        sel.isValid &&
        sel.isCollapsed &&
        sel.start == 0 &&
        index > 0) {
      _moveCaret((block: index - 1, offset: doc[index - 1].text.length));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight &&
        !shift &&
        sel.isValid &&
        sel.isCollapsed &&
        sel.start == value.length &&
        index + 1 < doc.length) {
      _moveCaret((block: index + 1, offset: 0));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Keys the editor handles around a code space; the code editor itself
  /// handles typing, Tab, Enter, selection and its own shortcuts.
  KeyEventResult _onCodeKey(int index, Block block, LogicalKeyboardKey key, {required bool ctrl, required bool shift}) {
    final code = _codeFor(block);
    if (ctrl && (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter)) {
      // Ctrl+Enter leaves the code space on a new paragraph below it.
      doc.insert(index + 1, Block(kind: BlockKind.paragraph));
      _moveCaret((block: index + 1, offset: 0));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace && !doc.plain && code.text.isEmpty) {
      doc.convert(index, BlockKind.paragraph, caret: (block: index, offset: 0));
      _moveCaret((block: index, offset: 0));
      return KeyEventResult.handled;
    }
    if (shift || ctrl) return KeyEventResult.ignored;
    final arrows = {
      LogicalKeyboardKey.arrowUp: AxisDirection.up,
      LogicalKeyboardKey.arrowDown: AxisDirection.down,
      LogicalKeyboardKey.arrowLeft: AxisDirection.left,
      LogicalKeyboardKey.arrowRight: AxisDirection.right,
    };
    final direction = arrows[key];
    if (direction != null && _leaveCode(block, direction)) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  // ---- code spaces -----------------------------------------------------------

  /// Moves the focus to the block before or after a code space when the
  /// caret is on its first or last line (up / down) or at its first or last
  /// character (left / right). Returns false when the caret stays inside.
  /// Moves the caret to the block before (up / left) or after (down / right).
  bool _leaveBlock(Block block, AxisDirection direction) {
    final index = doc.indexOf(block.id);
    if (index < 0) return false;
    final back = direction == AxisDirection.up || direction == AxisDirection.left;
    if (back && index > 0) {
      _moveCaret((block: index - 1, offset: doc[index - 1].text.length));
      return true;
    }
    if (!back && index + 1 < doc.length) {
      _moveCaret((block: index + 1, offset: 0));
      return true;
    }
    return false;
  }

  Widget _tableBlock(int index, Block block) => TableBlockView(
        key: _tableKeyFor(block),
        block: block,
        focusNode: _focusFor(block),
        readOnly: widget.readOnly,
        onChanged: (markdown, {structural = false}) {
          final i = doc.indexOf(block.id);
          if (i < 0 || doc[i].text == markdown) return;
          if (structural) {
            doc.replace(i, doc[i].copyWith(text: markdown)); // one undo step each
          } else {
            doc.updateText(i, markdown);
          }
        },
        onMoveOut: (direction) => _leaveBlock(block, direction),
        onDelete: () {
          final i = doc.indexOf(block.id);
          if (i >= 0) _moveCaret(doc.remove(i));
        },
      );

  bool _leaveCode(Block block, AxisDirection direction) {
    final index = doc.indexOf(block.id);
    if (index < 0) return false;
    final code = _codeFor(block);
    final sel = code.selection;
    if (!sel.isCollapsed) return false;
    final lastLine = code.codeLines.length - 1;
    final atStart = sel.extentIndex == 0 && sel.extentOffset == 0;
    final atEnd = sel.extentIndex == lastLine && sel.extentOffset == code.codeLines[lastLine].text.length;
    final back = direction == AxisDirection.up && sel.extentIndex == 0 || direction == AxisDirection.left && atStart;
    final forward =
        direction == AxisDirection.down && sel.extentIndex == lastLine || direction == AxisDirection.right && atEnd;
    if (back && index > 0) {
      _moveCaret((block: index - 1, offset: doc[index - 1].text.length));
      return true;
    }
    if (forward && index + 1 < doc.length) {
      _moveCaret((block: index + 1, offset: 0));
      return true;
    }
    return false;
  }

  void _onCodeChanged(Block block) {
    final index = doc.indexOf(block.id);
    if (index < 0) return;
    final code = _codeFor(block);
    final text = code.text;
    _reportCodeSelection(index, block, code);
    if (text == doc[index].text) return;
    doc.updateText(index, text);
    final current = doc[index];
    if (current.language == null || _autoLanguage.contains(block.id)) _scheduleDetect(block.id);
  }

  void _scheduleDetect(int id) {
    _detectTimers[id]?.cancel();
    _detectTimers[id] = Timer(detectDelay, () {
      _detectTimers.remove(id);
      if (!mounted) return;
      _detectNow(id);
    });
  }

  /// Guesses the language of a code space whose language was not chosen by
  /// hand, and writes it into the fence.
  void _detectNow(int id) {
    final index = doc.indexOf(id);
    if (index < 0) return;
    final block = doc[index];
    if (block.language != null && !_autoLanguage.contains(id)) return;
    final guess = detectLanguage(block.text);
    final next = guess?.id;
    if (next == block.language) return;
    _autoLanguage.add(id);
    doc.replace(index, next == null ? block.copyWith(clearLanguage: true) : block.copyWith(language: next));
  }

  void _setLanguage(Block block, CodeLanguage? language) {
    final index = doc.indexOf(block.id);
    if (index < 0) return;
    if (language == null) {
      _autoLanguage.add(block.id);
      final guess = detectLanguage(doc[index].text);
      doc.replace(
          index, guess == null ? doc[index].copyWith(clearLanguage: true) : doc[index].copyWith(language: guess.id));
    } else {
      _autoLanguage.remove(block.id);
      doc.replace(index, doc[index].copyWith(language: language.id));
    }
    _focusFor(block).requestFocus();
  }

  /// Offsets into the block's text for the code editor's line/column selection.
  void _reportCodeSelection(int index, Block block, CodeLineEditingController code) {
    if (!_focusFor(block).hasFocus) return;
    int offsetOf(int line, int column) {
      var offset = 0;
      final lines = code.codeLines;
      for (var i = 0; i < line && i < lines.length; i++) {
        offset += lines[i].text.length + 1;
      }
      return offset + column;
    }

    final sel = code.selection;
    widget.controller.setSelection(
      index,
      TextSelection(
        baseOffset: offsetOf(sel.baseIndex, sel.baseOffset),
        extentOffset: offsetOf(sel.extentIndex, sel.extentOffset),
      ),
    );
  }

  /// The file of an image block when it exists next to the page.
  File? _imageFile(Block block) {
    final page = widget.controller.path;
    if (page == null || block.url.isEmpty || block.url.contains('://')) return null;
    final rel = p.posix.join(p.posix.dirname(page), Uri.decodeFull(block.url));
    final f = File(widget.controller.workspace.resolve(rel));
    return f.existsSync() ? f : null;
  }

  bool _captionShown(Block block) => block.caption.isNotEmpty || _captions.contains(block.id);

  /// Row heights for the current document, width and options, so a scroll
  /// frame reads a number per row instead of measuring. Rebuilt in one pass
  /// when any of those change; unchanged blocks keep their measured height.
  Float64List? _extents;
  int _extentsVersion = -1;
  double _extentsWidth = -1;
  TextScaler? _extentsScale;
  int _extentsOptions = -1;
  int _options = 0; // bumped when wrap, caption or collapsed state changes

  // ---- sections ---------------------------------------------------------------

  /// Headings whose section is folded away (by block id).
  final _collapsed = <int>{};
  List<bool>? _hidden;
  int _hiddenVersion = -1;
  int _hiddenOptions = -1;

  /// The index after the last block of the heading's section: everything up
  /// to the next heading of the same or a higher level.
  int _sectionEnd(int index) {
    final level = doc[index].level;
    var end = index + 1;
    while (end < doc.length && !(doc[end].kind == BlockKind.heading && doc[end].level <= level)) {
      end++;
    }
    return end;
  }

  /// Which rows are inside a folded section, per document version.
  List<bool> _hiddenRows() {
    if (_hidden != null &&
        _hidden!.length == doc.length &&
        _hiddenVersion == doc.version &&
        _hiddenOptions == _options) {
      return _hidden!;
    }
    final hidden = List<bool>.filled(doc.length, false);
    if (_collapsed.isNotEmpty) {
      for (var i = 0; i < doc.length; i++) {
        if (doc[i].kind != BlockKind.heading || !_collapsed.contains(doc[i].id)) continue;
        for (var j = i + 1; j < _sectionEnd(i); j++) {
          hidden[j] = true;
        }
      }
    }
    _hidden = hidden;
    _hiddenVersion = doc.version;
    _hiddenOptions = _options;
    return hidden;
  }

  bool _isHidden(int index) => _collapsed.isNotEmpty && index < doc.length && _hiddenRows()[index];

  void _toggleSection(Block block) {
    final index = doc.indexOf(block.id);
    if (index < 0 || block.kind != BlockKind.heading) return;
    setState(() {
      if (!_collapsed.remove(block.id)) {
        _collapsed.add(block.id);
        // The caret cannot stay in a folded block.
        final focused = widget.controller.focusedBlock;
        if (focused > index && focused < _sectionEnd(index)) _pending = (block: index, offset: block.text.length);
      }
      _options++;
    });
  }

  /// Unfolds every section that hides [index].
  void _reveal(int index) {
    if (_collapsed.isEmpty || !_isHidden(index)) return;
    for (var i = index - 1; i >= 0; i--) {
      if (doc[i].kind == BlockKind.heading && _collapsed.contains(doc[i].id) && _sectionEnd(i) > index) {
        _collapsed.remove(doc[i].id);
      }
    }
    _options++;
  }

  // ---- drag and drop ------------------------------------------------------------

  /// The block being dragged by its handle, and where it would land.
  int? _dragId;
  ({int index, bool above})? _dropAt;
  Timer? _autoScroll;

  void _onDragStarted(Block block) {
    final index = doc.indexOf(block.id);
    if (index >= 0 && _collapsed.remove(block.id)) _options++; // a folded section moves as blocks, not as one
    setState(() => _dragId = block.id);
  }

  /// Scrolls the list while the pointer is near its top or bottom edge.
  void _onDragUpdate(Offset pointer) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !_scroll.hasClients) return;
    final local = box.globalToLocal(pointer);
    const zone = 48.0;
    double speed = 0;
    if (local.dy < zone) speed = -(zone - local.dy) / 3;
    if (local.dy > box.size.height - zone) speed = (local.dy - (box.size.height - zone)) / 3;
    if (speed == 0) {
      _autoScroll?.cancel();
      _autoScroll = null;
      return;
    }
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      position.jumpTo((position.pixels + speed).clamp(0.0, position.maxScrollExtent));
    });
  }

  void _onDragEnd() {
    _autoScroll?.cancel();
    _autoScroll = null;
    if (!mounted) return;
    setState(() {
      _dragId = null;
      _dropAt = null;
    });
  }

  void _updateDrop(int index, Offset pointer, BuildContext rowContext) {
    final box = rowContext.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(pointer);
    final at = (index: index, above: index < doc.length && local.dy < box.size.height / 2);
    if (_dropAt != at) setState(() => _dropAt = at);
  }

  void _drop(int id, int index, bool above) {
    final from = doc.indexOf(id);
    if (from < 0) return;
    var to = above ? index : index + 1;
    if (to > from) to--;
    to = to.clamp(0, doc.length - 1);
    if (to != from) {
      doc.move(from, to);
      _moveCaret((block: to, offset: 0));
    }
    _onDragEnd();
  }

  /// What follows the pointer while a block is dragged: its first line.
  Widget _dragFeedback(StackPalette palette, Block block) {
    var text = block.text.split('\n').first.trim();
    if (text.isEmpty) text = block.kind == BlockKind.image ? block.url : block.kind.name;
    if (text.length > 60) text = '${text.substring(0, 60)}…';
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: palette.panel,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: palette.accentA),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(60), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Text(text,
            style: TextStyle(color: palette.text, fontSize: StackType.menu),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Float64List _extentsFor(BlockMetrics metrics, double width) {
    if (_extents != null &&
        _extents!.length == doc.length &&
        _extentsVersion == doc.version &&
        _extentsWidth == width &&
        _extentsScale == metrics.textScaler &&
        _extentsOptions == _options) {
      return _extents!;
    }
    final extents = Float64List(doc.length);
    final hidden = _collapsed.isEmpty ? null : _hiddenRows();
    for (var i = 0; i < doc.length; i++) {
      extents[i] = hidden != null && hidden[i] ? 0 : _rowHeight(metrics, i, width);
    }
    _extents = extents;
    _extentsVersion = doc.version;
    _extentsWidth = width;
    _extentsScale = metrics.textScaler;
    _extentsOptions = _options;
    return extents;
  }

  /// The row's height, computed before it is built so the list can give
  /// every row a fixed extent (see [BlockMetrics]).
  double _rowHeight(BlockMetrics metrics, int index, double width) {
    final block = doc[index];
    final previous = index > 0 ? doc[index - 1] : null;
    final wrap = _wrap[block.id] ?? false;
    final caption = block.kind == BlockKind.code && _captionShown(block);
    final gap = BlockMetrics.gapAbove(block, previous);
    final cached = _heights[block.id];
    if (cached != null &&
        identical(cached.block, block) &&
        cached.width == width &&
        cached.scale == metrics.textScaler &&
        cached.wrap == wrap &&
        cached.caption == caption) {
      return gap + cached.body;
    }
    final body = metrics.bodyHeight(block, width, wrap: wrap, caption: caption);
    _heights[block.id] = _Measured(block, width, metrics.textScaler, wrap, caption, body);
    return gap + body;
  }

  Widget _codeBlock(int index, Block block) {
    final code = _codeFor(block);
    if (code.text != block.text) code.text = block.text;
    return CodeBlockView(
      key: ValueKey('code-${block.id}'),
      block: block,
      controller: code,
      focusNode: _focusFor(block),
      readOnly: widget.readOnly,
      plain: doc.plain,
      wrap: _wrap[block.id] ?? false,
      autoDetected: _autoLanguage.contains(block.id),
      onChanged: (_) => _onCodeChanged(block),
      onLanguage: (language) => _setLanguage(block, language),
      onCaption: (caption) {
        final i = doc.indexOf(block.id);
        if (i >= 0 && doc[i].caption != caption) doc.replace(i, doc[i].copyWith(caption: caption));
      },
      onWrap: (wrap) => setState(() {
        _wrap[block.id] = wrap;
        _options++;
      }),
      onDelete: () {
        final i = doc.indexOf(block.id);
        if (i >= 0) _moveCaret(doc.remove(i));
      },
      onBackspaceEmpty: () {
        final i = doc.indexOf(block.id);
        if (i < 0 || doc.plain) return;
        doc.convert(i, BlockKind.paragraph, caret: (block: i, offset: 0));
        _moveCaret((block: i, offset: 0));
      },
      onMoveOut: (direction) => _leaveCode(block, direction),
      showCaption: _captionShown(block),
      onShowCaption: () => setState(() {
        _captions.add(block.id);
        _options++;
      }),
    );
  }

  KeyEventResult _onNonTextKey(int index, Block block, LogicalKeyboardKey key) {
    if (block.kind == BlockKind.image && _altFocusFor(block).hasFocus) {
      // Typing in the description: only Enter and Up / Down leave the field.
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
        doc.insert(index + 1, Block(kind: BlockKind.paragraph));
        _moveCaret((block: index + 1, offset: 0));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp && index > 0) {
        _moveCaret((block: index - 1, offset: doc[index - 1].text.length));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown && index + 1 < doc.length) {
        _moveCaret((block: index + 1, offset: 0));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _moveCaret(doc.remove(index));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      doc.insert(index + 1, Block(kind: BlockKind.paragraph));
      _moveCaret((block: index + 1, offset: 0));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) _moveCaret((block: index - 1, offset: doc[index - 1].text.length));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
      if (index + 1 < doc.length) _moveCaret((block: index + 1, offset: 0));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- inline formatting ----------------------------------------------------

  /// Wraps the selection in [marker] (`**`, `_`, `` ` ``, `~~`), or removes the
  /// markers when the selection already has them, inside or just outside it.
  /// With no selection the markers are inserted and the caret goes between.
  void _toggleInline(int index, Block block, String marker) {
    final text = _textFor(block);
    final value = text.text;
    final sel = text.selection.isValid ? text.selection : TextSelection.collapsed(offset: value.length);
    final result = toggleMarker(value, sel, marker);
    text.expectChange(value, result.text);
    text.value = TextEditingValue(text: result.text, selection: result.selection);
    doc.updateText(index, result.text, caret: (block: index, offset: result.selection.extentOffset));
  }

  /// Turns the selection into a Markdown link with the URL part selected;
  /// on a Markdown link already, removes it and keeps its label (Bug 2).
  void _insertLink(int index, Block block) {
    final text = _textFor(block);
    final value = text.text;
    final sel = text.selection.isValid ? text.selection : TextSelection.collapsed(offset: value.length);
    final existing = linkAt(value, sel.start);
    if (existing != null && existing.isMarkdown && sel.end <= existing.end) {
      final next = value.replaceRange(existing.start, existing.end, existing.label);
      final after = TextSelection(baseOffset: existing.start, extentOffset: existing.start + existing.label.length);
      text.expectChange(value, next);
      text.value = TextEditingValue(text: next, selection: after);
      doc.updateText(index, next, caret: (block: index, offset: after.extentOffset));
      return;
    }
    final selected = sel.isCollapsed ? '' : value.substring(sel.start, sel.end);
    // A selected URL becomes the destination, with the label to fill in.
    final selectedUrl = isUrl(selected);
    final label = selected.isEmpty ? 'text' : (selectedUrl ? 'text' : selected);
    final url = selectedUrl ? selected.trim() : 'url';
    final next = value.replaceRange(sel.start, sel.end, '[$label]($url)');
    final TextSelection after;
    if (selectedUrl) {
      after = TextSelection(baseOffset: sel.start + 1, extentOffset: sel.start + 1 + label.length);
    } else {
      final urlStart = sel.start + label.length + 3;
      after = TextSelection(baseOffset: urlStart, extentOffset: urlStart + 3);
    }
    text.expectChange(value, next);
    text.value = TextEditingValue(text: next, selection: after);
    doc.updateText(index, next, caret: (block: index, offset: after.extentOffset));
  }

  /// Ctrl+click (or any click on a read-only page) on a link opens it.
  Future<void> _openLinkAt(Block block, int offset) async {
    final link = linkAt(block.text, offset);
    if (link == null) return;
    final problem = await openLink(link.url);
    if (problem != null && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  // ---- typing --------------------------------------------------------------

  static final _shortcuts = <RegExp, (BlockKind, int)>{
    RegExp(r'^(#{1,6}) $'): (BlockKind.heading, 0),
    RegExp(r'^[-*+] $'): (BlockKind.bullet, 0),
    RegExp(r'^1[.)] $'): (BlockKind.numbered, 0),
    RegExp(r'^(?:[-*+] )?\[[ xX]?\] $'): (BlockKind.todo, 0),
    RegExp(r'^> $'): (BlockKind.quote, 0),
    RegExp(r'^```$'): (BlockKind.code, 0),
    RegExp(r'^---$'): (BlockKind.divider, 0),
  };

  void _onChanged(Block block, String value) {
    final index = doc.indexOf(block.id);
    if (index < 0) return;
    block = doc[index];
    final text = _textFor(block);
    final fixed = text.reconcile(text.value);
    if (fixed.text != value) {
      // A late update from the platform, moved onto the text the editor set.
      value = fixed.text;
      if (_pending?.block == index) _pending = null;
    }
    final sel = text.selection;
    if (block.isText && !doc.plain && _pasteRangeClip(index, block, value, sel)) return;
    if (block.isText && !doc.plain && _pasteTable(index, block, value, sel)) return;
    if (block.isText && !doc.plain) _trackSlash(index, block, value, sel);
    if (block.isText && _splitOnNewline(index, block, value, sel)) return;
    // A URL pasted over selected words links them (Bug 2). A URL pasted on
    // its own stays as typed; bare URLs are shown and opened as links.
    if (block.isText && !doc.plain) {
      final paste = pastedUrl(block.text, value);
      if (paste != null &&
          paste.removed.trim().isNotEmpty &&
          !paste.removed.contains('\n') &&
          linkAt(block.text, paste.start)?.isMarkdown != true) {
        final linked = '[${paste.removed}](${paste.url.trim()})';
        final next = value.replaceRange(paste.start, paste.start + paste.url.length, linked);
        final after = TextSelection.collapsed(offset: paste.start + linked.length);
        text.expectChange(value, next);
        text.value = TextEditingValue(text: next, selection: after);
        doc.updateText(index, next, caret: (block: index, offset: after.extentOffset));
        return;
      }
    }
    // Markdown shortcuts turn a paragraph into another block as you type.
    if (block.kind == BlockKind.paragraph && !doc.plain && sel.isCollapsed && sel.extentOffset == value.length) {
      for (final entry in _shortcuts.entries) {
        final m = entry.key.firstMatch(value);
        if (m == null) continue;
        final kind = entry.value.$1;
        text.expectChange(value, '');
        text.value = const TextEditingValue();
        switch (kind) {
          case BlockKind.heading:
            doc.convert(index, kind, level: m.group(1)!.length);
          case BlockKind.code:
            doc.convert(index, kind);
          case BlockKind.divider:
            doc.replace(index, Block(id: block.id, kind: BlockKind.divider, gapBefore: block.gapBefore));
            doc.insert(index + 1, Block(kind: BlockKind.paragraph));
            _moveCaret((block: index + 1, offset: 0));
            return;
          default:
            doc.convert(index, kind);
        }
        doc.updateText(index, '');
        _moveCaret((block: index, offset: 0));
        return;
      }
    }
    doc.updateText(index, value, caret: (block: index, offset: sel.extentOffset));
  }

  /// A single newline typed into a text block ends it: the text after the
  /// caret moves to a new block. Shift+Enter keeps a soft line break, and a
  /// pasted multi-line text keeps its breaks.
  bool _splitOnNewline(int index, Block block, String value, TextSelection sel) {
    final added = '\n'.allMatches(value).length - '\n'.allMatches(block.text).length;
    if (added != 1 || !sel.isValid || !sel.isCollapsed) return false;
    final at = sel.extentOffset - 1;
    if (at < 0 || at >= value.length || value[at] != '\n') return false;
    if (HardwareKeyboard.instance.isShiftPressed) return false;
    final head = value.substring(0, at);
    final tail = value.substring(at + 1);
    final text = _textFor(block);
    if (block.isList && head.isEmpty && tail.isEmpty) {
      // Enter on an empty item ends the list (outdents first when nested).
      text.expectChange(value, '');
      text.value = const TextEditingValue(selection: TextSelection.collapsed(offset: 0));
      if (block.level > 0) {
        doc.indent(index, -1, caret: (block: index, offset: 0));
      } else {
        doc.convert(index, BlockKind.paragraph, caret: (block: index, offset: 0));
      }
      _moveCaret((block: index, offset: 0));
      return true;
    }
    // The field keeps the caret and becomes the second block, so set its text
    // first: keys typed before the next frame land in the right place.
    text.expectChange(value, tail);
    text.value = TextEditingValue(text: tail, selection: const TextSelection.collapsed(offset: 0));
    doc.updateText(index, head + tail);
    _moveCaret(doc.split(index, head.length));
    return true;
  }

  void _reportSelection(Block block) {
    final index = doc.indexOf(block.id);
    if (index < 0) return;
    if (_isCode(block)) {
      _reportCodeSelection(index, block, _codeFor(block));
      return;
    }
    final text = _textFor(block);
    final focused = _focusFor(block).hasFocus;
    if (focused) widget.controller.setSelection(index, text.selection);
    if (_range != null) {
      // The range has its own toolbar; the field's own selection is hidden.
    } else if (block.isText && !doc.plain && focused && !text.selection.isCollapsed && !widget.readOnly) {
      _positionToolbar(block);
    } else if (_toolbar?.blockId == block.id) {
      _closeToolbar();
    }
    final slash = _slash;
    if (slash != null && slash.blockId == block.id) {
      if (!focused) {
        _closeSlash();
      } else if (!text.selection.isCollapsed || text.selection.extentOffset <= slash.offset) {
        // The caret left the query.
        _closeSlash();
      }
    }
  }

  // ---- selection across blocks ------------------------------------------------

  /// A selection that spans blocks, while there is one. Each block's field
  /// selects only inside itself (and paints its selection only while it has
  /// focus), so the editor keeps this one, paints it and handles its keys.
  BlockRange? _range;

  /// The document version [_range] was made for; any other edit ends it.
  int _rangeVersion = -1;

  /// Where the mouse button went down in a text field, while it is held.
  Caret? _press;
  Offset? _lastPointer;
  Timer? _selectScroll;
  double _selectSpeed = 0;

  /// The last Markdown copied from a range, so pasting it brings back blocks.
  String? _rangeClip;
  Color _selectionColor = const Color(0x664488FF);

  final _bodyKeys = <int, GlobalKey>{};
  GlobalKey _bodyKeyFor(Block block) => _bodyKeys.putIfAbsent(block.id, GlobalKey.new);

  /// The selection across blocks, for tests.
  BlockRange? get range => _range;

  void _setRange(BlockRange? range) {
    _rangeVersion = doc.version;
    if (range == _range) return;
    setState(() => _range = range);
    final toolbar = _toolbar;
    if (toolbar != null && (range == null) == toolbar.range) _closeToolbar();
  }

  RenderEditable? _editableFor(Block block) => _findEditable(_fieldKeys[block.id]?.currentContext?.findRenderObject());

  /// The text block whose field is under [global], and the offset there.
  Caret? _fieldAt(Offset global) {
    for (final entry in _fieldKeys.entries) {
      final index = doc.indexOf(entry.key);
      if (index < 0 || !hasInlineText(doc[index]) || _isHidden(index)) continue;
      final editable = _editableFor(doc[index]);
      if (editable == null || !editable.attached || !editable.hasSize) continue;
      final local = editable.globalToLocal(global);
      if (!(Offset.zero & editable.size).contains(local)) continue;
      return (block: index, offset: editable.getPositionForPoint(global).offset);
    }
    return null;
  }

  /// The block nearest to [global] among the rows on screen, and the offset
  /// in its text closest to it.
  Caret? _hitAt(Offset global) {
    var best = -1;
    var bestDistance = double.infinity;
    for (final entry in _bodyKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final index = doc.indexOf(entry.key);
      if (index < 0 || _isHidden(index)) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      final distance = global.dy < top ? top - global.dy : (global.dy > bottom ? global.dy - bottom : 0.0);
      if (distance < bestDistance || (distance == bestDistance && index > best)) {
        best = index;
        bestDistance = distance;
      }
    }
    if (best < 0) return null;
    final block = doc[best];
    final editable = hasInlineText(block) ? _editableFor(block) : null;
    if (editable != null && editable.attached && editable.hasSize) {
      return (block: best, offset: editable.getPositionForPoint(global).offset);
    }
    final box = _bodyKeys[block.id]!.currentContext!.findRenderObject() as RenderBox;
    final middle = box.localToGlobal(Offset.zero).dy + box.size.height / 2;
    return (block: best, offset: global.dy < middle ? 0 : block.text.length);
  }

  /// The caret (the selection's fixed end) of the focused text block.
  Caret? _caretNow() {
    final i = widget.controller.focusedBlock;
    if (i < 0 || i >= doc.length || !hasInlineText(doc[i]) || !_focusFor(doc[i]).hasFocus) return null;
    final sel = _textFor(doc[i]).selection;
    return sel.isValid ? (block: i, offset: sel.baseOffset) : null;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse || event.buttons != kPrimaryMouseButton) return;
    final at = _fieldAt(event.position);
    if (at != null && HardwareKeyboard.instance.isShiftPressed) {
      // Shift+click in another block selects from the caret to there.
      final from = _range?.anchor ?? _caretNow();
      if (from != null && from.block != at.block) {
        _press = from;
        _setRange(BlockRange(from, at));
        _positionRangeToolbar();
        return;
      }
    }
    _press = at;
    if (_range != null) _setRange(null);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_press == null || event.buttons != kPrimaryMouseButton) return;
    _lastPointer = event.position;
    _extendTo(event.position);
    _autoScrollSelection(event.position);
  }

  void _onPointerEnd(PointerEvent event) {
    _press = null;
    _lastPointer = null;
    _selectScroll?.cancel();
    _selectScroll = null;
    if (_range != null) _positionRangeToolbar();
  }

  /// Moves the loose end of the drag to the block under [global]. Back inside
  /// the block where it started, the field's own selection takes over again.
  void _extendTo(Offset global) {
    final press = _press;
    if (press == null || !mounted) return;
    final at = _hitAt(global);
    if (at == null) return;
    _setRange(at.block == press.block ? null : BlockRange(press, at));
  }

  /// Scrolls the page while a selection is dragged near its top or bottom.
  void _autoScrollSelection(Offset pointer) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !_scroll.hasClients) return;
    final local = box.globalToLocal(pointer);
    const zone = 40.0;
    double speed = 0;
    if (local.dy < zone) speed = -(zone - local.dy) / 2;
    if (local.dy > box.size.height - zone) speed = (local.dy - (box.size.height - zone)) / 2;
    _selectSpeed = speed;
    if (speed == 0) {
      _selectScroll?.cancel();
      _selectScroll = null;
      return;
    }
    _selectScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || !_scroll.hasClients || _press == null) return;
      final position = _scroll.position;
      position.jumpTo((position.pixels + _selectSpeed).clamp(0.0, position.maxScrollExtent));
      // The rows are where they scrolled to after the next layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final p = _lastPointer;
        if (p != null) _extendTo(p);
      });
    });
  }

  /// One line up or down from [from]: within the block while it has more
  /// lines, else onto the nearest line of the block before or after, at the
  /// same distance from the left. Null at the top or bottom of the page.
  Caret? _lineStep(Caret from, {required bool down}) {
    final block = doc[from.block];
    final editable = hasInlineText(block) ? _editableFor(block) : null;
    double? x;
    if (editable != null && editable.attached && editable.hasSize) {
      final caret = editable.getLocalRectForCaret(TextPosition(offset: from.offset.clamp(0, block.text.length)));
      final y = down ? caret.bottom + caret.height / 2 : caret.top - caret.height / 2;
      if (y >= 0 && y <= editable.size.height) {
        return (
          block: from.block,
          offset: editable.getPositionForPoint(editable.localToGlobal(Offset(caret.left, y))).offset
        );
      }
      x = editable.localToGlobal(caret.topLeft).dx;
    }
    var to = from.block + (down ? 1 : -1);
    while (to >= 0 && to < doc.length && _isHidden(to)) {
      to += down ? 1 : -1;
    }
    if (to < 0 || to >= doc.length) {
      if (!hasInlineText(block)) return null;
      final edge = down ? block.text.length : 0;
      return edge == from.offset ? null : (block: from.block, offset: edge);
    }
    final target = doc[to];
    final next = hasInlineText(target) ? _editableFor(target) : null;
    if (x != null && next != null && next.attached && next.hasSize) {
      final topLeft = next.localToGlobal(Offset.zero);
      final y = down ? topLeft.dy + 2 : topLeft.dy + next.size.height - 2;
      return (block: to, offset: next.getPositionForPoint(Offset(x, y)).offset);
    }
    return (block: to, offset: down ? 0 : target.text.length);
  }

  /// One character left or right of [from], across into the next block.
  Caret? _charStep(Caret from, {required bool forward}) {
    final block = doc[from.block];
    if (hasInlineText(block)) {
      if (forward && from.offset < block.text.length) return (block: from.block, offset: from.offset + 1);
      if (!forward && from.offset > 0) return (block: from.block, offset: from.offset - 1);
    }
    var to = from.block + (forward ? 1 : -1);
    while (to >= 0 && to < doc.length && _isHidden(to)) {
      to += forward ? 1 : -1;
    }
    if (to < 0 || to >= doc.length) return null;
    return (block: to, offset: forward ? 0 : doc[to].text.length);
  }

  /// Shift+Up / Down on the first or last line of a block, or Shift+Left /
  /// Right at its start or end, starts a range into the next block.
  bool _startRangeByKey(int index, Block block, LogicalKeyboardKey key, TextSelection sel) {
    final from = (block: index, offset: sel.extentOffset);
    Caret? next;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      next = _lineStep(from, down: key == LogicalKeyboardKey.arrowDown);
    } else if (key == LogicalKeyboardKey.arrowRight && sel.extentOffset >= block.text.length ||
        key == LogicalKeyboardKey.arrowLeft && sel.extentOffset == 0) {
      next = _charStep(from, forward: key == LogicalKeyboardKey.arrowRight);
    }
    if (next == null || next.block == index) return false;
    _setRange(BlockRange((block: index, offset: sel.baseOffset), next));
    _positionRangeToolbar();
    return true;
  }

  /// Ends the range and puts the caret at [caret].
  void _placeCaret(Caret caret) {
    _setRange(null);
    _moveCaret(caret);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A field that kept focus keeps its caret in [_applyPending]; set it here.
      if (!mounted || caret.block >= doc.length) return;
      final block = doc[caret.block];
      if (!hasInlineText(block) || !_focusFor(block).hasFocus) return;
      final text = _textFor(block);
      if (text.text == block.text) {
        text.selection = TextSelection.collapsed(offset: caret.offset.clamp(0, block.text.length));
      }
    });
  }

  /// Keys while a range is selected. Null lets the block handle the key.
  KeyEventResult? _onRangeKey(BlockRange range, KeyEvent event) {
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final shift = keys.isShiftPressed;
    final modifiers = <LogicalKeyboardKey>{
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
      LogicalKeyboardKey.capsLock,
    };
    if (modifiers.contains(key)) return null;
    if (range.end.block >= doc.length) {
      _setRange(null);
      return null;
    }
    if (ctrl && key == LogicalKeyboardKey.keyC) {
      _copyRange(range);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyA) {
      _setRange(BlockRange((block: 0, offset: 0), (block: doc.length - 1, offset: doc[doc.length - 1].text.length)));
      _positionRangeToolbar();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _placeCaret(range.focus);
      return KeyEventResult.handled;
    }
    final arrows = <LogicalKeyboardKey>{
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    };
    if (arrows.contains(key) && !ctrl) {
      if (!shift) {
        final back = key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft;
        _placeCaret(back ? range.start : range.end);
        return KeyEventResult.handled;
      }
      final next = key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown
          ? _lineStep(range.focus, down: key == LogicalKeyboardKey.arrowDown)
          : _charStep(range.focus, forward: key == LogicalKeyboardKey.arrowRight);
      if (next != null) {
        final moved = BlockRange(range.anchor, next);
        if (moved.isCollapsed) {
          _placeCaret(next);
        } else {
          _setRange(moved);
          _positionRangeToolbar();
        }
      }
      return KeyEventResult.handled;
    }
    if (widget.readOnly) return null;
    if (ctrl && key == LogicalKeyboardKey.keyX) {
      _copyRange(range);
      _placeCaret(deleteRange(doc, range));
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyV) {
      _pasteOverRange(range);
      return KeyEventResult.handled;
    }
    if (ctrl && !doc.plain) {
      final marker = switch (key) {
        LogicalKeyboardKey.keyB => '**',
        LogicalKeyboardKey.keyI => '_',
        LogicalKeyboardKey.keyE => '`',
        LogicalKeyboardKey.keyX when shift => '~~',
        _ => null,
      };
      if (marker != null) {
        _formatRange(marker);
        return KeyEventResult.handled;
      }
    }
    if (ctrl) {
      // Undo, redo and the app's own shortcuts work as usual; the range ends.
      if (key == LogicalKeyboardKey.keyZ || key == LogicalKeyboardKey.keyY) _setRange(null);
      return key == LogicalKeyboardKey.keyK ? KeyEventResult.handled : null;
    }
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _placeCaret(deleteRange(doc, range));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      indentRange(doc, range, shift ? -1 : 1);
      _setRange(range.clampTo(doc.blocks));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      final caret = deleteRange(doc, range);
      _placeCaret(hasInlineText(doc[caret.block]) ? doc.split(caret.block, caret.offset) : caret);
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (character != null &&
        character.isNotEmpty &&
        character.codeUnitAt(0) >= 0x20 &&
        character.codeUnitAt(0) != 0x7f) {
      // Typing replaces the selection, as in any text field.
      _placeCaret(deleteRange(doc, range, insert: character));
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  void _copyRange(BlockRange range) {
    final markdown = rangeMarkdown(doc.blocks, range);
    _rangeClip = markdown;
    Clipboard.setData(ClipboardData(text: markdown));
  }

  Future<void> _pasteOverRange(BlockRange range) async {
    final caret = deleteRange(doc, range);
    _placeCaret(caret);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final clip = data?.text;
    if (!mounted || clip == null || clip.isEmpty || caret.block >= doc.length) return;
    final block = doc[caret.block];
    if (!hasInlineText(block)) return;
    final at = caret.offset.clamp(0, block.text.length);
    final head = block.text.substring(0, at), tail = block.text.substring(at);
    final blocks =
        clip == _rangeClip && block.isText && !doc.plain ? pasteBlocks(doc, caret.block, head, tail, clip) : null;
    if (blocks != null) {
      _placeCaret(blocks);
      return;
    }
    doc.updateText(caret.block, head + clip + tail, caret: (block: caret.block, offset: at + clip.length));
    _placeCaret((block: caret.block, offset: at + clip.length));
  }

  /// Text copied from a range and pasted into a field comes back as the
  /// blocks it was copied from rather than as lines of one block.
  bool _pasteRangeClip(int index, Block block, String value, TextSelection sel) {
    final clip = _rangeClip;
    if (clip == null || !clip.contains('\n') || !sel.isValid || !sel.isCollapsed) return false;
    final start = sel.extentOffset - clip.length;
    if (start < 0 || value.substring(start, sel.extentOffset) != clip) return false;
    final head = value.substring(0, start), tail = value.substring(sel.extentOffset);
    final old = block.text;
    if (head.length + tail.length > old.length || !old.startsWith(head) || !old.endsWith(tail)) return false;
    final text = _textFor(block);
    final caret = pasteBlocks(doc, index, head, tail, clip);
    if (caret == null) return false;
    text.expectChange(value, doc[index].text);
    _placeCaret(caret);
    return true;
  }

  /// A table pasted into a text block (from a spreadsheet, a web page, or
  /// Markdown or text drawn with border lines) becomes a table block, with
  /// the border lines left out.
  bool _pasteTable(int index, Block block, String value, TextSelection sel) {
    final old = block.text;
    if (!sel.isValid || !sel.isCollapsed || value.length <= old.length) return false;
    var start = 0;
    while (start < old.length && old.codeUnitAt(start) == value.codeUnitAt(start)) {
      start++;
    }
    var end = 0;
    while (
        end < old.length - start && old.codeUnitAt(old.length - 1 - end) == value.codeUnitAt(value.length - 1 - end)) {
      end++;
    }
    final pasted = value.substring(start, value.length - end);
    if (!pasted.contains('\n') || sel.extentOffset != value.length - end) return false;
    final grid = parseTableText(pasted, minRows: 2);
    if (grid == null) return false;
    final text = _textFor(block);
    final caret = pasteTable(doc, index, old.substring(0, start), old.substring(old.length - end), grid);
    if (doc[index].isText) text.expectChange(value, doc[index].text);
    _placeCaret(caret);
    return true;
  }

  void _formatRange(String marker) {
    final range = _range;
    if (range == null) return;
    final next = formatRange(doc, range, marker);
    _rangeVersion = doc.version;
    setState(() => _range = next.clampTo(doc.blocks));
    _positionRangeToolbar();
  }

  void _formatRangeAction(FormatAction action) {
    final marker = switch (action) {
      FormatAction.bold => '**',
      FormatAction.italic => '_',
      FormatAction.strike => '~~',
      FormatAction.code => '`',
      FormatAction.link => null,
    };
    if (marker != null) _formatRange(marker);
  }

  void _turnRangeInto(BlockKind kind, int level) {
    final range = _range;
    if (range == null) return;
    final caret = convertRange(doc, range, kind, level);
    if (caret != null) {
      _placeCaret(caret);
      return;
    }
    _rangeVersion = doc.version;
    setState(() => _range = range.clampTo(doc.blocks));
    _positionRangeToolbar();
  }

  /// Shows the toolbar above the first selected line on screen.
  void _positionRangeToolbar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final range = _range;
      if (!mounted || range == null || widget.readOnly || doc.plain || _press != null) return;
      for (var i = range.start.block; i <= range.end.block && i < doc.length; i++) {
        final block = doc[i];
        RenderBox? from;
        Rect? local;
        final editable = hasInlineText(block) ? _editableFor(block) : null;
        if (editable != null && editable.attached && editable.hasSize) {
          final sel = range.selectionIn(i, block)!;
          final boxes = sel.isCollapsed ? const <TextBox>[] : editable.getBoxesForSelection(sel);
          from = editable;
          local = boxes.isEmpty ? editable.getLocalRectForCaret(TextPosition(offset: sel.start)) : boxes.first.toRect();
        } else {
          final box = _bodyKeys[block.id]?.currentContext?.findRenderObject();
          if (box is RenderBox && box.attached && box.hasSize) {
            from = box;
            local = Offset.zero & Size(box.size.width.clamp(0, 300), 20);
          }
        }
        if (from == null || local == null) continue;
        final topLeft = from.localToGlobal(local.topLeft);
        final anchor = Rect.fromLTWH(topLeft.dx, topLeft.dy, local.width, local.height);
        final id = doc[range.start.block].id;
        final current = _toolbar;
        if (current != null && current.range && current.blockId == id && current.anchor == anchor) return;
        setState(() => _toolbar = _ToolbarSession(id, anchor, range: true));
        if (!_toolbarPortal.isShowing) _toolbarPortal.show();
        return;
      }
    });
    // Nothing else may be about to draw (a mouse release changes no field).
    WidgetsBinding.instance.scheduleFrame();
  }

  // ---- floating toolbar and block menu ----------------------------------------

  /// Shows the toolbar above the block's selection once it has been laid out.
  void _positionToolbar(Block block) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusFor(block).hasFocus) return;
      final text = _textFor(block);
      if (text.selection.isCollapsed || !text.selection.isValid) return;
      final editable = _findEditable(_fieldKeyFor(block).currentContext?.findRenderObject());
      if (editable == null) return;
      final boxes = editable.getBoxesForSelection(text.selection);
      Rect local;
      if (boxes.isEmpty) {
        local = editable.getLocalRectForCaret(TextPosition(offset: text.selection.start));
      } else {
        local = boxes.first.toRect();
        for (final b in boxes.skip(1)) {
          local = local.expandToInclude(b.toRect());
        }
      }
      final topLeft = editable.localToGlobal(local.topLeft);
      final anchor = Rect.fromLTWH(topLeft.dx, topLeft.dy, local.width, local.height);
      final current = _toolbar;
      if (current != null && current.blockId == block.id && current.anchor == anchor) return;
      setState(() => _toolbar = _ToolbarSession(block.id, anchor));
      if (!_toolbarPortal.isShowing) _toolbarPortal.show();
    });
  }

  void _closeToolbar() {
    if (_toolbar == null) return;
    _toolbar = null;
    if (_toolbarPortal.isShowing) _toolbarPortal.hide();
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_toolbar != null) _closeToolbar();
  }

  void _formatAction(Block block, FormatAction action) {
    final index = doc.indexOf(block.id);
    if (index < 0) return;
    switch (action) {
      case FormatAction.bold:
        _toggleInline(index, block, '**');
      case FormatAction.italic:
        _toggleInline(index, block, '_');
      case FormatAction.strike:
        _toggleInline(index, block, '~~');
      case FormatAction.code:
        _toggleInline(index, block, '`');
      case FormatAction.link:
        _insertLink(index, block);
    }
    _focusFor(block).requestFocus();
  }

  /// Turns a block into [kind] at [level], keeping its text and the caret.
  void _turnInto(Block block, BlockKind kind, int level) {
    final index = doc.indexOf(block.id);
    if (index < 0) return;
    final current = doc[index];
    if (current.kind == kind && (kind != BlockKind.heading || current.level == level)) return;
    final offset = _isCode(current) ? 0 : (_textFor(current).selection.extentOffset.clamp(0, current.text.length));
    doc.convert(index, kind, level: level, caret: (block: index, offset: offset));
    _moveCaret((block: index, offset: offset));
  }

  Future<void> _openBlockMenu(Block block, Offset at) async {
    final index = doc.indexOf(block.id);
    if (index < 0) return;
    final result = await showBlockMenu(context, at, doc[index],
        canMoveUp: index > 0,
        canMoveDown: index + 1 < doc.length,
        collapsed: doc[index].kind == BlockKind.heading ? _collapsed.contains(block.id) : null);
    if (result == null || !mounted) return;
    final i = doc.indexOf(block.id);
    if (i < 0) return;
    switch (result.$1) {
      case BlockAction.turnInto:
        _turnInto(block, result.$2!.$1, result.$2!.$2);
      case BlockAction.duplicate:
        final copy = doc[i].clone();
        doc.insert(i + 1, copy.copyWith(caption: doc[i].caption, checked: doc[i].checked));
        _moveCaret((block: i + 1, offset: 0));
      case BlockAction.moveUp:
        doc.move(i, i - 1);
        _moveCaret((block: i - 1, offset: 0));
      case BlockAction.moveDown:
        doc.move(i, i + 1);
        _moveCaret((block: i + 1, offset: 0));
      case BlockAction.collapse || BlockAction.expand:
        _toggleSection(doc[i]);
      case BlockAction.delete:
        _moveCaret(doc.remove(i));
    }
  }

  // ---- slash menu ------------------------------------------------------------

  /// Opens the menu when `/` is typed at the start of a block or after a
  /// space, follows the query while typing, and closes it when the slash goes.
  void _trackSlash(int index, Block block, String value, TextSelection sel) {
    final slash = _slash;
    if (slash != null && slash.blockId == block.id) {
      final alive = sel.isValid &&
          sel.isCollapsed &&
          sel.extentOffset > slash.offset &&
          value.length > slash.offset &&
          value[slash.offset] == '/';
      if (!alive) {
        _closeSlash();
        return;
      }
      final query = value.substring(slash.offset + 1, sel.extentOffset);
      if (query.contains('\n')) {
        _closeSlash();
        return;
      }
      setState(() {
        slash.query = query;
        slash.items = filterSlashCommands(query);
        slash.selected = 0;
      });
      return;
    }
    if (slash != null) _closeSlash();
    final typedOne = value.length == block.text.length + 1;
    if (!typedOne || !sel.isValid || !sel.isCollapsed || sel.extentOffset == 0) return;
    final at = sel.extentOffset - 1;
    if (value[at] != '/') return;
    if (at > 0 && value[at - 1].trim().isNotEmpty) return;
    _slash = _SlashSession(blockId: block.id, offset: at, items: filterSlashCommands(''));
    _slashPortal.show();
    _positionSlash(block);
    setState(() {});
  }

  /// Finds the slash character on screen and anchors the menu to it.
  void _positionSlash(Block block) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final slash = _slash;
      if (!mounted || slash == null || slash.blockId != block.id) return;
      final render = _fieldKeyFor(block).currentContext?.findRenderObject();
      final editable = _findEditable(render);
      Rect anchor;
      if (editable != null) {
        final local = editable.getLocalRectForCaret(TextPosition(offset: slash.offset));
        final topLeft = editable.localToGlobal(local.topLeft);
        anchor = Rect.fromLTWH(topLeft.dx, topLeft.dy, local.width, local.height);
      } else if (render is RenderBox && render.hasSize) {
        final topLeft = render.localToGlobal(Offset.zero);
        anchor = Rect.fromLTWH(topLeft.dx, topLeft.dy, 8, render.size.height);
      } else {
        return;
      }
      setState(() => slash.anchor = anchor);
    });
  }

  static RenderEditable? _findEditable(RenderObject? root) {
    if (root == null) return null;
    if (root is RenderEditable) return root;
    RenderEditable? found;
    root.visitChildren((child) {
      found ??= _findEditable(child);
    });
    return found;
  }

  void _closeSlash() {
    if (_slash == null) return;
    _slash = null;
    if (_slashPortal.isShowing) _slashPortal.hide();
    if (mounted) setState(() {});
  }

  /// Runs the chosen command: removes `/query` from the block, then applies it.
  Future<void> _applySlash(int index, Block block, int choice) async {
    final slash = _slash;
    if (slash == null || slash.blockId != block.id) return;
    if (choice < 0 || choice >= slash.items.length) {
      _closeSlash();
      return;
    }
    final command = slash.items[choice];
    final text = _textFor(block);
    final current = text.text;
    final caret = text.selection.isValid ? text.selection.extentOffset : current.length;
    final end = caret.clamp(slash.offset, current.length);
    final cleaned = current.replaceRange(slash.offset, end, '');
    _closeSlash();
    text.expectChange(current, cleaned);
    text.value = TextEditingValue(text: cleaned, selection: TextSelection.collapsed(offset: slash.offset));
    if (cleaned != doc[index].text) doc.updateText(index, cleaned);
    if (command.id == 'image') {
      final path = await (widget.pickImage ?? showImageDialog)(context);
      if (!mounted || path == null || path.trim().isEmpty) return;
      final url = await importImage(widget.controller, path);
      if (!mounted) return;
      final at = doc.indexOf(block.id);
      if (at < 0) return;
      final result = command.apply(doc, at);
      final imageIndex = doc.blocks.indexWhere((b) => b.kind == BlockKind.image && b.url.isEmpty);
      if (imageIndex >= 0) {
        final name = p.basenameWithoutExtension(Uri.decodeFull(url)).replaceAll(RegExp(r'[-_]+'), ' ');
        doc.replace(imageIndex, doc[imageIndex].copyWith(url: url, alt: url.contains('://') ? '' : name));
      }
      _moveCaret(result);
      return;
    }
    _moveCaret(command.apply(doc, index));
  }

  // ---- building --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    final metrics = BlockMetrics(
        palette: palette, textScaler: MediaQuery.textScalerOf(context), inputStyle: BlockMetrics.inputStyleOf(context))
      ..resolvesImage = (block) => _imageFile(block) != null;
    return ListenableBuilder(
      listenable: doc,
      builder: (context, _) {
        // Controllers outlive their blocks only after a removal; pruning is a
        // pass over every block, so it waits for that.
        if (_focus.length + _codeFocus.length > doc.length) _prune();
        // An edit from anywhere else (typing, undo, the assistant) ends a range.
        if (_range != null && _rangeVersion != doc.version) {
          _range = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _toolbar?.range == true) _closeToolbar();
          });
        }
        _selectionColor =
            DefaultSelectionStyle.of(context).selectionColor ?? Theme.of(context).colorScheme.primary.withAlpha(102);
        return OverlayPortal(
          controller: _toolbarPortal,
          overlayChildBuilder: (context) {
            final toolbar = _toolbar;
            if (toolbar == null) return const SizedBox.shrink();
            final i = doc.indexOf(toolbar.blockId);
            if (i < 0) return const SizedBox.shrink();
            final block = doc[i];
            if (toolbar.range) {
              return FormatToolbar(
                anchor: toolbar.anchor,
                block: block,
                link: false,
                onAction: _formatRangeAction,
                onTurnInto: _turnRangeInto,
              );
            }
            return FormatToolbar(
              anchor: toolbar.anchor,
              block: block,
              onAction: (action) => _formatAction(block, action),
              onTurnInto: (kind, level) => _turnInto(block, kind, level),
            );
          },
          child: OverlayPortal(
            controller: _slashPortal,
            overlayChildBuilder: (context) {
              final slash = _slash;
              if (slash == null || slash.anchor == null) return const SizedBox.shrink();
              final block = doc.indexOf(slash.blockId);
              return SlashMenuPanel(
                anchor: slash.anchor!,
                items: slash.items,
                selected: slash.selected,
                query: slash.query,
                onHover: (i) => setState(() => slash.selected = i),
                onPick: (i) {
                  if (block >= 0) _applySlash(block, doc[block], i);
                },
              );
            },
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerEnd,
              onPointerCancel: _onPointerEnd,
              child: Scrollbar(
                controller: _scroll,
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(0, 6, BlockMetrics.listPadding, 0),
                  itemCount: doc.length + 1,
                  // Every row's height is known up front, so a jump to any point
                  // of a long page lays out only the rows that show there.
                  itemExtentBuilder: (i, dimensions) => i == doc.length
                      ? BlockMetrics.tailHeight
                      : _extentsFor(metrics, dimensions.crossAxisExtent - BlockMetrics.gutter)[i],
                  // Rows are keyed by block id, so a block that moves (after a split
                  // or an insert above it) keeps its widgets, focus and text input.
                  findChildIndexCallback: (key) {
                    if (key is! ValueKey<String> || !key.value.startsWith('row-')) return null;
                    final index = doc.indexOf(int.parse(key.value.substring(4)));
                    return index < 0 ? null : index;
                  },
                  itemBuilder: (context, i) {
                    if (i == doc.length) return _tail(palette);
                    return _row(context, palette, i, doc[i]);
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Empty space under the last block: a click there adds or focuses a paragraph.
  Widget _tail(StackPalette palette) => DragTarget<int>(
      onWillAcceptWithDetails: (d) {
        final at = (index: doc.length, above: true);
        if (_dropAt != at) setState(() => _dropAt = at);
        return true;
      },
      onLeave: (_) {
        if (_dropAt?.index == doc.length) setState(() => _dropAt = null);
      },
      onAcceptWithDetails: (d) => _drop(d.data, doc.length - 1, false),
      builder: (context, _, __) => Stack(children: [
            _tailBody(palette),
            if (_dropAt?.index == doc.length) _dropLine(palette, top: 0),
          ]));

  Widget _dropLine(StackPalette palette, {double? top, double? bottom}) => Positioned(
        left: BlockMetrics.gutter,
        right: 0,
        top: top,
        bottom: bottom,
        child: IgnorePointer(
          child: Container(
            key: const ValueKey('drop-line'),
            height: 3,
            decoration: BoxDecoration(color: palette.accentA, borderRadius: BorderRadius.circular(2)),
          ),
        ),
      );

  Widget _tailBody(StackPalette palette) => Semantics(
      button: true,
      label: 'Add a paragraph at the end',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.readOnly
            ? null
            : () {
                final last = doc.length - 1;
                if (last >= 0 && doc[last].kind == BlockKind.paragraph && doc[last].text.isEmpty) {
                  _moveCaret((block: last, offset: 0));
                } else {
                  doc.insert(doc.length, Block(kind: BlockKind.paragraph));
                  _moveCaret((block: doc.length - 1, offset: 0));
                }
              },
        child: const SizedBox(height: BlockMetrics.tailHeight, width: double.infinity),
      ));

  /// Bumped by every [setState], so a row can tell the editor's own state
  /// changing (a selection, a drag, a folded section) from an edit to some
  /// other block, after which it hands back the same widgets (see [_row]).
  int _stamp = 0;

  @override
  void setState(VoidCallback fn) {
    _stamp++;
    super.setState(fn);
  }

  /// Each row's last widgets and what they were built from.
  final _rows = <int, (Object, Widget)>{};

  Widget _row(BuildContext context, StackPalette palette, int index, Block block) {
    if (_isHidden(index)) return SizedBox.shrink(key: ValueKey('row-${block.id}'));
    _applyPending(index);
    final previous = index > 0 ? doc[index - 1] : null;
    final folded = block.kind == BlockKind.heading && _collapsed.contains(block.id);
    final look = (
      _stamp,
      block,
      index,
      previous,
      _range,
      _selectionColor,
      widget.readOnly,
      doc.plain,
      palette,
      _options,
      folded ? doc.version : -1, // the count of hidden blocks
      block.kind == BlockKind.numbered ? _numberedAbove(index) : 0, // its number
    );
    final cached = _rows[block.id];
    if (cached != null && cached.$1 == look) return cached.$2;
    final row = _buildRow(context, palette, index, block);
    _rows[block.id] = (look, row);
    return row;
  }

  /// How many numbered items run on right above [index].
  int _numberedAbove(int index) {
    var n = 0;
    for (var i = index - 1; i >= 0 && doc[i].kind == BlockKind.numbered; i--) {
      n++;
    }
    return n;
  }

  Widget _buildRow(BuildContext context, StackPalette palette, int index, Block block) {
    final node = _focusFor(block);
    final Widget body;
    switch (block.kind) {
      case BlockKind.divider:
        body = _NonTextBlock(
          focusNode: node,
          label: 'Divider',
          child: Divider(color: palette.barBorder, thickness: 1, height: 24),
        );
      case BlockKind.image:
        final alt = _altFor(block);
        if (alt.text != block.alt && !_altFocusFor(block).hasFocus) alt.text = block.alt;
        body = _NonTextBlock(
          focusNode: node,
          label: 'Image ${block.alt.isEmpty ? block.url : block.alt}',
          child: _ImageBlock(
            block: block,
            file: _imageFile(block),
            alt: alt,
            altFocus: _altFocusFor(block),
            readOnly: widget.readOnly,
            onAlt: (value) {
              final i = doc.indexOf(block.id);
              if (i >= 0 && doc[i].alt != value) doc.replace(i, doc[i].copyWith(alt: value));
            },
          ),
        );
      case BlockKind.table:
        body = _tableBlock(index, block);
      case BlockKind.code:
        body = _codeBlock(index, block);
      default:
        final text = _textFor(block);
        if (text.text != block.text) {
          if (_focusFor(block).hasFocus) text.expectChange(text.text, block.text);
          final old = text.selection;
          text.value = TextEditingValue(
            text: block.text,
            selection:
                old.isValid && old.end <= block.text.length ? old : TextSelection.collapsed(offset: block.text.length),
          );
        }
        text.styled = block.isText;
        body = _TextBlock(
          key: ValueKey(block.id),
          block: block,
          index: index,
          text: text,
          focusNode: node,
          readOnly: widget.readOnly,
          onChanged: (v) => _onChanged(block, v),
          onSelection: () => _reportSelection(block),
          onToggle: () => doc.toggleChecked(doc.indexOf(block.id)),
          onOpenLink: (offset) => _openLinkAt(doc[doc.indexOf(block.id)], offset),
          plain: doc.plain,
          fieldKey: _fieldKeyFor(block),
          range: _range?.selectionIn(index, block),
          rangeRunsOn: _range != null && _range!.covers(index) && index < _range!.end.block,
          rangeColor: _selectionColor,
        );
    }
    final gap = BlockMetrics.gapAbove(block, index > 0 ? doc[index - 1] : null);
    final isHeading = block.kind == BlockKind.heading;
    final collapsed = isHeading && _collapsed.contains(block.id);
    final dropHere = _dropAt?.index == index ? _dropAt : null;
    BuildContext? rowContext; // the row's own box, for the drop position
    return DragTarget<int>(
      key: ValueKey('row-${block.id}'),
      onWillAcceptWithDetails: (d) => d.data != block.id,
      onMove: (d) {
        if (rowContext != null && rowContext!.mounted) _updateDrop(index, d.offset, rowContext!);
      },
      onLeave: (_) {
        if (_dropAt?.index == index) setState(() => _dropAt = null);
      },
      onAcceptWithDetails: (d) => _drop(d.data, index, _dropAt?.above ?? true),
      builder: (context, _, __) {
        rowContext = context;
        return Stack(clipBehavior: Clip.none, children: [
          // The block on its way somewhere else is dimmed where it was.
          Opacity(
            opacity: _dragId == block.id ? 0.35 : 1,
            child: _rowBody(context, palette, index, block, node, body, gap, isHeading, collapsed),
          ),
          if (dropHere != null) dropHere.above ? _dropLine(palette, top: gap - 2) : _dropLine(palette, bottom: -1),
        ]);
      },
    );
  }

  Widget _rowBody(BuildContext context, StackPalette palette, int index, Block block, FocusNode node, Widget body,
      double gap, bool isHeading, bool collapsed) {
    return Padding(
      padding: EdgeInsets.only(top: gap),
      // The row's slot has a fixed height; the body lays out at its natural
      // height, so a measurement that is off by a pixel can never squeeze a
      // field or make it scroll inside itself.
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minHeight: 0,
        maxHeight: double.infinity,
        child: MouseRegion(
          onEnter: (_) => _hoverFor(block).value = true,
          onExit: (_) => _hoverFor(block).value = false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: BlockMetrics.gutter,
                child: Padding(
                  // Centred on the first line of the block.
                  padding: EdgeInsets.only(
                      top: isHeading
                          ? (block.level == 1
                              ? 17
                              : block.level == 2
                                  ? 10
                                  : 7)
                          : 0),
                  child: Row(children: [
                    if (isHeading)
                      SectionToggle(
                        key: ValueKey('toggle-${block.id}'),
                        hover: _hoverFor(block),
                        focusNode: node,
                        collapsed: collapsed,
                        hiddenCount: collapsed ? _sectionEnd(index) - index - 1 : 0,
                        onToggle: () => _toggleSection(block),
                      )
                    else
                      const SizedBox(width: SectionToggle.size),
                    const SizedBox(width: 2),
                    BlockHandle(
                      key: ValueKey('handle-${block.id}'),
                      hover: _hoverFor(block),
                      focusNode: node,
                      label: 'Block options for block ${index + 1}',
                      onOpen: (at) => _openBlockMenu(block, at),
                      dragData: widget.readOnly ? null : block.id,
                      dragFeedback: _dragFeedback(palette, block),
                      onDragStarted: () => _onDragStarted(block),
                      onDragUpdate: _onDragUpdate,
                      onDragEnd: _onDragEnd,
                    ),
                  ]),
                ),
              ),
              Expanded(
                child: KeyedSubtree(
                  key: ValueKey('body-${block.id}'),
                  child: KeyedSubtree(
                    key: _bodyKeyFor(block),
                    child: Focus(
                      skipTraversal: true,
                      canRequestFocus: false,
                      onKeyEvent: (_, event) => _onKey(block, event),
                      // A block without inline text inside a range is selected whole.
                      child: DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          color: !hasInlineText(block) && (_range?.covers(index) ?? false) ? _selectionColor : null,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: body,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A block without text: it can hold focus so keys still work on it.
class _NonTextBlock extends StatelessWidget {
  const _NonTextBlock({required this.focusNode, required this.label, required this.child});
  final FocusNode focusNode;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    return Focus(
      focusNode: focusNode,
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: focusNode.requestFocus,
            child: Semantics(
                button: true,
                label: label,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: focused ? palette.accentA : Colors.transparent),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: child,
                )),
          );
        },
      ),
    );
  }
}

class _ImageBlock extends StatelessWidget {
  const _ImageBlock({
    required this.block,
    required this.file,
    required this.alt,
    required this.altFocus,
    required this.readOnly,
    required this.onAlt,
  });
  final Block block;
  final File? file;
  final TextEditingController alt;
  final FocusNode altFocus;
  final bool readOnly;
  final ValueChanged<String> onAlt;

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    final file = this.file;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (file != null)
            SizedBox(
              height: ImageBlockMetrics.imageHeight,
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(file, fit: BoxFit.contain, alignment: Alignment.centerLeft)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: palette.panel, borderRadius: BorderRadius.circular(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.image_outlined, size: 18, color: palette.subText),
                const SizedBox(width: 8),
                Flexible(
                    child: Text(block.url,
                        style: ImageBlockMetrics.pathStyle.copyWith(color: palette.subText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              height: ImageBlockMetrics.altHeight,
              child: Center(
                child: TextField(
                  key: ValueKey('alt-${block.id}'),
                  controller: alt,
                  focusNode: altFocus,
                  readOnly: readOnly,
                  maxLines: 1,
                  style: ImageBlockMetrics.altStyle.copyWith(color: palette.subText),
                  strutStyle: StrutStyle.fromTextStyle(ImageBlockMetrics.altStyle, forceStrutHeight: true),
                  cursorColor: palette.accentA,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                    hintText: 'Add a description (alt text)',
                    hintStyle: TextStyle(color: palette.subText.withAlpha(120)),
                  ),
                  onChanged: onAlt,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextBlock extends StatefulWidget {
  const _TextBlock({
    super.key,
    required this.block,
    required this.index,
    required this.text,
    required this.focusNode,
    required this.readOnly,
    required this.onChanged,
    required this.onSelection,
    required this.onToggle,
    required this.onOpenLink,
    required this.plain,
    required this.fieldKey,
    this.range,
    this.rangeRunsOn = false,
    this.rangeColor = Colors.transparent,
  });

  final GlobalKey fieldKey;

  /// The part of this block inside a selection across blocks, painted by the
  /// editor in place of the field's own selection.
  final TextSelection? range;

  /// Whether that selection goes on past the end of this block.
  final bool rangeRunsOn;
  final Color rangeColor;
  final Block block;
  final int index;
  final InlineMarkdownController text;
  final FocusNode focusNode;
  final bool readOnly;
  final ValueChanged<String> onChanged;
  final VoidCallback onSelection;
  final VoidCallback onToggle;

  /// Called with the caret offset of a click that should open a link there.
  final ValueChanged<int> onOpenLink;
  final bool plain;

  @override
  State<_TextBlock> createState() => _TextBlockState();
}

class _TextBlockState extends State<_TextBlock> {
  @override
  void initState() {
    super.initState();
    widget.text.addListener(widget.onSelection);
    widget.focusNode.addListener(_onFocus);
    SpellChecker.instance.addListener(_onSpelling);
  }

  @override
  void didUpdateWidget(_TextBlock old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.onSelection != widget.onSelection) {
      old.text.removeListener(old.onSelection);
      widget.text.addListener(widget.onSelection);
    }
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.text.removeListener(widget.onSelection);
    widget.focusNode.removeListener(_onFocus);
    SpellChecker.instance.removeListener(_onSpelling);
    super.dispose();
  }

  /// The word list loaded, a word was added, or checking was turned on or off.
  void _onSpelling() {
    if (mounted && widget.text.checkSpelling) setState(() {});
  }

  void _onFocus() {
    widget.onSelection(); // the editor reads the focus state itself
    if (mounted) setState(() {});
  }

  /// The last build and what it was made from. The editor rebuilds every
  /// row on each edit; a row whose block and state are unchanged returns the
  /// same widgets, so its text field is not rebuilt (see [build]).
  Object? _look;
  Widget? _built;

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    final block = widget.block;
    final look = (
      block,
      widget.index,
      widget.text,
      widget.focusNode,
      widget.focusNode.hasFocus,
      widget.readOnly,
      widget.plain,
      widget.range,
      widget.rangeRunsOn,
      widget.rangeColor,
      palette,
      block.kind == BlockKind.numbered && block.number == null ? _numberOf() : 0,
      SpellChecker.instance.generation, // words added, the list loaded
      SpellChecker.instance.active,
    );
    if (look == _look) return _built!;
    _look = look;
    return _built = _build(palette, block);
  }

  Widget _build(StackPalette palette, Block block) {
    final style = BlockMetrics.styleFor(block, palette);
    widget.text.markerColor = palette.subText;
    widget.text.codeColor = palette.accentB;
    widget.text.linkColor = palette.accentA;
    final hint = switch (block.kind) {
      BlockKind.heading => 'Heading ${block.level}',
      BlockKind.code => widget.plain ? '' : 'Code',
      BlockKind.quote => 'Quote',
      BlockKind.bullet || BlockKind.numbered || BlockKind.todo => 'List item',
      BlockKind.paragraph => widget.focusNode.hasFocus ? "Type '/' for commands, or just write" : '',
      _ => '',
    };
    final field = TextField(
      key: widget.fieldKey,
      controller: widget.text,
      focusNode: widget.focusNode,
      readOnly: widget.readOnly,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      style: style,
      cursorColor: palette.accentA,
      onChanged: widget.onChanged,
      contextMenuBuilder: spellingContextMenu,
      // The tap has already put the caret where it landed. Ctrl+click opens
      // the link there; a plain click only edits. Read-only: any click opens.
      onTap: () {
        final keys = HardwareKeyboard.instance;
        if (widget.plain || !(widget.readOnly || keys.isControlPressed || keys.isMetaPressed)) return;
        final sel = widget.text.selection;
        if (sel.isValid) widget.onOpenLink(sel.extentOffset);
      },
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        hintText: hint.isEmpty ? null : hint,
        hintStyle: style.copyWith(color: palette.subText.withAlpha(140), fontStyle: FontStyle.normal),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
    );

    // The tree keeps one shape for every kind, so changing a paragraph into a
    // heading or a list item updates the field in place instead of recreating
    // it (which would drop keys typed in the same instant).
    final boxed = block.kind == BlockKind.raw;
    final isListItem = block.isList;
    final Widget marker;
    if (block.kind == BlockKind.todo) {
      marker = SizedBox(
        width: 24,
        height: 24,
        child: Checkbox(
          value: block.checked,
          onChanged: widget.readOnly ? null : (_) => widget.onToggle(),
          visualDensity: VisualDensity.compact,
          side: BorderSide(color: palette.subText),
        ),
      );
    } else if (block.kind == BlockKind.numbered) {
      marker = SizedBox(
        width: 24,
        child: Text('${block.number ?? _numberOf()}.',
            style: style.copyWith(color: palette.subText),
            textAlign: TextAlign.right,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip),
      );
    } else if (block.kind == BlockKind.bullet) {
      marker = SizedBox(
          width: 24,
          child: Text('•',
              style: style.copyWith(color: palette.subText),
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false));
    } else {
      marker = const SizedBox.shrink();
    }
    // Always the same widgets around the field (DecoratedBox, Padding, Row,
    // Column), only their parameters change, so the field is never rebuilt
    // from scratch when its block changes kind.
    final decoration = boxed
        ? BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: palette.barBorder))
        : block.kind == BlockKind.quote
            ? BoxDecoration(border: Border(left: BorderSide(color: palette.accentB, width: 3)))
            : const BoxDecoration();
    final padding = boxed
        ? const EdgeInsets.fromLTRB(10, 6, 10, 8)
        : block.kind == BlockKind.quote
            ? const EdgeInsets.only(left: 14)
            : block.kind == BlockKind.heading
                ? EdgeInsets.only(top: block.level == 1 ? 10 : 6)
                : EdgeInsets.zero;
    return Padding(
      padding: EdgeInsets.only(left: isListItem ? 24.0 * block.level : 0),
      child: DecoratedBox(
        decoration: decoration,
        child: Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              marker,
              SizedBox(width: isListItem ? 8 : 0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DefaultTextStyle.merge(
                      style: TextStyle(
                          decoration: block.kind == BlockKind.todo && block.checked
                              ? TextDecoration.lineThrough
                              : TextDecoration.none),
                      child: _RangeHighlight(
                        selection: widget.range,
                        runsOn: widget.rangeRunsOn,
                        color: widget.rangeColor,
                        child: DefaultSelectionStyle.merge(
                          selectionColor: widget.range != null ? Colors.transparent : null,
                          child: field,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _numberOf() {
    // Counts consecutive numbered items above this one.
    final doc = context.findAncestorStateOfType<_BlockEditorState>()?.doc;
    if (doc == null) return 1;
    var n = 1;
    for (var i = widget.index - 1; i >= 0 && doc[i].kind == BlockKind.numbered; i--) {
      n++;
    }
    return n;
  }
}

/// The state of an open slash menu.
class _ToolbarSession {
  _ToolbarSession(this.blockId, this.anchor, {this.range = false});
  final int blockId;
  final Rect anchor;

  /// Whether the toolbar acts on the selection across blocks.
  final bool range;
}

class _SlashSession {
  _SlashSession({required this.blockId, required this.offset, required this.items});

  final int blockId;

  /// Where the `/` is in the block's text.
  final int offset;
  String query = '';
  List<SlashCommand> items;
  int selected = 0;
  Rect? anchor;
}

class _Measured {
  const _Measured(this.block, this.width, this.scale, this.wrap, this.caption, this.body);
  final Block block;
  final double width;
  final TextScaler scale;
  final bool wrap;
  final bool caption;
  final double body;
}

/// Paints a selection across blocks inside one text field, behind its text.
class _RangeHighlight extends SingleChildRenderObjectWidget {
  const _RangeHighlight({required this.selection, required this.runsOn, required this.color, super.child});

  final TextSelection? selection;
  final bool runsOn;
  final Color color;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderRangeHighlight(selection, runsOn, color);

  @override
  void updateRenderObject(BuildContext context, _RenderRangeHighlight renderObject) {
    renderObject
      ..selection = selection
      ..runsOn = runsOn
      ..color = color;
  }
}

class _RenderRangeHighlight extends RenderProxyBox {
  _RenderRangeHighlight(this._selection, this._runsOn, this._color);

  TextSelection? _selection;
  set selection(TextSelection? value) {
    if (value == _selection) return;
    _selection = value;
    markNeedsPaint();
  }

  bool _runsOn;
  set runsOn(bool value) {
    if (value == _runsOn) return;
    _runsOn = value;
    markNeedsPaint();
  }

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final sel = _selection;
    final editable = sel == null ? null : _BlockEditorState._findEditable(child);
    if (sel != null && editable != null && editable.attached && editable.hasSize) {
      final shift = offset + MatrixUtils.transformPoint(editable.getTransformTo(this), Offset.zero);
      final paint = Paint()..color = _color;
      if (!sel.isCollapsed) {
        for (final box in editable.getBoxesForSelection(sel)) {
          context.canvas.drawRect(box.toRect().shift(shift), paint);
        }
      }
      // A selection that carries on into the next block also takes the line
      // break, shown as a sliver after the last character (or on an empty line).
      if (_runsOn) {
        final caret = editable.getLocalRectForCaret(TextPosition(offset: sel.end));
        context.canvas.drawRect(Rect.fromLTWH(caret.left, caret.top, 6, caret.height).shift(shift), paint);
      }
    }
    super.paint(context, offset);
  }
}
