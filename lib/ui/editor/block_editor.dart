import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../../app/theme.dart';
import '../../editor/blocks.dart';
import '../../editor/code_languages.dart';
import '../../editor/page_document.dart';
import '../../editor/page_editor_controller.dart';
import '../../editor/slash_commands.dart';
import 'block_metrics.dart';
import 'code_block.dart';
import 'inline_markdown.dart';
import 'slash_menu.dart';

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

  final _fieldKeys = <int, GlobalKey>{};

  // Code spaces: their editors, wrap setting, and which ones have a guessed
  // language (so a later edit may guess again).
  final _codes = <int, CodeLineEditingController>{};
  final _wrap = <int, bool>{};
  final _autoLanguage = <int>{};
  final _detectTimers = <int, Timer>{};
  static const detectDelay = Duration(milliseconds: 500);

  final _slashPortal = OverlayPortalController();
  _SlashSession? _slash;

  /// The open slash menu, for tests and the pane.
  bool get slashMenuOpen => _slash != null;

  @override
  void dispose() {
    for (final c in _texts.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
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

  FocusNode _focusFor(Block block) => _focus.putIfAbsent(block.id, () => FocusNode(debugLabel: 'block ${block.id}'));

  CodeLineEditingController _codeFor(Block block) =>
      _codes.putIfAbsent(block.id, () => CodeLineEditingController.fromText(block.text));

  /// Whether the block's text lives in a code editor rather than a text field.
  bool _isCode(Block block) => block.kind == BlockKind.code;

  GlobalKey _fieldKeyFor(Block block) => _fieldKeys.putIfAbsent(block.id, GlobalKey.new);

  /// Code blocks whose caption field is open although the caption is empty.
  final _captions = <int>{};

  /// Measured row heights, keyed by block id; valid while the block object,
  /// width, text scale and code options are the same.
  final _heights = <int, _Measured>{};

  void _prune() {
    final live = {for (final b in doc.blocks) b.id};
    _fieldKeys.removeWhere((id, _) => !live.contains(id));
    _heights.removeWhere((id, _) => !live.contains(id));
    _captions.removeWhere((id) => !live.contains(id));
    for (final id in _texts.keys.where((id) => !live.contains(id)).toList()) {
      _texts.remove(id)!.dispose();
    }
    for (final id in _focus.keys.where((id) => !live.contains(id)).toList()) {
      _focus.remove(id)!.dispose();
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
    setState(() => _pending = caret);
  }

  /// Applies [_pending] to the block that now owns it, after it has been built.
  void _applyPending(int index) {
    final pending = _pending;
    if (pending == null || pending.block != index || index >= doc.length) return;
    _pending = null;
    final block = doc[index];
    final node = _focusFor(block);
    final text = _textFor(block);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // A field that already has focus keeps its caret: setting the selection
      // would also send the field's text back to the platform, over any
      // typing still on its way in.
      if (node.hasFocus) return;
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
      final editable =
          block.isText || block.kind == BlockKind.code || block.kind == BlockKind.table || block.kind == BlockKind.raw;
      if (editable && current >= 0 && text.text == doc[current].text) {
        text.selection = TextSelection.collapsed(offset: pending.offset.clamp(0, text.text.length));
      }
    });
  }

  // ---- key handling ----------------------------------------------------------

  KeyEventResult _onKey(Block block, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (widget.readOnly) return KeyEventResult.ignored;
    // Callbacks may run before the list has rebuilt, so find the block now.
    final index = doc.indexOf(block.id);
    if (index < 0) return KeyEventResult.ignored;
    block = doc[index];
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final shift = keys.isShiftPressed;

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
      _moveCaret(shift ? doc.redo() : doc.undo());
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyY) {
      _moveCaret(doc.redo());
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

    final editable = block.isText || block.kind == BlockKind.table || block.kind == BlockKind.raw;
    if (!editable) return _onNonTextKey(index, block, key);

    final text = _textFor(block);
    final sel = text.selection;
    final value = text.text;

    // Enter is not handled here: the newline arrives with the typed text (see
    // [_onChanged]), which keeps it in order with characters still in flight
    // from the platform's text input.

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
  int _options = 0; // bumped when wrap or caption state changes

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
    for (var i = 0; i < doc.length; i++) {
      extents[i] = _rowHeight(metrics, i, width);
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
      onMoveOut: (direction) => _leaveCode(block, direction),
      showCaption: _captionShown(block),
      onShowCaption: () => setState(() {
        _captions.add(block.id);
        _options++;
      }),
    );
  }

  KeyEventResult _onNonTextKey(int index, Block block, LogicalKeyboardKey key) {
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
    final start = sel.start, end = sel.end, n = marker.length;
    final inner = value.substring(start, end);
    final String next;
    final TextSelection after;
    if (inner.length >= 2 * n && inner.startsWith(marker) && inner.endsWith(marker)) {
      next = value.replaceRange(start, end, inner.substring(n, inner.length - n));
      after = TextSelection(baseOffset: start, extentOffset: end - 2 * n);
    } else if (start >= n &&
        end + n <= value.length &&
        value.substring(start - n, start) == marker &&
        value.substring(end, end + n) == marker) {
      next = value.replaceRange(start - n, end + n, inner);
      after = TextSelection(baseOffset: start - n, extentOffset: end - n);
    } else {
      next = value.replaceRange(start, end, '$marker$inner$marker');
      after = TextSelection(baseOffset: start + n, extentOffset: end + n);
    }
    text.expectChange(value, next);
    text.value = TextEditingValue(text: next, selection: after);
    doc.updateText(index, next, caret: (block: index, offset: after.extentOffset));
  }

  /// Turns the selection into a Markdown link with the URL part selected.
  void _insertLink(int index, Block block) {
    final text = _textFor(block);
    final value = text.text;
    final sel = text.selection.isValid ? text.selection : TextSelection.collapsed(offset: value.length);
    final label = sel.isCollapsed ? 'text' : value.substring(sel.start, sel.end);
    final next = value.replaceRange(sel.start, sel.end, '[$label](url)');
    final urlStart = sel.start + label.length + 3;
    final after = TextSelection(baseOffset: urlStart, extentOffset: urlStart + 3);
    text.expectChange(value, next);
    text.value = TextEditingValue(text: next, selection: after);
    doc.updateText(index, next, caret: (block: index, offset: after.extentOffset));
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
    if (block.isText && !doc.plain) _trackSlash(index, block, value, sel);
    if (block.isText && _splitOnNewline(index, block, value, sel)) return;
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
      final path = await (widget.pickImage ?? _askImagePath)(context);
      if (!mounted || path == null || path.trim().isEmpty) return;
      final at = doc.indexOf(block.id);
      if (at < 0) return;
      final result = command.apply(doc, at);
      final imageIndex = doc.blocks.indexWhere((b) => b.kind == BlockKind.image && b.url.isEmpty);
      if (imageIndex >= 0) {
        final name = p.basename(path.trim());
        doc.replace(imageIndex, doc[imageIndex].copyWith(url: path.trim(), alt: name));
      }
      _moveCaret(result);
      return;
    }
    _moveCaret(command.apply(doc, index));
  }

  static Future<String?> _askImagePath(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insert image'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'File path or link',
              hintText: 'images/photo.png or https://...',
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Insert')),
        ],
      ),
    );
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
        if (_focus.length > doc.length) _prune();
        return OverlayPortal(
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
            child: Scrollbar(
              controller: _scroll,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(BlockMetrics.listPadding, 6, BlockMetrics.listPadding, 0),
                itemCount: doc.length + 1,
                // Every row's height is known up front, so a jump to any point
                // of a long page lays out only the rows that show there.
                itemExtentBuilder: (i, dimensions) =>
                    i == doc.length ? BlockMetrics.tailHeight : _extentsFor(metrics, dimensions.crossAxisExtent)[i],
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
            ));
      },
    );
  }

  /// Empty space under the last block: a click there adds or focuses a paragraph.
  Widget _tail(StackPalette palette) => Semantics(
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

  Widget _row(BuildContext context, StackPalette palette, int index, Block block) {
    _applyPending(index);
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
        body = _NonTextBlock(
          focusNode: node,
          label: 'Image ${block.alt.isEmpty ? block.url : block.alt}',
          child: _ImageBlock(block: block, file: _imageFile(block)),
        );
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
          plain: doc.plain,
          fieldKey: _fieldKeyFor(block),
        );
    }
    final gap = BlockMetrics.gapAbove(block, index > 0 ? doc[index - 1] : null);
    return Padding(
      key: ValueKey('row-${block.id}'),
      padding: EdgeInsets.only(top: gap),
      // The row's slot has a fixed height; the body lays out at its natural
      // height, so a measurement that is off by a pixel can never squeeze a
      // field or make it scroll inside itself.
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minHeight: 0,
        maxHeight: double.infinity,
        child: KeyedSubtree(
          key: ValueKey('body-${block.id}'),
          child: Focus(
            skipTraversal: true,
            canRequestFocus: false,
            onKeyEvent: (_, event) => _onKey(block, event),
            child: body,
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
  const _ImageBlock({required this.block, required this.file});
  final Block block;
  final File? file;

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
          if (block.alt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(block.alt,
                  style: ImageBlockMetrics.altStyle.copyWith(color: palette.subText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
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
    required this.plain,
    required this.fieldKey,
  });

  final GlobalKey fieldKey;
  final Block block;
  final int index;
  final InlineMarkdownController text;
  final FocusNode focusNode;
  final bool readOnly;
  final ValueChanged<String> onChanged;
  final VoidCallback onSelection;
  final VoidCallback onToggle;
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
    super.dispose();
  }

  void _onFocus() {
    widget.onSelection(); // the editor reads the focus state itself
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    final block = widget.block;
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
    final boxed = block.kind == BlockKind.table || block.kind == BlockKind.raw;
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
                      child: field,
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
