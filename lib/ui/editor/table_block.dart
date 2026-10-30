import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../editor/blocks.dart';
import '../../editor/table_data.dart';
import 'block_metrics.dart';
import 'header_button.dart';

/// A table block as a grid of cells: a header strip with the row and column
/// buttons, then one field per cell.
///
/// Tab moves to the next cell (on the last cell it adds a row), Ctrl+Shift+Tab
/// to the previous one; Shift+Tab and Shift+Enter start a new line in the
/// cell. Enter moves down a row (and adds one at the bottom), arrows leave
/// the table at its edges. Every change is written back as padded Markdown
/// through [onChanged]; the page keeps the Markdown, not a grid.
///
/// Text wraps in a column unless that column is set not to, and a row is as
/// tall as its tallest cell. Right-click a cell (or the ⋯ button, or
/// Shift+F10) for the table menu: insert rows and columns above, below, left
/// and right, duplicate, sort, filter, align, colour, wrap and header row.
/// The grips that show on the hovered row's left edge and column's top edge
/// drag rows and columns to new places; Alt+Shift+arrows move them from the
/// keyboard.
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

  /// Height of a row whose cells hold one line.
  static const cellHeight = 34.0;

  static const cellStyle = TextStyle(fontSize: 14, height: 1.3);

  /// Space around the text of a cell: left and right padding, and the room
  /// a text field keeps for the caret at the right.
  static const _cellPadding = 10.0;
  static const _caretMargin = 1.0 + 2.0;

  /// Space above and below the lines of a cell that holds more than one.
  static const _linePadding = cellHeight - 14 * 1.3;

  /// Height of the whole block at [width] (the row width), mirroring [build]:
  /// the border, the header strip and each row that the filters leave.
  static double heightFor(Block block, double width, {required TextScaler textScaler, required TextStyle inputStyle}) {
    final data = TableData.parse(block.text);
    if (data == null) return 2 + headerHeight + cellHeight;
    final widths = columnWidths(data, width - 2);
    var height = 2 + headerHeight;
    for (final r in data.visibleRows) {
      height += rowHeight(data, r, widths, textScaler, inputStyle);
    }
    return height;
  }

  /// The width of each column inside [available]: the widths set by
  /// dragging, or even columns that fill it.
  static List<double> columnWidths(TableData data, double available) =>
      data.widths ?? List<double>.filled(data.columns, available / data.columns);

  /// The style a cell's text field lays its text out with.
  static TextStyle textStyle(TextStyle inputStyle, {required bool bold}) =>
      inputStyle.merge(cellStyle.copyWith(fontWeight: bold ? FontWeight.w600 : FontWeight.normal));

  static final _strut = StrutStyle.fromTextStyle(cellStyle, forceStrutHeight: true);

  /// Whether the cell's field shows more than one line: its column wraps,
  /// or it holds a line break.
  static bool multiline(TableData data, int row, int column) =>
      data.wrap[column] || data.rows[row][column].contains('\n');

  static final _measured = <(String, double, bool, TextScaler, TextStyle), double>{};

  /// Height of row [row] at the column [widths]: [cellHeight] when every
  /// cell fits on one line, else its tallest cell's lines plus padding.
  static double rowHeight(TableData data, int row, List<double> widths, TextScaler textScaler, TextStyle inputStyle) {
    final bold = data.header && row == 0;
    final style = textStyle(inputStyle, bold: bold);
    var tallest = 0.0;
    for (var c = 0; c < data.columns; c++) {
      final text = data.rows[row][c];
      if (text.isEmpty || !multiline(data, row, c)) continue;
      final width = math.max(0.0, widths[c] - 2 * _cellPadding - _caretMargin);
      final key = (text, width, bold, textScaler, style);
      var height = _measured[key];
      if (height == null) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
          strutStyle: _strut,
        )..layout(maxWidth: width);
        final lines = painter.computeLineMetrics().length;
        height = lines <= 1 ? 0.0 : painter.height;
        painter.dispose();
        if (_measured.length > 4000) _measured.clear();
        _measured[key] = height;
      }
      if (height > tallest) tallest = height;
    }
    return tallest == 0 ? cellHeight : math.max(cellHeight, tallest + _linePadding);
  }

  @override
  State<TableBlockView> createState() => TableBlockViewState();
}

/// What the table menu can do.
enum _TableAction {
  insertRowAbove,
  insertRowBelow,
  insertColumnLeft,
  insertColumnRight,
  duplicateRow,
  duplicateColumn,
  sortAscending,
  sortDescending,
  filter,
  clearFilters,
  align,
  color,
  wrap,
  header,
  cut,
  copy,
  paste,
  clear,
  deleteRows,
  deleteColumns,
  deleteTable,
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

  /// The widths, rows and row heights the grid was last laid out with.
  List<double> _layoutWidths = const [];
  List<int> _layoutRows = const [];
  List<double> _layoutHeights = const [];
  final _scroll = ScrollController();
  final _gridKey = GlobalKey();

  /// The cell under the mouse, for the row and column grips.
  (int, int)? _hoverCell;

  /// The row or column being dragged by its grip, and the row or column it
  /// would land before (in the table's own order) if let go now.
  int? _movingRow, _movingColumn, _dropBefore;

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

  /// A change of shape or order: the cells are made again from the data,
  /// written back as one undo step, and the caret goes to ([row], [column]).
  void _reshaped(int row, int column) {
    setState(() {
      _anchor = _extent = null;
      _rebuildCells();
    });
    _emit(structural: true);
    _focusAfterBuild(row, column);
  }

  (int, int)? get _focused {
    for (var r = 0; r < _cells.length; r++) {
      for (var c = 0; c < _cells[r].length; c++) {
        if (_cells[r][c].focus.hasFocus) return (r, c);
      }
    }
    return null;
  }

  /// Puts the caret in a cell, at its end (or [atStart]). A row the filters
  /// hide gives way to the nearest one that shows.
  void focusCell(int row, int column, {bool atStart = false}) {
    if (_cells.isEmpty) return;
    var r = row.clamp(0, _cells.length - 1);
    if (!_data.rowVisible(r)) {
      final shown = _data.visibleRows;
      if (shown.isEmpty) return;
      r = shown.firstWhere((v) => v >= r, orElse: () => shown.last);
    }
    final c = column.clamp(0, _cells[r].length - 1);
    final cell = _cells[r][c];
    cell.focus.requestFocus();
    final length = cell.text.text.length;
    cell.text.selection = TextSelection.collapsed(offset: atStart ? 0 : length);
  }

  void focusFirst() {
    final shown = _data.visibleRows;
    focusCell(shown.isEmpty ? 0 : shown.first, 0, atStart: true);
  }

  void focusLast() {
    final shown = _data.visibleRows;
    focusCell(shown.isEmpty ? _cells.length - 1 : shown.last, _data.columns - 1);
  }

  /// The row that shows above [row], or null at the top.
  int? _rowAbove(int row) {
    for (var r = row - 1; r >= 0; r--) {
      if (_data.rowVisible(r)) return r;
    }
    return null;
  }

  /// The row that shows below [row], or null at the bottom.
  int? _rowBelow(int row) {
    for (var r = row + 1; r < _data.rowCount; r++) {
      if (_data.rowVisible(r)) return r;
    }
    return null;
  }

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

  void _addRow(int after, {int? column}) => _insertRow(after + 1, column: column);

  /// Adds an empty row at [at] (0 puts it above the first row); the caret
  /// goes to its cell in [column], or in the focused cell's column.
  void _insertRow(int at, {int? column}) {
    column ??= _focused?.$2 ?? _anchor?.$2 ?? 0;
    final r = at.clamp(0, _data.rowCount);
    _data.insertRow(r);
    _reshaped(r, column);
  }

  void _addColumn(int after) => _insertColumn(after + 1);

  void _insertColumn(int at) {
    final row = _focused?.$1 ?? _anchor?.$1 ?? 0;
    final c = at.clamp(0, _data.columns);
    _data.insertColumn(c, header: 'Column ${c + 1}');
    _reshaped(row, c);
  }

  /// Removes the rows from [top] to [bottom]; the last row stays.
  void _removeRows(int top, int bottom) {
    final column = _focused?.$2 ?? _anchor?.$2 ?? 0;
    var removed = false;
    for (var r = bottom; r >= top; r--) {
      removed = _data.removeRow(r) || removed;
    }
    if (!removed) return;
    _reshaped(top.clamp(0, _data.rowCount - 1), column);
  }

  void _removeRow(int row) => _removeRows(row, row);

  /// Removes the columns from [left] to [right]; the last column stays.
  void _removeColumns(int left, int right) {
    final row = _focused?.$1 ?? _anchor?.$1 ?? 0;
    var removed = false;
    for (var c = right; c >= left; c--) {
      removed = _data.removeColumn(c) || removed;
    }
    if (!removed) return;
    _reshaped(row, left.clamp(0, _data.columns - 1));
  }

  void _removeColumn(int column) => _removeColumns(column, column);

  void _moveRow(int from, int before) {
    final column = _focused?.$2 ?? 0;
    _data.moveRow(from, before);
    _reshaped(before > from ? before - 1 : before, column);
  }

  void _moveColumn(int from, int before) {
    final row = _focused?.$1 ?? 0;
    _data.moveColumn(from, before);
    _reshaped(row, before > from ? before - 1 : before);
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
      setState(() {});
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

  /// Starts a new line at the caret in the cell at ([r], [c]).
  void _newLine(int r, int c) {
    final cell = _cells[r][c];
    final value = cell.text.value;
    final sel = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
    final text = value.text.replaceRange(sel.start, sel.end, '\n');
    cell.text.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: sel.start + 1));
    _data.setCell(r, c, text);
    setState(() {}); // the field may become a multi-line one
    _emit();
  }

  /// The text layout of a cell's field, to tell which line the caret is on.
  RenderEditable? _editableOf(_Cell cell) {
    RenderEditable? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderEditable) {
        found = object;
        return;
      }
      object.visitChildren(visit);
    }

    final root = cell.focus.context?.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  /// Whether the caret of the cell at ([r], [c]) can go [up] (or down) a
  /// line inside the cell, rather than to the next row.
  bool _caretCanMoveInside(int r, int c, {required bool up}) {
    if (!TableBlockView.multiline(_data, r, c)) return false;
    final cell = _cells[r][c];
    final editable = _editableOf(cell);
    final sel = cell.text.selection;
    if (editable == null || !sel.isValid) return false;
    final caret = editable.getLocalRectForCaret(TextPosition(offset: sel.extentOffset));
    final line = editable.preferredLineHeight;
    final last = editable.getLocalRectForCaret(TextPosition(offset: cell.text.text.length));
    return up ? caret.top > line / 2 : caret.top < last.top - line / 2;
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
    if (_isMenuKey(event)) {
      if (!widget.readOnly) _openMenuForKeys();
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
      var row = extent.$1;
      if (step.$1 < 0) row = _rowAbove(row) ?? row;
      if (step.$1 > 0) row = _rowBelow(row) ?? row;
      final to = (row, extent.$2 + step.$2);
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

  /// Shift+F10 or the menu key: the keyboard's right-click.
  bool _isMenuKey(KeyEvent event) =>
      event.logicalKey == LogicalKeyboardKey.contextMenu ||
      (event.logicalKey == LogicalKeyboardKey.f10 && HardwareKeyboard.instance.isShiftPressed);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (hasCellRange) return _onRangeKey(event);
    if (widget.readOnly) return KeyEventResult.ignored;
    final at = _focused;
    if (at == null) return KeyEventResult.ignored;
    final (r, c) = at;
    final keys = HardwareKeyboard.instance;
    final shift = keys.isShiftPressed;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final key = event.logicalKey;
    final lastColumn = _data.columns - 1;
    if (_isMenuKey(event)) {
      _openMenuForKeys();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab && !keys.isAltPressed) {
      if (shift && !ctrl) {
        _newLine(r, c);
      } else if (shift) {
        // Ctrl+Shift+Tab: back a cell.
        final above = _rowAbove(r);
        if (c > 0) {
          focusCell(r, c - 1);
        } else if (above != null) {
          focusCell(above, lastColumn);
        }
      } else if (c < lastColumn) {
        focusCell(r, c + 1, atStart: true);
      } else if (_rowBelow(r) case final below?) {
        focusCell(below, 0, atStart: true);
      } else {
        _addRow(r, column: 0);
      }
      return KeyEventResult.handled;
    }
    if (ctrl && !keys.isAltPressed) {
      if (key == LogicalKeyboardKey.keyV) {
        _paste(at: at);
        return KeyEventResult.handled;
      }
      final text = _cells[r][c].text;
      if (key == LogicalKeyboardKey.keyA &&
          !shift &&
          (text.text.isEmpty || (text.selection.start == 0 && text.selection.end == text.text.length))) {
        // A second Ctrl+A, once the cell's text is all selected, takes the whole table.
        selectCells((0, 0), (_data.rowCount - 1, lastColumn));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (keys.isAltPressed && shift) {
      // Alt+Shift+arrows move the row or column, like dragging its grip.
      final first = _data.firstBodyRow;
      if (key == LogicalKeyboardKey.arrowUp && r > first) {
        _moveRow(r, _rowAbove(r) ?? r);
      } else if (key == LogicalKeyboardKey.arrowDown && r >= first) {
        if (_rowBelow(r) case final below?) _moveRow(r, below + 1);
      } else if (key == LogicalKeyboardKey.arrowLeft && c > 0) {
        _moveColumn(c, c - 1);
      } else if (key == LogicalKeyboardKey.arrowRight && c < lastColumn) {
        _moveColumn(c, c + 2);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (keys.isAltPressed) return KeyEventResult.ignored;
    if (shift && (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown)) {
      final up = key == LogicalKeyboardKey.arrowUp;
      if (_caretCanMoveInside(r, c, up: up)) return KeyEventResult.ignored; // select lines in the cell
      final to = up ? _rowAbove(r) : _rowBelow(r);
      if (to != null) selectCells(at, (to, c));
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (shift) {
        _newLine(r, c);
      } else if (_rowBelow(r) case final below?) {
        focusCell(below, c);
      } else {
        _addRow(r);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (_caretCanMoveInside(r, c, up: true)) return KeyEventResult.ignored;
      if (_rowAbove(r) case final above?) {
        focusCell(above, c);
        return KeyEventResult.handled;
      }
      return widget.onMoveOut(AxisDirection.up) ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_caretCanMoveInside(r, c, up: false)) return KeyEventResult.ignored;
      if (_rowBelow(r) case final below?) {
        focusCell(below, c);
        return KeyEventResult.handled;
      }
      return widget.onMoveOut(AxisDirection.down) ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    final sel = _cells[r][c].text.selection;
    if (key == LogicalKeyboardKey.arrowLeft && sel.isCollapsed && sel.extentOffset == 0) {
      final above = _rowAbove(r);
      if (c > 0) {
        focusCell(r, c - 1);
      } else if (above != null) {
        focusCell(above, lastColumn);
      } else {
        return widget.onMoveOut(AxisDirection.left) ? KeyEventResult.handled : KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight && sel.isCollapsed && sel.extentOffset == _cells[r][c].text.text.length) {
      final below = _rowBelow(r);
      if (c < lastColumn) {
        focusCell(r, c + 1, atStart: true);
      } else if (below != null) {
        focusCell(below, 0, atStart: true);
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
    if (has && widget.focusNode.hasPrimaryFocus && !hasCellRange && !_menuOpen) focusFirst();
    if (!has && !_menuOpen) _anchor = _extent = null; // clicked away
    if (mounted) setState(() {});
  }

  // Mouse selection of cells.

  (int, int)? _cellAt(Offset local, {bool clamp = false}) {
    if (_layoutWidths.isEmpty || _layoutRows.isEmpty) return null;
    var visible = 0;
    var y = 0.0;
    while (visible < _layoutRows.length - 1 && local.dy >= y + _layoutHeights[visible]) {
      y += _layoutHeights[visible];
      visible++;
    }
    var column = 0, x = 0.0;
    while (column < _layoutWidths.length - 1 && local.dx >= x + _layoutWidths[column]) {
      x += _layoutWidths[column];
      column++;
    }
    if (!clamp &&
        (local.dy < 0 ||
            local.dy > y + _layoutHeights[visible] ||
            local.dx < 0 ||
            local.dx > x + _layoutWidths[column])) {
      return null;
    }
    return (_layoutRows[visible], column);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    final hit = _cellAt(event.localPosition);
    if (hit == null) return;
    if (event.buttons == kSecondaryMouseButton) {
      if (widget.readOnly) return;
      if (!_inRange(hit.$1, hit.$2)) {
        if (hasCellRange) setState(() => _anchor = _extent = null);
        if (_focused != hit) focusCell(hit.$1, hit.$2);
      }
      _openMenu(hit, event.position);
      return;
    }
    if (event.buttons != kPrimaryMouseButton) return;
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

  void _onHover(PointerHoverEvent event) {
    if (widget.readOnly || _movingRow != null || _movingColumn != null) return;
    final hit = _cellAt(event.localPosition);
    if (hit != _hoverCell) setState(() => _hoverCell = hit);
  }

  // Dragging rows and columns by their grips.

  Offset? _toGrid(Offset global) {
    final box = _gridKey.currentContext?.findRenderObject();
    return box is RenderBox ? box.globalToLocal(global) : null;
  }

  /// The row a dragged row would land before, for the pointer at [y].
  int _rowDropAt(double y) {
    var top = 0.0;
    for (var v = 0; v < _layoutRows.length; v++) {
      if (y < top + _layoutHeights[v] / 2) return math.max(_layoutRows[v], _data.firstBodyRow);
      top += _layoutHeights[v];
    }
    return _data.rowCount;
  }

  int _columnDropAt(double x) {
    var left = 0.0;
    for (var c = 0; c < _layoutWidths.length; c++) {
      if (x < left + _layoutWidths[c] / 2) return c;
      left += _layoutWidths[c];
    }
    return _data.columns;
  }

  void _startMove({int? row, int? column}) {
    setState(() {
      _movingRow = row;
      _movingColumn = column;
      _dropBefore = null;
      _anchor = _extent = null;
    });
  }

  void _updateMove(Offset global) {
    final local = _toGrid(global);
    if (local == null) return;
    final before = _movingRow != null ? _rowDropAt(local.dy) : _columnDropAt(local.dx);
    if (before != _dropBefore) setState(() => _dropBefore = before);
  }

  void _endMove({bool cancelled = false}) {
    final row = _movingRow, column = _movingColumn, before = _dropBefore;
    setState(() {
      _movingRow = _movingColumn = _dropBefore = null;
      _hoverCell = null;
    });
    if (cancelled || before == null) return;
    if (row != null && before != row && before != row + 1) _moveRow(row, before);
    if (column != null && before != column && before != column + 1) _moveColumn(column, before);
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

  // The table menu.

  /// True while the menu (or a dialog it opened) is up, so the focus it
  /// takes doesn't drop the selected cells.
  bool _menuOpen = false;
  final _menuButtonKey = GlobalKey();

  /// Opens the menu for the focused cell (or the selected cells) from the
  /// keyboard, under that cell.
  void _openMenuForKeys() {
    final at = _anchor ?? _focused;
    if (at == null) return;
    final context = _cells[at.$1][at.$2].focus.context;
    final box = context?.findRenderObject();
    final position = box is RenderBox ? box.localToGlobal(Offset(0, box.size.height)) : Offset.zero;
    _openMenu(at, position);
  }

  void _openMenuFromButton() {
    final at = _anchor ?? _focused ?? (_data.rowCount - 1, _data.columns - 1);
    final box = _menuButtonKey.currentContext?.findRenderObject();
    final position = box is RenderBox ? box.localToGlobal(Offset(0, box.size.height)) : Offset.zero;
    _openMenu(at, position);
  }

  Future<void> _openMenu((int, int) at, Offset position) async {
    final (r, c) = at;
    final range = cellRange ?? (r, c, r, c);
    final (top, left, bottom, right) = range;
    final rowsSelected = bottom - top + 1, columnsSelected = right - left + 1;
    final palette = StackColors.of(context);
    final columnName = _columnName(c);
    _menuOpen = true;
    final action = await showMenu<_TableAction>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        _item(_TableAction.insertRowAbove, Icons.north, 'Insert row above', palette),
        _item(_TableAction.insertRowBelow, Icons.south, 'Insert row below', palette),
        _item(_TableAction.insertColumnLeft, Icons.west, 'Insert column left', palette),
        _item(_TableAction.insertColumnRight, Icons.east, 'Insert column right', palette),
        const PopupMenuDivider(),
        _item(_TableAction.duplicateRow, Icons.copy_outlined, 'Duplicate row', palette),
        _item(_TableAction.duplicateColumn, Icons.copy_all_outlined, 'Duplicate column', palette),
        const PopupMenuDivider(),
        _item(_TableAction.sortAscending, Icons.arrow_downward, 'Sort by $columnName, A → Z', palette,
            enabled: _data.rowCount - _data.firstBodyRow > 1),
        _item(_TableAction.sortDescending, Icons.arrow_upward, 'Sort by $columnName, Z → A', palette,
            enabled: _data.rowCount - _data.firstBodyRow > 1),
        _item(_TableAction.filter, Icons.filter_alt_outlined,
            _data.filters[c] == null ? 'Filter by $columnName…' : 'Edit filter on $columnName…', palette),
        if (_data.isFiltered) _item(_TableAction.clearFilters, Icons.filter_alt_off_outlined, 'Clear filters', palette),
        const PopupMenuDivider(),
        _item(_TableAction.align, Icons.format_align_left, 'Align column', palette, submenu: true),
        _item(_TableAction.color, Icons.format_color_fill, 'Cell colour', palette, submenu: true),
        _item(_TableAction.wrap, Icons.wrap_text, 'Wrap text in column', palette, checked: _data.wrap[c]),
        _item(_TableAction.header, Icons.table_rows_outlined, 'Header row', palette, checked: _data.header),
        const PopupMenuDivider(),
        _item(_TableAction.cut, Icons.content_cut, 'Cut', palette, shortcut: 'Ctrl+X'),
        _item(_TableAction.copy, Icons.content_copy, 'Copy', palette, shortcut: 'Ctrl+C'),
        _item(_TableAction.paste, Icons.content_paste, 'Paste', palette, shortcut: 'Ctrl+V'),
        _item(_TableAction.clear, Icons.backspace_outlined, 'Clear contents', palette, shortcut: 'Delete'),
        const PopupMenuDivider(),
        _item(_TableAction.deleteRows, Icons.playlist_remove,
            rowsSelected > 1 ? 'Delete $rowsSelected rows' : 'Delete row', palette,
            enabled: _data.rowCount > rowsSelected),
        _item(_TableAction.deleteColumns, Icons.remove_circle_outline,
            columnsSelected > 1 ? 'Delete $columnsSelected columns' : 'Delete column', palette,
            enabled: _data.columns > columnsSelected),
        _item(_TableAction.deleteTable, Icons.delete_outline, 'Delete table', palette, danger: true),
      ],
    );
    if (!mounted) return;
    if (action == null) {
      _menuOpen = false;
      _restoreFocus(at);
      return;
    }
    await _run(action, at, range, position);
    _menuOpen = false;
  }

  /// After the menu closes without changing the shape, the caret (or the
  /// selected cells) come back.
  void _restoreFocus((int, int) at) {
    if (hasCellRange) {
      _holdRangeFocus();
    } else if (at.$1 < _cells.length && at.$2 < _cells[at.$1].length) {
      final cell = _cells[at.$1][at.$2];
      final sel = cell.text.selection;
      cell.focus.requestFocus();
      if (sel.isValid) cell.text.selection = sel;
    }
  }

  String _columnName(int c) {
    final name = _data.header ? _data.rows[0][c].trim().replaceAll('\n', ' ') : '';
    if (name.isEmpty) return 'column ${c + 1}';
    return name.length > 24 ? '${name.substring(0, 23)}…' : name;
  }

  PopupMenuItem<_TableAction> _item(_TableAction value, IconData icon, String label, StackPalette palette,
      {bool enabled = true, bool submenu = false, bool? checked, String? shortcut, bool danger = false}) {
    final color = danger ? palette.error : null;
    return PopupMenuItem(
      value: value,
      enabled: enabled,
      height: 32,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 17, color: color ?? palette.subText),
        const SizedBox(width: 10),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: color))),
        if (submenu || checked != null || shortcut != null) const SizedBox(width: 24),
        if (submenu) Icon(Icons.chevron_right, size: 16, color: palette.subText),
        if (checked != null)
          Icon(checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 17, color: checked ? palette.accentA : palette.subText, semanticLabel: checked ? 'on' : 'off'),
        if (shortcut != null) Text(shortcut, style: TextStyle(color: palette.subText, fontSize: StackType.hint)),
      ]),
    );
  }

  Future<void> _run(_TableAction action, (int, int) at, (int, int, int, int) range, Offset position) async {
    final (r, c) = at;
    final (top, left, bottom, right) = range;
    switch (action) {
      case _TableAction.insertRowAbove:
        _insertRow(top);
      case _TableAction.insertRowBelow:
        _insertRow(bottom + 1);
      case _TableAction.insertColumnLeft:
        _insertColumn(left);
      case _TableAction.insertColumnRight:
        _insertColumn(right + 1);
      case _TableAction.duplicateRow:
        _data.duplicateRow(r);
        _reshaped(r + 1, c);
      case _TableAction.duplicateColumn:
        _data.duplicateColumn(c);
        _reshaped(r, c + 1);
      case _TableAction.sortAscending || _TableAction.sortDescending:
        _data.sortBy(c, descending: action == _TableAction.sortDescending);
        _reshaped(r, c);
      case _TableAction.filter:
        final result = await showTableFilterDialog(context, _columnName(c), _data.filters[c]);
        if (!mounted) return;
        if (result == null) {
          _restoreFocus(at);
          return;
        }
        _data.filters[c] = result.filter;
        final shown = _data.visibleRows;
        _reshaped(shown.contains(r) ? r : (shown.length > _data.firstBodyRow ? shown[_data.firstBodyRow] : 0), c);
      case _TableAction.clearFilters:
        _data.filters.fillRange(0, _data.columns, null);
        _reshaped(r, c);
      case _TableAction.align:
        final align = await _pickAlign(position, _data.aligns[c]);
        if (!mounted) return;
        if (align != null) {
          for (var column = left; column <= right; column++) {
            _data.aligns[column] = align;
          }
          setState(() {});
          _emit(structural: true);
        }
        _restoreFocus(at);
      case _TableAction.color:
        final color = await _pickColor(position);
        if (!mounted) return;
        if (color != null) {
          _data.setColor(top, left, bottom, right, color.isEmpty ? null : color);
          setState(() {});
          _emit(structural: true);
        }
        _restoreFocus(at);
      case _TableAction.wrap:
        final on = !_data.wrap[c];
        for (var column = left; column <= right; column++) {
          _data.wrap[column] = on;
        }
        setState(() {});
        _emit(structural: true);
        _restoreFocus(at);
      case _TableAction.header:
        _data.header = !_data.header;
        _reshaped(r, c);
      case _TableAction.cut || _TableAction.copy:
        if (hasCellRange) {
          await _copyRange(cut: action == _TableAction.cut);
        } else {
          final cell = _cells[r][c].text;
          final sel = cell.selection;
          final whole = !sel.isValid || sel.isCollapsed;
          await Clipboard.setData(ClipboardData(text: whole ? cell.text : sel.textInside(cell.text)));
          if (action == _TableAction.cut) {
            final text = whole ? '' : cell.text.replaceRange(sel.start, sel.end, '');
            cell.value =
                TextEditingValue(text: text, selection: TextSelection.collapsed(offset: whole ? 0 : sel.start));
            _data.setCell(r, c, text);
            setState(() {});
            _emit(structural: true);
          }
        }
        if (mounted) _restoreFocus(at);
      case _TableAction.paste:
        _restoreFocus(at);
        await _paste(at: hasCellRange ? null : at);
      case _TableAction.clear:
        if (!hasCellRange) {
          _anchor = _extent = at;
        }
        _clearCells();
        if (top == bottom && left == right) {
          setState(() => _anchor = _extent = null);
          _focusAfterBuild(r, c);
        } else {
          _holdRangeFocus();
        }
      case _TableAction.deleteRows:
        _removeRows(top, bottom);
      case _TableAction.deleteColumns:
        _removeColumns(left, right);
      case _TableAction.deleteTable:
        widget.onDelete();
    }
  }

  Future<TableAlign?> _pickAlign(Offset at, TableAlign current) {
    final palette = StackColors.of(context);
    PopupMenuItem<TableAlign> item(TableAlign value, IconData icon, String label) => PopupMenuItem(
          value: value,
          height: 32,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: palette.subText),
            const SizedBox(width: 10),
            Text(label),
            if (value == current) ...[
              const SizedBox(width: 24),
              Icon(Icons.check, size: 16, color: palette.accentA, semanticLabel: 'current'),
            ],
          ]),
        );
    return showMenu<TableAlign>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        item(TableAlign.left, Icons.format_align_left, 'Left'),
        item(TableAlign.center, Icons.format_align_center, 'Centre'),
        item(TableAlign.right, Icons.format_align_right, 'Right'),
        item(TableAlign.none, Icons.format_clear, 'Default'),
      ],
    );
  }

  /// A colour name, '' for none, or null when nothing was picked.
  Future<String?> _pickColor(Offset at) {
    final palette = StackColors.of(context);
    PopupMenuItem<String> item(String value, String label) => PopupMenuItem(
          value: value,
          height: 32,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: palette.tableTint(value) ?? palette.canvas,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: palette.controlBorder),
              ),
            ),
            const SizedBox(width: 10),
            Text(label),
          ]),
        );
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        item('', 'No colour'),
        for (final name in tableColors) item(name, '${name[0].toUpperCase()}${name.substring(1)}'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    final focused = widget.focusNode.hasFocus;
    final showTools = (_hover || focused || _refocusing || _menuOpen) && !widget.readOnly;
    final rows = _data.rowCount, columns = _data.columns;
    final (r, c) = _focused ?? _anchor ?? (rows - 1, columns - 1);
    final shown = _data.visibleRows.length;

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
          onExit: (_) => setState(() {
            _hover = false;
            if (_movingRow == null && _movingColumn == null) _hoverCell = null;
          }),
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
                        if (_data.isFiltered) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.filter_alt, size: 14, color: palette.accentA),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Tooltip(
                              message: [
                                for (var i = 0; i < columns; i++)
                                  if (_data.filters[i] != null) _data.filters[i]!.describe(_columnName(i)),
                              ].join('\n'),
                              child: Text(
                                'Showing ${shown - _data.firstBodyRow} of ${rows - _data.firstBodyRow} rows',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: palette.subText, fontSize: StackType.hint),
                              ),
                            ),
                          ),
                          if (!widget.readOnly)
                            HeaderButton(
                              tooltip: 'Clear filters',
                              semanticLabel: 'Clear filters',
                              onPressed: () {
                                _data.filters.fillRange(0, columns, null);
                                _reshaped(r, c);
                              },
                              child: Icon(Icons.filter_alt_off_outlined, size: 16, color: palette.subText),
                            ),
                        ],
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
                            tooltip: rows == 1 ? 'The last row stays' : 'Delete row',
                            semanticLabel: 'Delete row',
                            onPressed: rows == 1 ? null : () => _removeRow(r),
                            child: Icon(Icons.playlist_remove,
                                size: 17, color: rows == 1 ? palette.barBorder : palette.subText),
                          ),
                          HeaderButton(
                            tooltip: columns == 1 ? 'The last column stays' : 'Delete column',
                            semanticLabel: 'Delete column',
                            onPressed: columns == 1 ? null : () => _removeColumn(c),
                            child: Icon(Icons.remove_circle_outline,
                                size: 16, color: columns == 1 ? palette.barBorder : palette.subText),
                          ),
                          HeaderButton(
                            key: _menuButtonKey,
                            tooltip: 'Table options (or right-click a cell)',
                            semanticLabel: 'Table options',
                            onPressed: _openMenuFromButton,
                            child: Icon(Icons.more_horiz, size: 17, color: palette.subText),
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

  /// The cells, with a drag handle on each column's right border and grips
  /// on the hovered row and column; wider than the page, it scrolls sideways.
  Widget _grid(StackPalette palette, double available) {
    final columns = _data.columns;
    final widths = _dragWidths ?? TableBlockView.columnWidths(_data, available);
    final scaler = MediaQuery.textScalerOf(context);
    final inputStyle = BlockMetrics.inputStyleOf(context);
    final shown = _data.visibleRows;
    // The resize drag shows the new widths at once, so the heights follow them.
    final heights = [for (final row in shown) TableBlockView.rowHeight(_data, row, widths, scaler, inputStyle)];
    _layoutWidths = widths;
    _layoutRows = shown;
    _layoutHeights = heights;
    final total = widths.fold(0.0, (a, b) => a + b);
    final tableHeight = heights.fold(0.0, (a, b) => a + b);
    double columnLeft(int column) => widths.take(column).fold(0.0, (a, b) => a + b);
    double rowTop(int visible) => heights.take(visible).fold(0.0, (a, b) => a + b);

    final hover = _hoverCell ?? (-1, -1);
    final hoverVisible = shown.indexOf(hover.$1);
    // A grip stays while its drag runs, or the drag would end with it.
    final moving = _movingRow != null || _movingColumn != null;
    final showGrips = !widget.readOnly && hoverVisible >= 0;

    var edge = 0.0;
    final children = <Widget>[
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
            for (var v = 0; v < shown.length; v++)
              TableRow(
                decoration: _data.header && shown[v] == 0 ? BoxDecoration(color: palette.panel) : null,
                children: [
                  for (var column = 0; column < columns; column++) _cellField(palette, shown[v], column, heights[v]),
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
      if (showGrips && !(_data.header && hover.$1 == 0) && (!moving || _movingRow != null))
        Positioned(
          // Keyed, so the column grip keeps its drag when this one goes.
          key: const ValueKey('row-grip'),
          left: 0,
          top: rowTop(hoverVisible) + (heights[hoverVisible] - _ReorderGrip.long) / 2,
          width: _ReorderGrip.short,
          height: _ReorderGrip.long,
          child: _ReorderGrip(
            key: ValueKey('row-grip-${widget.block.id}-${hover.$1}'),
            vertical: true,
            label: 'Drag to move row ${hover.$1 + 1}',
            onStart: () => _startMove(row: hover.$1),
            onUpdate: _updateMove,
            onEnd: _endMove,
          ),
        ),
      if (showGrips && (!moving || _movingColumn != null))
        Positioned(
          key: const ValueKey('column-grip'),
          left: columnLeft(hover.$2) + (widths[hover.$2] - _ReorderGrip.long) / 2,
          top: 0,
          width: _ReorderGrip.long,
          height: _ReorderGrip.short - 2,
          child: _ReorderGrip(
            key: ValueKey('column-grip-${widget.block.id}-${hover.$2}'),
            vertical: false,
            label: 'Drag to move column ${hover.$2 + 1}',
            onStart: () => _startMove(column: hover.$2),
            onUpdate: _updateMove,
            onEnd: _endMove,
          ),
        ),
    ];

    // While a row or column is dragged: it is shaded, and a line shows where it would land.
    final movingRow = _movingRow, movingColumn = _movingColumn, before = _dropBefore;
    if (movingRow != null) {
      final v = shown.indexOf(movingRow);
      if (v >= 0) {
        children.add(Positioned(
          left: 0,
          width: total,
          top: rowTop(v),
          height: heights[v],
          child: IgnorePointer(child: ColoredBox(color: palette.accentA.withAlpha(36))),
        ));
      }
      if (before != null) {
        final at = shown.indexWhere((row) => row >= before);
        children.add(_dropLine(palette, horizontal: true, offset: at < 0 ? tableHeight : rowTop(at), length: total));
      }
    }
    if (movingColumn != null) {
      children.add(Positioned(
        left: columnLeft(movingColumn),
        width: widths[movingColumn],
        top: 0,
        height: tableHeight,
        child: IgnorePointer(child: ColoredBox(color: palette.accentA.withAlpha(36))),
      ));
      if (before != null) {
        children.add(_dropLine(palette, horizontal: false, offset: columnLeft(before), length: tableHeight));
      }
    }

    Widget grid = MouseRegion(
      onHover: _onHover,
      child: Stack(key: _gridKey, children: children),
    );
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

  Widget _dropLine(StackPalette palette, {required bool horizontal, required double offset, required double length}) =>
      Positioned(
        left: horizontal ? 0 : offset - 1.5,
        top: horizontal ? offset - 1.5 : 0,
        width: horizontal ? length : 3,
        height: horizontal ? 3 : length,
        child: IgnorePointer(child: ColoredBox(color: palette.accentA)),
      );

  Widget _cellField(StackPalette palette, int row, int column, double height) {
    final cell = _cells[row][column];
    final align = switch (_data.aligns[column]) {
      TableAlign.center => TextAlign.center,
      TableAlign.right => TextAlign.right,
      _ => TextAlign.left,
    };
    final isHeader = _data.header && row == 0;
    final tint = palette.tableTint(_data.colors[row][column]);
    final selected = _inRange(row, column) ? palette.accentA.withAlpha(46) : null;
    final multiline = TableBlockView.multiline(_data, row, column);
    return Container(
      height: height,
      color: selected != null && tint != null ? Color.alphaBlend(selected, tint) : selected ?? tint,
      child: Center(
        child: TextField(
          key: ValueKey('cell-${widget.block.id}-$row-$column'),
          controller: cell.text,
          focusNode: cell.focus,
          readOnly: widget.readOnly,
          maxLines: multiline ? null : 1,
          keyboardType: multiline ? TextInputType.multiline : TextInputType.text,
          textAlign: align,
          // The table's own menu takes the right-click.
          contextMenuBuilder: null,
          style: TableBlockView.cellStyle.copyWith(
            color: palette.text,
            fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
          ),
          strutStyle: TableBlockView._strut,
          cursorColor: palette.accentA,
          decoration: InputDecoration(
            isCollapsed: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: TableBlockView._cellPadding),
            hintText: isHeader ? 'Header' : null,
            hintStyle: TextStyle(color: palette.subText.withAlpha(120)),
          ),
          onChanged: (value) {
            final wasMultiline = TableBlockView.multiline(_data, row, column);
            _data.setCell(row, column, value);
            if (multiline || wasMultiline != TableBlockView.multiline(_data, row, column)) {
              setState(() {}); // the row may grow or shrink
            }
            _emit();
          },
        ),
      ),
    );
  }
}

/// The result of the filter dialog: the filter to set, or null to remove it.
class TableFilterChoice {
  const TableFilterChoice(this.filter);
  final TableFilter? filter;
}

/// Asks how to filter the rows by [column]. Null when cancelled.
Future<TableFilterChoice?> showTableFilterDialog(BuildContext context, String column, TableFilter? current) {
  final text = TextEditingController(text: current?.value ?? '');
  var op = current?.op ?? TableFilterOp.contains;
  return showDialog<TableFilterChoice>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      final needsText = op == TableFilterOp.contains || op == TableFilterOp.notContains;
      void apply() => Navigator.of(context).pop(TableFilterChoice(TableFilter(op, needsText ? text.text : '')));
      return AlertDialog(
        title: Text('Filter by $column'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<TableFilterOp>(
                value: op,
                isExpanded: true,
                onChanged: (value) => setState(() => op = value ?? op),
                items: const [
                  DropdownMenuItem(value: TableFilterOp.contains, child: Text('Contains')),
                  DropdownMenuItem(value: TableFilterOp.notContains, child: Text('Does not contain')),
                  DropdownMenuItem(value: TableFilterOp.isEmpty, child: Text('Is empty')),
                  DropdownMenuItem(value: TableFilterOp.isNotEmpty, child: Text('Is not empty')),
                ],
              ),
              if (needsText) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('table-filter-text'),
                  controller: text,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Text', hintText: 'Not case-sensitive'),
                  onSubmitted: (_) => apply(),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          if (current != null)
            TextButton(
                onPressed: () => Navigator.of(context).pop(const TableFilterChoice(null)),
                child: const Text('Remove filter')),
          FilledButton(onPressed: apply, child: const Text('Filter')),
        ],
      );
    }),
  );
}

/// The grip that shows on the hovered row's left edge or column's top edge;
/// dragging it moves the row or column.
class _ReorderGrip extends StatefulWidget {
  const _ReorderGrip(
      {super.key,
      required this.vertical,
      required this.label,
      required this.onStart,
      required this.onUpdate,
      required this.onEnd});

  /// Narrow enough to sit in the cell's padding, clear of its text.
  static const short = 10.0;
  static const long = 26.0;

  final bool vertical;
  final String label;
  final VoidCallback onStart;
  final ValueChanged<Offset> onUpdate;
  final void Function({bool cancelled}) onEnd;

  @override
  State<_ReorderGrip> createState() => _ReorderGripState();
}

class _ReorderGripState extends State<_ReorderGrip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    return Tooltip(
      message: widget.label,
      waitDuration: const Duration(milliseconds: 600),
      child: Semantics(
        label: widget.label,
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              widget.onStart();
              widget.onUpdate(details.globalPosition);
            },
            onPanUpdate: (details) => widget.onUpdate(details.globalPosition),
            onPanEnd: (_) => widget.onEnd(),
            onPanCancel: () => widget.onEnd(cancelled: true),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _hover ? palette.pressed : palette.control,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: palette.controlBorder),
              ),
              child: Center(
                child: RotatedBox(
                  quarterTurns: widget.vertical ? 0 : 1,
                  child: Icon(Icons.drag_indicator, size: 8, color: palette.subText),
                ),
              ),
            ),
          ),
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
