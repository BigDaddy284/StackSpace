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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (widget.readOnly) return KeyEventResult.ignored;
    final at = _focused;
    if (at == null) return KeyEventResult.ignored;
    final (r, c) = at;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) return KeyEventResult.ignored;
    final shift = keys.isShiftPressed;
    final key = event.logicalKey;
    final last = _data.rowCount - 1, lastColumn = _data.columns - 1;

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
    if (has && widget.focusNode.hasPrimaryFocus) focusFirst();
    if (mounted) setState(() {});
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
                  Table(
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cellField(StackPalette palette, int row, int column) {
    final cell = _cells[row][column];
    final align = switch (_data.aligns[column]) {
      TableAlign.center => TextAlign.center,
      TableAlign.right => TextAlign.right,
      _ => TextAlign.left,
    };
    return SizedBox(
      height: TableBlockView.cellHeight,
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

class _Cell {
  _Cell(String value, this.focus) : text = TextEditingController(text: value);
  final TextEditingController text;
  final FocusNode focus;

  void dispose() {
    text.dispose();
    focus.dispose();
  }
}
