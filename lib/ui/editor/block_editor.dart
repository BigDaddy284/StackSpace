import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../editor/blocks.dart';
import '../../editor/page_document.dart';
import '../../editor/page_editor_controller.dart';
import 'inline_markdown.dart';

/// Edits a page block by block. Each block is its own text field, so a page
/// with thousands of lines of code lays out only the blocks on screen.
class BlockEditor extends StatefulWidget {
  const BlockEditor({super.key, required this.controller, required this.readOnly});

  final PageEditorController controller;
  final bool readOnly;

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
  void dispose() {
    for (final c in _texts.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  InlineMarkdownController _textFor(Block block) =>
      _texts.putIfAbsent(block.id, () => InlineMarkdownController(text: block.text));

  FocusNode _focusFor(Block block) => _focus.putIfAbsent(block.id, () => FocusNode(debugLabel: 'block ${block.id}'));

  void _prune() {
    final live = {for (final b in doc.blocks) b.id};
    for (final id in _texts.keys.where((id) => !live.contains(id)).toList()) {
      _texts.remove(id)!.dispose();
    }
    for (final id in _focus.keys.where((id) => !live.contains(id)).toList()) {
      _focus.remove(id)!.dispose();
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

    final editable =
        block.isText || block.kind == BlockKind.code || block.kind == BlockKind.table || block.kind == BlockKind.raw;
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
    final text = _textFor(block);
    if (_focusFor(block).hasFocus) widget.controller.setSelection(index, text.selection);
  }

  // ---- building --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    return ListenableBuilder(
      listenable: doc,
      builder: (context, _) {
        _prune();
        return Scrollbar(
          controller: _scroll,
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
            itemCount: doc.length + 1,
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
        );
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
        child: const SizedBox(height: 120, width: double.infinity),
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
          child: _ImageBlock(block: block, controller: widget.controller),
        );
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
        );
    }
    final gap = index == 0 ? 0.0 : (block.isList && doc[index - 1].isList ? 2.0 : 10.0);
    return Padding(
      key: ValueKey('row-${block.id}'),
      padding: EdgeInsets.only(top: gap),
      child: Focus(
        skipTraversal: true,
        canRequestFocus: false,
        onKeyEvent: (_, event) => _onKey(block, event),
        child: body,
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
  const _ImageBlock({required this.block, required this.controller});
  final Block block;
  final PageEditorController controller;

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    final page = controller.path;
    File? file;
    if (page != null && !block.url.contains('://')) {
      final rel = p.posix.join(p.posix.dirname(page), Uri.decodeFull(block.url));
      final f = File(controller.workspace.resolve(rel));
      if (f.existsSync()) file = f;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (file != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 480),
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
                Text(block.url, style: TextStyle(color: palette.subText, fontSize: StackType.button)),
              ]),
            ),
          if (block.alt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(block.alt, style: TextStyle(color: palette.subText, fontSize: StackType.hint)),
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
  });

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
    if (widget.focusNode.hasFocus) widget.onSelection();
    if (mounted) setState(() {});
  }

  static const _mono =
      TextStyle(fontFamily: 'Cascadia Mono', fontFamilyFallback: StackType.mono, fontSize: 14, height: 1.45);

  TextStyle _style(StackPalette palette) {
    final block = widget.block;
    switch (block.kind) {
      case BlockKind.heading:
        final size = switch (block.level) { 1 => 30.0, 2 => 24.0, 3 => 20.0, 4 => 17.0, _ => 15.5 };
        return StackType.display(size, palette.text).copyWith(height: 1.3);
      case BlockKind.code || BlockKind.table || BlockKind.raw:
        return _mono.copyWith(color: palette.text);
      case BlockKind.quote:
        return TextStyle(fontSize: 15.5, height: 1.5, color: palette.subText, fontStyle: FontStyle.italic);
      default:
        return TextStyle(fontSize: 15.5, height: 1.5, color: palette.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    final block = widget.block;
    final style = _style(palette);
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
    final isCode = block.kind == BlockKind.code && !widget.plain;
    final boxed = isCode || block.kind == BlockKind.table || block.kind == BlockKind.raw;
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
            style: style.copyWith(color: palette.subText), textAlign: TextAlign.right),
      );
    } else if (block.kind == BlockKind.bullet) {
      marker = SizedBox(
          width: 24, child: Text('•', style: style.copyWith(color: palette.subText), textAlign: TextAlign.center));
    } else {
      marker = const SizedBox.shrink();
    }
    // Always the same widgets around the field (DecoratedBox, Padding, Row,
    // Column), only their parameters change, so the field is never rebuilt
    // from scratch when its block changes kind.
    final decoration = isCode
        ? BoxDecoration(
            color: palette.panel, borderRadius: BorderRadius.circular(8), border: Border.all(color: palette.barBorder))
        : boxed
            ? BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: palette.barBorder))
            : block.kind == BlockKind.quote
                ? BoxDecoration(border: Border(left: BorderSide(color: palette.accentB, width: 3)))
                : const BoxDecoration();
    final padding = isCode
        ? const EdgeInsets.fromLTRB(14, 10, 14, 12)
        : boxed
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
                    Padding(
                      padding: EdgeInsets.only(bottom: isCode ? 6 : 0),
                      child: isCode
                          ? Text(block.language ?? 'plain text',
                              style: TextStyle(color: palette.subText, fontSize: StackType.hint))
                          : const SizedBox.shrink(),
                    ),
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
