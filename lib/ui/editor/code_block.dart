import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import '../../app/theme.dart';
import 'header_button.dart';
import '../../editor/blocks.dart';
import '../../editor/code_languages.dart';

/// A code space: a highlighted code editor with a language picker, copy,
/// wrap toggle, caption and context menu.
class CodeBlockView extends StatefulWidget {
  const CodeBlockView({
    super.key,
    required this.block,
    required this.controller,
    required this.focusNode,
    required this.readOnly,
    required this.plain,
    required this.wrap,
    required this.autoDetected,
    required this.onChanged,
    required this.onLanguage,
    required this.onCaption,
    required this.onWrap,
    required this.onDelete,
    required this.onMoveOut,
    required this.showCaption,
    required this.onShowCaption,
  });

  final Block block;
  final CodeLineEditingController controller;
  final FocusNode focusNode;
  final bool readOnly;

  /// True when the whole file is this one code block (a script, not a page).
  final bool plain;
  final bool wrap;

  /// True when the language was guessed from the code rather than chosen.
  final bool autoDetected;
  final ValueChanged<String> onChanged;

  /// null = back to auto-detection.
  final ValueChanged<CodeLanguage?> onLanguage;
  final ValueChanged<String> onCaption;
  final ValueChanged<bool> onWrap;
  final VoidCallback onDelete;

  /// Called when an arrow key would move the caret past the first or last
  /// line (or the first or last character). Returns true when the block
  /// editor moved the focus to a neighbouring block.
  final bool Function(AxisDirection direction) onMoveOut;

  /// Whether the caption field is shown (kept by the editor, which needs it
  /// to know the block's height before building it).
  final bool showCaption;
  final VoidCallback onShowCaption;

  static const headerHeight = 34.0;

  /// Height of the whole block at [width] (the row width), mirroring [build].
  static double heightFor(Block block, double width,
      {required bool wrap, required bool caption, required TextScaler textScaler, required TextStyle inputStyle}) {
    var height = headerHeight + bodyHeight(block.text.split('\n'), width, wrap: wrap);
    if (caption) height += captionHeight(block.caption, width, textScaler, inputStyle);
    return height;
  }

  static const _captionStyle = TextStyle(fontSize: StackType.hint, height: 1.4, fontStyle: FontStyle.italic);

  /// Height of the caption field: its text (or the hint) as the field lays it
  /// out, on top of the theme's input style, plus 8 px below.
  static double captionHeight(String caption, double width, TextScaler textScaler, TextStyle inputStyle) {
    final style = inputStyle.merge(_captionStyle);
    final painter = TextPainter(
      text: TextSpan(text: caption.isEmpty ? 'Caption' : caption, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
    )..layout(maxWidth: width - 24);
    final height = painter.height < painter.preferredLineHeight ? painter.preferredLineHeight : painter.height;
    painter.dispose();
    return 8 + height;
  }

  /// The editor needs a fixed height: enough for its lines, up to a limit,
  /// after which it scrolls inside the block.
  static double bodyHeight(List<String> lines, double width, {required bool wrap}) {
    const line = fontSize * lineHeight;
    var rows = 0;
    if (wrap) {
      final usable = (width - 80).clamp(80.0, double.infinity);
      final perRow = (usable / (fontSize * 0.62)).floor().clamp(8, 1 << 20);
      for (final l in lines) {
        rows += (l.length / perRow).ceil().clamp(1, 1 << 20);
      }
    } else {
      rows = lines.length;
    }
    return (rows * line + 14 + (wrap ? 0 : 12)).clamp(line + 14, maxBodyHeight);
  }

  static const fontSize = 13.5;
  static const lineHeight = 1.5;
  static const maxBodyHeight = 640.0;

  @override
  State<CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<CodeBlockView> {
  final _captionController = TextEditingController();
  final _captionFocus = FocusNode(debugLabel: 'code caption');
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _captionController.text = widget.block.caption;
  }

  @override
  void didUpdateWidget(CodeBlockView old) {
    super.didUpdateWidget(old);
    if (widget.block.caption != _captionController.text && !_captionFocus.hasFocus) {
      _captionController.text = widget.block.caption;
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _captionFocus.dispose();
    super.dispose();
  }

  CodeLanguage? get _language => languageFor(widget.block.language);

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.controller.text));
    if (!mounted) return;
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _pickLanguage() async {
    final choice = await showDialog<_LanguageChoice>(
      context: context,
      builder: (context) =>
          _LanguagePicker(current: _language, auto: widget.autoDetected || widget.block.language == null),
    );
    if (choice == null) return;
    widget.onLanguage(choice.language);
  }

  void _toggleCaption() {
    widget.onShowCaption();
    WidgetsBinding.instance.addPostFrameCallback((_) => _captionFocus.requestFocus());
  }

  Future<void> _contextMenu(Offset at) async {
    final palette = StackColors.of(context);
    final controller = widget.controller;
    final hasSelection = !controller.selection.isCollapsed;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      color: palette.panel,
      items: [
        PopupMenuItem(value: 'copy', enabled: hasSelection, child: const Text('Copy')),
        const PopupMenuItem(value: 'copyAll', child: Text('Copy all')),
        if (!widget.readOnly) PopupMenuItem(value: 'cut', enabled: hasSelection, child: const Text('Cut')),
        if (!widget.readOnly) const PopupMenuItem(value: 'paste', child: Text('Paste')),
        const PopupMenuItem(value: 'selectAll', child: Text('Select all')),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(value: 'wrap', checked: widget.wrap, child: const Text('Wrap lines')),
        const PopupMenuItem(value: 'language', child: Text('Language...')),
        if (!widget.plain) const PopupMenuItem(value: 'caption', child: Text('Add caption')),
        if (!widget.plain && !widget.readOnly) const PopupMenuDivider(),
        if (!widget.plain && !widget.readOnly) const PopupMenuItem(value: 'delete', child: Text('Delete code block')),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'copy':
        await controller.copy();
      case 'copyAll':
        await _copy();
      case 'cut':
        controller.cut();
      case 'paste':
        controller.paste();
      case 'selectAll':
        controller.selectAll();
        widget.focusNode.requestFocus();
      case 'wrap':
        widget.onWrap(!widget.wrap);
      case 'language':
        await _pickLanguage();
      case 'caption':
        _toggleCaption();
      case 'delete':
        widget.onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    final language = _language;
    final mode = language?.mode;
    final theme = palette.dark ? atomOneDarkTheme : atomOneLightTheme;
    final style = CodeEditorStyle(
      fontFamily: 'Cascadia Mono',
      fontFamilyFallback: StackType.mono,
      fontSize: CodeBlockView.fontSize,
      fontHeight: CodeBlockView.lineHeight,
      textColor: palette.text,
      backgroundColor: Colors.transparent,
      cursorColor: palette.accentA,
      selectionColor: palette.accentA.withAlpha(palette.dark ? 90 : 60),
      cursorLineColor: palette.hover.withAlpha(80),
      chunkIndicatorColor: palette.subText,
      codeTheme: mode == null || language!.id == 'text'
          ? null
          : CodeHighlightTheme(languages: {
              language.id: CodeHighlightThemeMode(mode: mode)
            }, theme: {
              ...theme,
              'root': TextStyle(color: palette.text, backgroundColor: Colors.transparent),
            }),
    );
    final lineText = TextStyle(
        fontFamily: 'Cascadia Mono', fontFamilyFallback: StackType.mono, fontSize: 12, color: palette.subText);
    final languageLabel = language?.label ?? 'Plain text';
    final autoLabel = widget.autoDetected && language != null ? ' (auto)' : '';

    return Semantics(
      container: true,
      label: 'Code block, $languageLabel',
      child: GestureDetector(
        onSecondaryTapDown: (d) => _contextMenu(d.globalPosition),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.barBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: CodeBlockView.headerHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 6, 0),
                  child: Row(children: [
                    HeaderButton(
                      tooltip: 'Change language',
                      semanticLabel: 'Language: $languageLabel$autoLabel. Change language',
                      onPressed: widget.readOnly ? null : _pickLanguage,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(languageLabel,
                            style:
                                TextStyle(color: palette.text, fontSize: StackType.hint, fontWeight: FontWeight.w600)),
                        if (autoLabel.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 5),
                            child: Text('auto', style: TextStyle(color: palette.subText, fontSize: StackType.hint)),
                          ),
                        Icon(Icons.expand_more, size: 15, color: palette.subText),
                      ]),
                    ),
                    const Spacer(),
                    HeaderButton(
                      tooltip: widget.wrap ? 'Wrap lines: on' : 'Wrap lines: off',
                      semanticLabel: widget.wrap ? 'Wrap lines, on' : 'Wrap lines, off',
                      onPressed: () => widget.onWrap(!widget.wrap),
                      child: Icon(Icons.wrap_text, size: 16, color: widget.wrap ? palette.accentA : palette.subText),
                    ),
                    HeaderButton(
                      tooltip: 'Copy code',
                      semanticLabel: _copied ? 'Copied' : 'Copy code',
                      onPressed: _copy,
                      child: Icon(_copied ? Icons.check : Icons.copy_outlined,
                          size: 16, color: _copied ? palette.success : palette.subText),
                    ),
                    HeaderButton(
                      tooltip: 'More',
                      semanticLabel: 'More code block options',
                      onPressed: () {
                        final box = context.findRenderObject() as RenderBox;
                        _contextMenu(box.localToGlobal(Offset(box.size.width - 40, 30)));
                      },
                      child: Icon(Icons.more_horiz, size: 16, color: palette.subText),
                    ),
                  ]),
                ),
              ),
              LayoutBuilder(builder: (context, constraints) {
                final height = CodeBlockView.bodyHeight([
                  for (var i = 0; i < widget.controller.codeLines.length; i++) widget.controller.codeLines[i].text
                ], constraints.maxWidth, wrap: widget.wrap);
                return SizedBox(
                  height: height,
                  child: CodeEditor(
                    // An empty code space hands Backspace to the block editor, which turns it back into a paragraph.
                    shortcutsActivatorsBuilder:
                        _CodeShortcuts(passBackspace: !widget.plain && widget.block.text.isEmpty),
                    shortcutOverrideActions: {
                      // Arrows at the edges of the code leave the block.
                      CodeShortcutCursorMoveIntent: CallbackAction<CodeShortcutCursorMoveIntent>(onInvoke: (intent) {
                        if (!widget.onMoveOut(intent.direction)) widget.controller.moveCursor(intent.direction);
                        return null;
                      }),
                    },
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    readOnly: widget.readOnly,
                    autofocus: false,
                    wordWrap: widget.wrap,
                    style: style,
                    padding: const EdgeInsets.fromLTRB(4, 2, 12, 8),
                    indicatorBuilder: (context, editingController, chunkController, notifier) => Row(children: [
                      DefaultCodeLineNumber(
                          controller: editingController,
                          notifier: notifier,
                          textStyle: lineText,
                          focusedTextStyle: lineText.copyWith(color: palette.text),
                          minNumberCount: 2),
                      const SizedBox(width: 10),
                    ]),
                    onChanged: (value) => widget.onChanged(value.codeLines.asString(TextLineBreak.lf)),
                  ),
                );
              }),
              if (widget.showCaption && !widget.plain)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextField(
                    controller: _captionController,
                    focusNode: _captionFocus,
                    readOnly: widget.readOnly,
                    style: CodeBlockView._captionStyle.copyWith(color: palette.subText),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      hintText: 'Caption',
                      hintStyle: CodeBlockView._captionStyle.copyWith(color: palette.subText.withAlpha(140)),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: widget.onCaption,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageChoice {
  const _LanguageChoice(this.language);
  final CodeLanguage? language;
}

/// A searchable list of languages, with "Auto-detect" at the top.
class _LanguagePicker extends StatefulWidget {
  const _LanguagePicker({required this.current, required this.auto});
  final CodeLanguage? current;
  final bool auto;

  @override
  State<_LanguagePicker> createState() => _LanguagePickerState();
}

class _LanguagePickerState extends State<_LanguagePicker> {
  String _query = '';
  int _selected = 0;
  final _search = FocusNode();

  List<CodeLanguage> get _items => filterLanguages(_query);

  void _choose(int i) {
    // Row 0 is "Auto-detect" when nothing is typed.
    if (_query.isEmpty && i == 0) {
      Navigator.of(context).pop(const _LanguageChoice(null));
      return;
    }
    final items = _items;
    final index = _query.isEmpty ? i - 1 : i;
    if (index < 0 || index >= items.length) return;
    Navigator.of(context).pop(_LanguageChoice(items[index]));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final count = _items.length + (_query.isEmpty ? 1 : 0);
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && count > 0) {
      setState(() => _selected = (_selected + 1) % count);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && count > 0) {
      setState(() => _selected = (_selected - 1 + count) % count);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _choose(_selected);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    final items = _items;
    final rows = <Widget>[];
    if (_query.isEmpty) {
      rows.add(_row(palette, 0, Icons.auto_awesome_outlined, 'Auto-detect', 'Guess from the code', widget.auto));
    }
    for (var i = 0; i < items.length; i++) {
      final index = i + (_query.isEmpty ? 1 : 0);
      rows.add(_row(
          palette, index, Icons.code, items[i].label, items[i].id, !widget.auto && widget.current?.id == items[i].id));
    }
    return Dialog(
      backgroundColor: palette.panel,
      child: SizedBox(
        width: 340,
        height: 460,
        child: Focus(
          onKeyEvent: _onKey,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: TextField(
                key: const Key('language-search'),
                focusNode: _search,
                autofocus: true,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 18), hintText: 'Search languages', isDense: true),
                onChanged: (v) => setState(() {
                  _query = v;
                  _selected = 0;
                }),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(child: Text('No language matches "$_query"', style: TextStyle(color: palette.subText)))
                  : ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: rows),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(StackPalette palette, int index, IconData icon, String label, String detail, bool current) {
    final selected = index == _selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _selected = index),
      child: Semantics(
        button: true,
        selected: current,
        label: label,
        child: InkWell(
          onTap: () => _choose(index),
          child: Container(
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: selected ? palette.checkedGradient : null,
            ),
            child: Row(children: [
              Icon(icon, size: 16, color: palette.subText),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: TextStyle(color: palette.text, fontSize: StackType.button))),
              Text(detail, style: TextStyle(color: palette.subText, fontSize: StackType.hint)),
              if (current)
                Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.check, size: 16, color: palette.accentA)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The editor's default keys, except that Ctrl+Enter is left for the block
/// editor, which uses it to leave the code space on a new paragraph, and
/// Backspace is left to it too while the code space is empty. Undo and redo
/// also go to the block editor, so the page has one history.
class _CodeShortcuts extends DefaultCodeShortcutsActivatorsBuilder {
  const _CodeShortcuts({required this.passBackspace});
  final bool passBackspace;

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) {
    final activators = super.build(type);
    if (type == CodeShortcutType.backspace && passBackspace) return null;
    // One history for the whole page: the block editor undoes code edits too.
    if (type == CodeShortcutType.undo || type == CodeShortcutType.redo) return null;
    if (type != CodeShortcutType.newLine || activators == null) return activators;
    return [
      for (final a in activators)
        if (a is! SingleActivator || !a.control) a
    ];
  }

  @override
  bool operator ==(Object other) => other is _CodeShortcuts && other.passBackspace == passBackspace;

  @override
  int get hashCode => passBackspace.hashCode;
}
