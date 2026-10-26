import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../editor/blocks.dart';
import '../../editor/table_data.dart';
import 'header_button.dart';

/// A table block as a grid of cells: a header strip with the row and column
/// buttons, then one single-line field per cell.
///
/// Tab and Shift+Tab move between cells (Tab on the last cell adds a row),
/// Enter moves down a row (and adds one at the bottom), arrows leave the
/// table at its edges. Every change is written back as padded Markdown
/// through [onChanged]; the page keeps the Markdown, not a grid.
///
/// Like a spreadsheet, a drag across cells (or Shift+click, or Shift+Up and
/// Down) selects a block of cells: Ctrl+C copies it as tab-separated text,
/// Ctrl+X cuts, Delete empties it, and Ctrl+V pastes a copied block (from
/// here or from Excel) over it. The column borders drag to set widths;
/// double-clicking one makes the columns even again.
class TableBlockView extends StatefulWidget {
  const TableBlockView({
    super.key,
    required this.block,
    required this.focusNode,
    required this.readOnly,
    required this.onChanged,
    required this.onMoveOut,
    required this.onDelete,
  });

  final Block block;

  /// The block's focus node; the cells' nodes are its children, so the
  /// editor sees the block as focused while any cell is.
  final FocusNode focusNode;
  final bool readOnly;

  /// The table's new Markdown; [structural] for a row or column added or
  /// removed (its own undo step) rather than typing in a cell.
  final void Function(String markdown, {bool structural}) onChanged;

  /// Asked to move the caret to the neighbouring block; true when it did.
  final bool Function(AxisDirection direction) onMoveOut;
  final VoidCallback onDelete;

  static const headerHeight = 30.0;
  static const cellHeight = 34.0;

  /// Height of the whole block, known before it is built.
  static double heightFor(Block block) {
    final rows = TableData.parse(block.text)?.rowCount ?? 1;
    return 2 + headerHeight + rows * cellHeight;
  }

  static const cellStyle = TextStyle(fontSize: 14, height: 1.3);

  @override
  State<TableBlockView> createState() => TableBlockViewState();
}

class TableBlockViewState extends State<TableBlockView> {
  late TableData _data;

  /// The Markdown the grid was last read from or written to.
  String _written = '';
  List<List<_Cell>> _cells = const [];
  bool _hover = false;

  /// The selected block of cells, as (row, column) of the corner it started
  /// from and the corner that moves; null when the caret is in one cell.
  (int, int)? _anchor, _extent;

  /// The cell a mouse drag started in, while the button is down.
  (int, int)? _dragFrom;

  /// Column widths while a border is dragged, applied when it is let go.
  List<double>? _dragWidths;

  /// The widths the grid was last laid out with.
  List<double> _layoutWidths = const [];
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _read(widget.block.text);
  }

  @override
  void didUpdateWidget(TableBlockView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.block.text != _written) _read(widget.block.text);
  }

  @override
  void dispose() {
    _disposeCells();
    _scroll.dispose();
    super.dispose();
  }

  void _disposeCells() {
    for (final row in _cells) {
      for (final cell in row) {
        cell.dispose();
      }
    }
    _cells = const [];
  }

  /// Loads [markdown] into the grid (an undo, or the assistant's edit).
  void _read(String markdown) {
    _written = markdown;
    _data = TableData.parse(markdown) ??
        TableData([
          ['']
        ], [
          TableAlign.none
        ]);
    _rebuildCells();
    _anchor = _extent = null;
  }

  void _rebuildCells() {
    _disposeCells();
    _cells = [
      for (var r = 0; r < _data.rowCount; r++)
        [
          for (var c = 0; c < _data.columns; c++)
            _Cell(_data.rows[r][c], FocusNode(debugLabel: 'cell $r,$c')..addListener(_onCellFocus))
        ]
    ];
  }

  /// The header buttons act on the focused cell, so they follow it.
  void _onCellFocus() {
    if (mounted) setState(() {});
  }

  void _emit({bool structural = false}) {
    _written = _data.toMarkdown();
    widget.onChanged(_written, structural: structural);
  }

  (int, int)? get _focused {
    for (var r = 0; r < _cells.length; r++) {
      for (var c = 0; c < _cells[r].length; c++) {
        if (_cells[r][c].focus.hasFocus) return (r, c);
      }
    }
    return null;
  }

  /// Puts the caret in a cell, at its end (or [atStart]).
  void focusCell(int row, int column, {bool atStart = false}) {
    if (_cells.isEmpty) return;
    final r = row.clamp(0, _cells.length - 1);
    final c = column.clamp(0, _cells[r].length - 1);
    final cell = _cells[r][c];
    cell.focus.requestFocus();
    final length = cell.text.text.length;
    cell.text.selection = TextSelection.collapsed(offset: atStart ? 0 : length);
  }

  void focusFirst() => focusCell(0, 0, atStart: true);
  void focusLast() => focusCell(_cells.length - 1, _data.columns - 1);

  /// True between a change of shape and the caret landing in the new grid,
  /// so the buttons stay while the old cells are gone and the new ones are
  /// not focused yet.
  bool _refocusing = false;

  /// Focuses a cell once the grid has been rebuilt with it.
  void _focusAfterBuild(int row, int column) {
    _refocusing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refocusing = false;
      if (mounted) focusCell(row, column);
    });
  }

  void _addRow(int after) {
    final at = (after + 1).clamp(1, _data.rowCount);
    _data.insertRow(at);
    setState(_rebuildCells);
    _emit(structural: true);
    _focusAfterBuild(at, _focused?.$2 ?? 0);
  }

  void _removeRow(int row) {
    final column = _focused?.$2 ?? 0;
    if (!_data.removeRow(row)) return;
    setState(_rebuildCells);
    _emit(structural: true);
    _focusAfterBuild(row.clamp(0, _data.rowCount - 1), column);
  }

  void _addColumn(int after) {
    final row = _focused?.$1 ?? 0;
    final at = (after + 1).clamp(0, _data.columns);
    _data.insertColumn(at, header: 'Column ${at + 1}');
    setState(_rebuildCells);
    _emit(structural: true);
    _focusAfterBuild(row, at);
  }

  void _removeColumn(int column) {
    final row = _focused?.$1 ?? 0;
    if (!_data.removeColumn(column)) return;
    setState(_rebuildCells);
    _emit(structural: true);
    _focusAfterBuild(row, column.clamp(0, _data.columns - 1));
  }

  // The selected block of cells.

  bool get hasCellRange => _anchor != null;

  /// The selected cells as (top, left, bottom, right), or null.
  (int, int, int, int)? get cellRange {
    final a = _anchor, e = _extent;
    if (a == null || e == null) return null;
    return (a.$1 < e.$1 ? a.$1 : e.$1, a.$2 < e.$2 ? a.$2 : e.$2, a.$1 > e.$1 ? a.$1 : e.$1, a.$2 > e.$2 ? a.$2 : e.$2);
  }

  bool _inRange(int row, int column) {
    final range = cellRange;
    if (range == null) return false;
    final (top, left, bottom, right) = range;
    return row >= top && row <= bottom && column >= left && column <= right;
  }

  /// Selects the cells from [from] to [to] and takes the keys for the table,
  /// so no cell shows a caret while a block of them is selected.
  void selectCells((int, int) from, (int, int) to) {
    final last = (_data.rowCount - 1, _data.columns - 1);
    (int, int) clamp((int, int) at) => (at.$1.clamp(0, last.$1), at.$2.clamp(0, last.$2));
    setState(() {
      _anchor = clamp(from);
      _extent = clamp(to);
    });
    _holdRangeFocus();
  }

  /// Moves the keys to the table itself, now and again after the frame (a
  /// click still on its way to a cell would otherwise put the caret there),
  /// and drops any text selection the drag left inside a cell.
  void _holdRangeFocus() {
    void hold() {
      if (!mounted || !hasCellRange) return;
      if (!widget.focusNode.hasPrimaryFocus) widget.focusNode.requestFocus();
      for (final row in _cells) {
        for (final cell in row) {
          final sel = cell.text.selection;
          if (sel.isValid && !sel.isCollapsed) cell.text.selection = TextSelection.collapsed(offset: sel.extentOffset);
        }
      }
    }

    hold();
    WidgetsBinding.instance.addPostFrameCallback((_) => hold());
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Leaves the block of cells; the caret goes to [to] when given.
  void _clearRange({(int, int)? to, bool atStart = false}) {
    if (!hasCellRange) return;
    setState(() => _anchor = _extent = null);
    if (to == null) return;
    focusCell(to.$1, to.$2, atStart: atStart);
    // Focus coming back from the table selects the cell's text; keep the caret.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || to.$1 >= _cells.length || to.$2 >= _cells[to.$1].length) return;
      final text = _cells[to.$1][to.$2].text;
      if (!text.selection.isCollapsed) {
        text.selection = TextSelection.collapsed(offset: atStart ? 0 : text.text.length);
      }
    });
  }

  Future<void> _copyRange({bool cut = false}) async {
    final range = cellRange;
    if (range == null) return;
    final (top, left, bottom, right) = range;
    await Clipboard.setData(ClipboardData(text: _data.toTsv(top, left, bottom, right)));
    if (cut && !widget.readOnly) _clearCells();
  }

  void _clearCells() {
    final range = cellRange;
    if (range == null) return;
    final (top, left, bottom, right) = range;
    _data.clear(top, left, bottom, right);
    for (var r = top; r <= bottom; r++) {
      for (var c = left; c <= right; c++) {
        _cells[r][c].text.text = '';
      }
    }
    setState(() {});
    _emit(structural: true);
  }

  /// Pastes the clipboard over the selected cells, or from [at] when no
  /// block is selected. Text without a tab or line break goes into the cell
  /// at [at] like typing.
  Future<void> _paste({(int, int)? at}) async {
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (clip == null || clip.isEmpty || !mounted) return;
    final range = cellRange;
    var single = clip;
    if (single.endsWith('\r\n')) {
      single = single.substring(0, single.length - 2);
    } else if (single.endsWith('\n')) {
      single = single.substring(0, single.length - 1);
    }
    if (range == null && at != null && !single.contains(RegExp('[\t\n\r]'))) {
      final cell = _cells[at.$1][at.$2];
      final value = cell.text.value;
      final sel = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
      final text = value.text.replaceRange(sel.start, sel.end, single);
      cell.text.value =
          TextEditingValue(text: text, selection: TextSelection.collapsed(offset: sel.start + single.length));
      _data.setCell(at.$1, at.$2, text);
      _emit();
      return;
    }
    final (top, left, bottom, right) = range ?? (at!.$1, at.$2, at.$1, at.$2);
    final shape = (_data.rowCount, _data.columns);
    final (t, l, b, r) = _data.paste(top, left, bottom, right, TableData.parseTsv(clip));
    if (shape != (_data.rowCount, _data.columns)) {
      _rebuildCells();
    } else {
      for (var row = t; row <= b; row++) {
        for (var column = l; column <= r; column++) {
          _cells[row][column].text.text = _data.rows[row][column];
        }
      }
    }
    _emit(structural: true);
    if (t == b && l == r) {
      setState(() => _anchor = _extent = null);
      _focusAfterBuild(t, l);
    } else {
      selectCells((t, l), (b, r));
    }
  }

  KeyEventResult _onRangeKey(KeyEvent event) {
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final key = event.logicalKey;
    final anchor = _anchor!, extent = _extent!;
    if (ctrl) {
      if (key == LogicalKeyboardKey.keyC) {
        _copyRange();
      } else if (key == LogicalKeyboardKey.keyX) {
        _copyRange(cut: true);
      } else if (key == LogicalKeyboardKey.keyV) {
        if (!widget.readOnly) _paste();
      } else if (key == LogicalKeyboardKey.keyA) {
        selectCells((0, 0), (_data.rowCount - 1, _data.columns - 1));
      } else {
        return KeyEventResult.ignored; // undo and the app's shortcuts
      }
      return KeyEventResult.handled;
    }
    if (keys.isAltPressed) return KeyEventResult.ignored;
    final step = switch (key) {
      LogicalKeyboardKey.arrowUp => (-1, 0),
      LogicalKeyboardKey.arrowDown => (1, 0),
      LogicalKeyboardKey.arrowLeft => (0, -1),
      LogicalKeyboardKey.arrowRight => (0, 1),
      _ => null,
    };
    if (step != null) {
      final to = (extent.$1 + step.$1, extent.$2 + step.$2);
      if (keys.isShiftPressed) {
        selectCells(anchor, to);
      } else {
        _clearRange(to: (to.$1.clamp(0, _data.rowCount - 1), to.$2.clamp(0, _data.columns - 1)));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.tab ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _clearRange(to: anchor);
      return KeyEventResult.handled;
    }
    if (widget.readOnly) return KeyEventResult.handled;
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      _clearCells();
      return KeyEventResult.handled;
    }
    final typed = event.character;
    if (typed != null && typed.isNotEmpty && typed.codeUnitAt(0) >= 0x20 && typed.codeUnitAt(0) != 0x7f) {
      // Typing over a selection starts the first cell afresh, as in a spreadsheet.
      _clearRange(to: anchor);
      final cell = _cells[anchor.$1][anchor.$2];
      cell.text.value = TextEditingValue(text: typed, selection: TextSelection.collapsed(offset: typed.length));
      _data.setCell(anchor.$1, anchor.$2, typed);
      _emit();
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (hasCellRange) return _onRangeKey(event);
    if (widget.readOnly) return KeyEventResult.ignored;
    final at = _focused;
    if (at == null) return KeyEventResult.ignored;
    final (r, c) = at;
    final keys = HardwareKeyboard.instance;
    final shift = keys.isShiftPressed;
    final key = event.logicalKey;
    final last = _data.rowCount - 1, lastColumn = _data.columns - 1;
    if ((keys.isControlPressed || keys.isMetaPressed) && !keys.isAltPressed) {
      if (key == LogicalKeyboardKey.keyV) {
        _paste(at: at);
        return KeyEventResult.handled;
      }
      final text = _cells[r][c].text;
      if (key == LogicalKeyboardKey.keyA &&
          !shift &&
          (text.text.isEmpty || (text.selection.start == 0 && text.selection.end == text.text.length))) {
        // A second Ctrl+A, once the cell's text is all selected, takes the whole table.
        selectCells((0, 0), (last, lastColumn));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (keys.isAltPressed) return KeyEventResult.ignored;
    if (shift && (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown)) {
      final to = key == LogicalKeyboardKey.arrowUp ? r - 1 : r + 1;
      if (to >= 0 && to <= last) selectCells(at, (to, c));
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.tab) {
      if (shift) {
        if (c > 0) {
          focusCell(r, c - 1);
        } else if (r > 0) {
          focusCell(r - 1, lastColumn);
        }
      } else if (c < lastColumn) {
        focusCell(r, c + 1, atStart: true);
      } else if (r < last) {
        focusCell(r + 1, 0, atStart: true);
      } else {
        _addRow(r);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (shift) return KeyEventResult.handled; // cells hold one line
      if (r < last) {
        focusCell(r + 1, c);
      } else {
        _addRow(r);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (r > 0) {
        focusCell(r - 1, c);
        return KeyEventResult.handled;
      }
      return widget.onMoveOut(AxisDirection.up) ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (r < last) {
        focusCell(r + 1, c);
        return KeyEventResult.handled;
      }
      return widget.onMoveOut(AxisDirection.down) ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    final sel = _cells[r][c].text.selection;
    if (key == LogicalKeyboardKey.arrowLeft && sel.isCollapsed && sel.extentOffset == 0) {
      if (c > 0) {
        focusCell(r, c - 1);
      } else if (r > 0) {
        focusCell(r - 1, lastColumn);
      } else {
        return widget.onMoveOut(AxisDirection.left) ? KeyEventResult.handled : KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight && sel.isCollapsed && sel.extentOffset == _cells[r][c].text.text.length) {
      if (c < lastColumn) {
        focusCell(r, c + 1, atStart: true);
      } else if (r < last) {
        focusCell(r + 1, 0, atStart: true);
      } else {
        return widget.onMoveOut(AxisDirection.right) ? KeyEventResult.handled : KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onFocusChange(bool has) {
    // The editor focuses the block itself when the caret arrives from a
    // neighbour; that goes to the first cell.
    if (has && widget.focusNode.hasPrimaryFocus && !hasCellRange) focusFirst();
    if (!has) _anchor = _extent = null; // clicked away
    if (mounted) setState(() {});
  }

  // Mouse selection of cells.

  (int, int)? _cellAt(Offset local, {bool clamp = false}) {
    if (_layoutWidths.isEmpty) return null;
    var row = (local.dy / TableBlockView.cellHeight).floor();
    var column = 0, x = 0.0;
    while (column < _layoutWidths.length - 1 && local.dx >= x + _layoutWidths[column]) {
      x += _layoutWidths[column];
      column++;
    }
    if (!clamp && (row < 0 || row >= _data.rowCount || local.dx < 0 || local.dx > x + _layoutWidths[column])) {
      return null;
    }
    row = row.clamp(0, _data.rowCount - 1);
    return (row, column);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse || event.buttons != kPrimaryMouseButton) return;
    final hit = _cellAt(event.localPosition);
    if (hit == null) return;
    if (HardwareKeyboard.instance.isShiftPressed) {
      final from = _anchor ?? _focused;
      if (from != null && from != hit) {
        selectCells(from, hit);
        return;
      }
    }
    if (hasCellRange) setState(() => _anchor = _extent = null);
    _dragFrom = hit;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final from = _dragFrom;
    if (from == null) return;
    final hit = _cellAt(event.localPosition, clamp: true);
    if (hit == null || (!hasCellRange && hit == from) || hit == _extent) return;
    selectCells(from, hit);
  }

  void _onPointerUp(PointerEvent event) {
    _dragFrom = null;
    if (hasCellRange) _holdRangeFocus();
  }

  // Column widths.

  void _onResize(int column, double delta) {
    final widths = _dragWidths ??= List.of(_layoutWidths);
    setState(() => widths[column] = (widths[column] + delta).clamp(TableData.minWidth, 4000.0));
  }

  void _onResizeEnd() {
    final widths = _dragWidths;
    if (widths == null) return;
    _dragWidths = null;
    _data.widths = [for (final w in widths) w.roundToDouble()];
    setState(() {});
    _emit(structural: true);
  }

  /// Back to even columns that fill the page.
  void _resetWidths() {
    if (_data.widths == null) return;
    _data.widths = null;
    setState(() {});
    _emit(structural: true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    final focused = widget.focusNode.hasFocus;
    final showTools = (_hover || focused || _refocusing) && !widget.readOnly;
    final rows = _data.rowCount, columns = _data.columns;
    final (r, c) = _focused ?? (rows - 1, columns - 1);

    return Semantics(
      container: true,
      label: 'Table, $rows rows, $columns columns',
      child: Focus(
        focusNode: widget.focusNode,
        skipTraversal: true,
        onKeyEvent: _onKey,
        onFocusChange: _onFocusChange,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: focused ? palette.accentA : palette.barBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.all(1), // inside the border
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: TableBlockView.headerHeight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 2, 4, 0),
                      child: Row(children: [
                        Icon(Icons.table_chart_outlined, size: 14, color: palette.subText),
                        const SizedBox(width: 6),
                        Text('Table',
                            style:
                                TextStyle(color: palette.text, fontSize: StackType.hint, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        Text('$rows × $columns', style: TextStyle(color: palette.subText, fontSize: StackType.hint)),
                        const Spacer(),
                        if (showTools) ...[
                          HeaderButton(
                            tooltip: 'Add row below',
                            semanticLabel: 'Add row below',
                            onPressed: () => _addRow(r),
                            child: Icon(Icons.playlist_add, size: 17, color: palette.subText),
                          ),
                          HeaderButton(
                            tooltip: 'Add column after',
                            semanticLabel: 'Add column after',
                            onPressed: () => _addColumn(c),
                            child: Icon(Icons.view_column_outlined, size: 16, color: palette.subText),
                          ),
                          HeaderButton(
                            tooltip: r == 0 ? 'The header row stays' : 'Delete row',
                            semanticLabel: 'Delete row',
                            onPressed: r == 0 ? null : () => _removeRow(r),
                            child: Icon(Icons.playlist_remove,
                                size: 17, color: r == 0 ? palette.barBorder : palette.subText),
                          ),
                          HeaderButton(
                            tooltip: columns == 1 ? 'The last column stays' : 'Delete column',
                            semanticLabel: 'Delete column',
                            onPressed: columns == 1 ? null : () => _removeColumn(c),
                            child: Icon(Icons.remove_circle_outline,
                                size: 16, color: columns == 1 ? palette.barBorder : palette.subText),
                          ),
                          HeaderButton(
                            tooltip: 'Delete table',
                            semanticLabel: 'Delete table',
                            onPressed: widget.onDelete,
                            child: Icon(Icons.delete_outline, size: 16, color: palette.subText),
                          ),
                        ],
                      ]),
                    ),
                  ),
                  LayoutBuilder(builder: (context, constraints) => _grid(palette, constraints.maxWidth)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The cells, with a drag handle on each column's right border; wider
  /// than the page, it scrolls sideways.
  Widget _grid(StackPalette palette, double available) {
    final rows = _data.rowCount, columns = _data.columns;
    final widths = _dragWidths ?? _data.widths ?? List<double>.filled(columns, available / columns);
    _layoutWidths = widths;
    final total = widths.fold(0.0, (a, b) => a + b);
    var edge = 0.0;
    Widget grid = Stack(children: [
      Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerUp,
        child: Table(
          columnWidths: {for (var c = 0; c < columns; c++) c: FixedColumnWidth(widths[c])},
          border: TableBorder(
            top: BorderSide(color: palette.barBorder),
            horizontalInside: BorderSide(color: palette.barBorder),
            verticalInside: BorderSide(color: palette.barBorder),
          ),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            for (var row = 0; row < rows; row++)
              TableRow(
                decoration: row == 0 ? BoxDecoration(color: palette.panel) : null,
                children: [
                  for (var column = 0; column < columns; column++) _cellField(palette, row, column),
                ],
              ),
          ],
        ),
      ),
      if (!widget.readOnly)
        for (var c = 0; c < columns; c++)
          Positioned(
            // The last border's handle stays inside the grid, where it can be hit.
            left: (edge += widths[c]) - (c == columns - 1 ? _ColumnResizeHandle.width : _ColumnResizeHandle.width / 2),
            top: 0,
            bottom: 0,
            width: _ColumnResizeHandle.width,
            child: _ColumnResizeHandle(
              key: ValueKey('resize-${widget.block.id}-$c'),
              column: c,
              onDrag: (delta) => _onResize(c, delta),
              onDragEnd: _onResizeEnd,
              onReset: _resetWidths,
            ),
          ),
    ]);
    if (total > available + 0.5) {
      grid = Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: grid,
        ),
      );
    }
    return Align(alignment: Alignment.topLeft, child: grid);
  }

  Widget _cellField(StackPalette palette, int row, int column) {
    final cell = _cells[row][column];
    final align = switch (_data.aligns[column]) {
      TableAlign.center => TextAlign.center,
      TableAlign.right => TextAlign.right,
      _ => TextAlign.left,
    };
    return Container(
      height: TableBlockView.cellHeight,
      color: _inRange(row, column) ? palette.accentA.withAlpha(46) : null,
      child: Center(
        child: TextField(
          key: ValueKey('cell-${widget.block.id}-$row-$column'),
          controller: cell.text,
          focusNode: cell.focus,
          readOnly: widget.readOnly,
          maxLines: 1,
          textAlign: align,
          style: TableBlockView.cellStyle.copyWith(
            color: palette.text,
            fontWeight: row == 0 ? FontWeight.w600 : FontWeight.normal,
          ),
          strutStyle: StrutStyle.fromTextStyle(TableBlockView.cellStyle, forceStrutHeight: true),
          cursorColor: palette.accentA,
          decoration: InputDecoration(
            isCollapsed: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            hintText: row == 0 ? 'Header' : null,
            hintStyle: TextStyle(color: palette.subText.withAlpha(120)),
          ),
          onChanged: (value) {
            _data.setCell(row, column, value);
            _emit();
          },
        ),
      ),
    );
  }
}

/// The grab strip on a column's right border: drag to set the width,
/// double-click for even columns.
class _ColumnResizeHandle extends StatefulWidget {
  const _ColumnResizeHandle(
      {super.key, required this.column, required this.onDrag, required this.onDragEnd, required this.onReset});

  static const width = 8.0;

  final int column;
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;

  @override
  State<_ColumnResizeHandle> createState() => _ColumnResizeHandleState();
}

class _ColumnResizeHandleState extends State<_ColumnResizeHandle> {
  bool _hover = false, _dragging = false;

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    return Semantics(
      label: 'Resize column ${widget.column + 1}',
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
          onHorizontalDragEnd: (_) {
            setState(() => _dragging = false);
            widget.onDragEnd();
          },
          onHorizontalDragCancel: () {
            setState(() => _dragging = false);
            widget.onDragEnd();
          },
          onDoubleTap: widget.onReset,
          child: Center(
            child: Container(
              width: 2,
              color: _hover || _dragging ? palette.accentA : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}

class _Cell {
  _Cell(String value, this.focus) : text = TextEditingController(text: value);
  final TextEditingController text;
  final FocusNode focus;

  void dispose() {
    text.dispose();
    focus.dispose();
  }
}
