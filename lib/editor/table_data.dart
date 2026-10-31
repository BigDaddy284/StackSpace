import 'dart:convert';
import 'dart:math' as math;

/// A Markdown (GitHub style) table as cells: the header row, the column
/// alignments and the body rows.
///
/// `| a | b |` lines are read and written here; the block keeps the lines
/// as its text, so a page that is never edited writes back exactly as read.
/// A line break inside a cell is written as `<br>`, as GitHub does. Column
/// widths set by dragging are kept on one HTML comment line right under the
/// rows (`<!-- table-widths: 120,200 -->`), and the rest of the table's look
/// (no header row, columns that don't wrap, cell colours, filters) on one
/// more (`<!-- table-style: {...} -->`); other Markdown readers hide both.
enum TableAlign { none, left, center, right }

/// How a column's filter tests a cell.
enum TableFilterOp { contains, notContains, isEmpty, isNotEmpty }

/// A filter on one column: rows whose cell fails it are hidden.
class TableFilter {
  const TableFilter(this.op, [this.value = '']);
  final TableFilterOp op;
  final String value;

  bool test(String cell) {
    final text = cell.trim().toLowerCase();
    return switch (op) {
      TableFilterOp.contains => text.contains(value.trim().toLowerCase()),
      TableFilterOp.notContains => !text.contains(value.trim().toLowerCase()),
      TableFilterOp.isEmpty => text.isEmpty,
      TableFilterOp.isNotEmpty => text.isNotEmpty,
    };
  }

  String describe(String column) => switch (op) {
        TableFilterOp.contains => '$column contains "$value"',
        TableFilterOp.notContains => '$column does not contain "$value"',
        TableFilterOp.isEmpty => '$column is empty',
        TableFilterOp.isNotEmpty => '$column is not empty',
      };

  @override
  bool operator ==(Object other) => other is TableFilter && other.op == op && other.value == value;

  @override
  int get hashCode => Object.hash(op, value);
}

/// The background colours a cell can have, by name; the theme picks the
/// shade (see `StackPalette.tableTint`).
const tableColors = ['gray', 'brown', 'orange', 'yellow', 'green', 'blue', 'purple', 'pink', 'red'];

class TableData {
  TableData(this.rows, this.aligns, [this.widths])
      : assert(rows.isNotEmpty),
        colors = [for (final r in rows) List<String?>.filled(r.length, null, growable: true)],
        wrap = List<bool>.filled(aligns.length, true, growable: true),
        filters = List<TableFilter?>.filled(aligns.length, null, growable: true);

  /// Row 0 is the header (when [header] is on); every row has [columns] cells.
  final List<List<String>> rows;
  final List<TableAlign> aligns;

  /// Each cell's background colour (a name from [tableColors]) or null, in
  /// the same shape as [rows].
  final List<List<String?>> colors;

  /// Per column: long text wraps onto more lines (the default) rather than
  /// staying on one line that scrolls inside the cell.
  final List<bool> wrap;

  /// Per column: the filter that hides rows, or null.
  final List<TableFilter?> filters;

  /// Whether row 0 is a header row (bold, shaded, kept out of sorting and
  /// filtering). Markdown always has one; turning it off is kept on the
  /// style line.
  bool header = true;

  /// Each column's width in logical pixels, or null for even columns that
  /// fill the page width.
  List<double>? widths;

  /// The width a column added to a table with set widths starts at.
  static const defaultWidth = 160.0;

  /// The narrowest a column can be dragged.
  static const minWidth = 48.0;

  /// The line that keeps the column widths, under the table's rows.
  static final widthsLine = RegExp(r'^<!--\s*table-widths:\s*([\d.,\s]*?)\s*-->\s*$');

  /// The line that keeps the rest of the table's look, as JSON.
  static final styleLine = RegExp(r'^<!--\s*table-style:\s*(.*?)\s*-->\s*$');

  /// True for either comment line that belongs to the table above it.
  static bool isMetaLine(String line) => widthsLine.hasMatch(line.trim()) || styleLine.hasMatch(line.trim());

  static final _lineBreak = RegExp(r'<br\s*/?>', caseSensitive: false);

  int get columns => aligns.length;
  int get rowCount => rows.length;

  static final _separatorCell = RegExp(r'^:?-+:?$');

  /// The cell of [to] where it first differs from [from], and the caret
  /// offset in that cell at the end of the changed text: where Ctrl+Z or
  /// Ctrl+Y puts the caret. Cells are compared, not the Markdown, because a
  /// longer cell re-pads its whole column. A row or column added or removed
  /// at the end gives the nearest cell that is left; null when only the
  /// widths or style changed.
  static (int, int, int)? firstChange(String from, String to) {
    final a = parse(from), b = parse(to);
    if (b == null) return null;
    if (a == null) return (0, 0, 0);
    for (var r = 0; r < b.rowCount; r++) {
      for (var c = 0; c < b.columns; c++) {
        final before = r < a.rowCount && c < a.columns ? a.rows[r][c] : null;
        final after = b.rows[r][c];
        if (before == after) continue;
        if (before == null) return (r, c, after.length);
        var start = 0;
        while (start < before.length && start < after.length && before[start] == after[start]) {
          start++;
        }
        var end = 0;
        while (end < before.length - start &&
            end < after.length - start &&
            before[before.length - 1 - end] == after[after.length - 1 - end]) {
          end++;
        }
        return (r, c, after.length - end);
      }
    }
    if (a.rowCount != b.rowCount) return (b.rowCount - 1, 0, 0);
    if (a.columns != b.columns) return (0, b.columns - 1, 0);
    return null;
  }

  /// Reads the lines of a table block. Lines that are not `| ... |` rows are
  /// skipped; a missing separator row makes every row a body row after the
  /// first. Null when there is no row at all.
  static TableData? parse(String markdown) {
    final lines = markdown.split('\n').where((l) => l.trim().isNotEmpty).toList();
    List<double>? widths;
    Map<String, dynamic>? style;
    lines.removeWhere((line) {
      final styleMatch = styleLine.firstMatch(line.trim());
      if (styleMatch != null) {
        try {
          final decoded = jsonDecode(styleMatch.group(1)!);
          if (decoded is Map<String, dynamic>) style = decoded;
        } on FormatException {
          // A damaged style line is dropped; the table reads as plain.
        }
        return true;
      }
      final match = widthsLine.firstMatch(line.trim());
      if (match == null) return false;
      widths = match
          .group(1)!
          .split(',')
          .map((w) => double.tryParse(w.trim()))
          .whereType<double>()
          .map((w) => w < minWidth ? minWidth : w)
          .toList();
      return true;
    });
    if (lines.isEmpty) return null;
    final rows = <List<String>>[];
    List<TableAlign>? aligns;
    for (var i = 0; i < lines.length; i++) {
      final cells = splitRow(lines[i]);
      if (i == 1 && aligns == null && cells.every((c) => _separatorCell.hasMatch(c.trim()))) {
        aligns = cells.map((c) => _alignOf(c.trim())).toList();
        continue;
      }
      rows.add(cells);
    }
    if (rows.isEmpty) return null;
    final columns = [rows.map((r) => r.length).reduce((a, b) => a > b ? a : b), aligns?.length ?? 0]
        .reduce((a, b) => a > b ? a : b);
    for (final row in rows) {
      while (row.length < columns) {
        row.add('');
      }
    }
    final filled =
        List<TableAlign>.generate(columns, (i) => aligns != null && i < aligns.length ? aligns[i] : TableAlign.none);
    final read = widths;
    if (read != null && read.isNotEmpty) {
      while (read.length < columns) {
        read.add(defaultWidth);
      }
      read.length = columns;
    }
    final data = TableData(rows, filled, read == null || read.isEmpty ? null : read);
    if (style != null) data._readStyle(style!);
    return data;
  }

  void _readStyle(Map<String, dynamic> style) {
    if (style['header'] == false) header = false;
    final noWrap = style['nowrap'];
    if (noWrap is List) {
      for (final c in noWrap) {
        if (c is int && c >= 0 && c < columns) wrap[c] = false;
      }
    }
    final colours = style['colors'];
    if (colours is Map) {
      colours.forEach((key, value) {
        final at = '$key'.split(',').map(int.tryParse).toList();
        if (at.length != 2 || at[0] == null || at[1] == null || value is! String || !tableColors.contains(value)) {
          return;
        }
        final (r, c) = (at[0]!, at[1]!);
        if (r >= 0 && r < rowCount && c >= 0 && c < columns) colors[r][c] = value;
      });
    }
    final filtersRead = style['filters'];
    if (filtersRead is Map) {
      filtersRead.forEach((key, value) {
        final c = int.tryParse('$key');
        if (c == null || c < 0 || c >= columns || value is! Map) return;
        final op = TableFilterOp.values.where((o) => o.name == value['op']).firstOrNull;
        if (op == null) return;
        filters[c] = TableFilter(op, value['value'] is String ? value['value'] as String : '');
      });
    }
  }

  /// The style line's JSON, or null when everything is the default.
  String? _styleJson() {
    final style = <String, Object>{};
    if (!header) style['header'] = false;
    final noWrap = [
      for (var c = 0; c < columns; c++)
        if (!wrap[c]) c
    ];
    if (noWrap.isNotEmpty) style['nowrap'] = noWrap;
    final colours = <String, String>{
      for (var r = 0; r < rowCount; r++)
        for (var c = 0; c < columns; c++)
          if (colors[r][c] != null) '$r,$c': colors[r][c]!,
    };
    if (colours.isNotEmpty) style['colors'] = colours;
    final set = <String, Object>{
      for (var c = 0; c < columns; c++)
        if (filters[c] != null)
          '$c': {'op': filters[c]!.op.name, if (filters[c]!.value.isNotEmpty) 'value': filters[c]!.value},
    };
    if (set.isNotEmpty) style['filters'] = set;
    if (style.isEmpty) return null;
    // A '>' in a filter's text must not end the comment early.
    return jsonEncode(style).replaceAll('>', r'\u003e');
  }

  /// The first row that sorting and filtering act on: 1 under a header row.
  int get firstBodyRow => header ? 1 : 0;

  bool get isFiltered => filters.any((f) => f != null);

  /// Whether row [r] passes every filter (a header row always shows).
  bool rowVisible(int r) {
    if (header && r == 0) return true;
    for (var c = 0; c < columns; c++) {
      final f = filters[c];
      if (f != null && !f.test(rows[r][c])) return false;
    }
    return true;
  }

  /// The rows that show, in order.
  List<int> get visibleRows => [
        for (var r = 0; r < rowCount; r++)
          if (rowVisible(r)) r
      ];

  static TableAlign _alignOf(String cell) {
    final left = cell.startsWith(':'), right = cell.endsWith(':');
    if (left && right) return TableAlign.center;
    if (left) return TableAlign.left;
    if (right) return TableAlign.right;
    return TableAlign.none;
  }

  /// The cells of one `| a | b |` line, trimmed, with `\|` read as `|`.
  static List<String> splitRow(String line) {
    var s = line.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|') && !s.endsWith(r'\|')) s = s.substring(0, s.length - 1);
    final cells = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == r'\' && i + 1 < s.length && s[i + 1] == '|') {
        buffer.write('|');
        i++;
      } else if (ch == '|') {
        cells.add(buffer.toString().trim().replaceAll(_lineBreak, '\n'));
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    cells.add(buffer.toString().trim().replaceAll(_lineBreak, '\n'));
    return cells;
  }

  /// The table as Markdown lines with the columns padded to equal width.
  String toMarkdown() {
    final escaped =
        rows.map((r) => r.map((c) => c.replaceAll('|', r'\|').replaceAll(RegExp(r'\r?\n'), '<br>')).toList()).toList();
    final widths = List<int>.generate(columns, (c) {
      var w = 3;
      for (final row in escaped) {
        if (row[c].length > w) w = row[c].length;
      }
      return w;
    });
    String line(List<String> cells) =>
        '| ${[for (var c = 0; c < columns; c++) cells[c].padRight(widths[c])].join(' | ')} |';
    final separator = '| ${[
      for (var c = 0; c < columns; c++)
        switch (aligns[c]) {
          TableAlign.left => ':${'-' * (widths[c] - 1)}',
          TableAlign.right => '${'-' * (widths[c] - 1)}:',
          TableAlign.center => ':${'-' * (widths[c] - 2)}:',
          TableAlign.none => '-' * widths[c],
        }
    ].join(' | ')} |';
    final set = this.widths;
    final style = _styleJson();
    return [
      line(escaped[0]),
      separator,
      for (var r = 1; r < escaped.length; r++) line(escaped[r]),
      if (set != null) '<!-- table-widths: ${set.map((w) => w.round()).join(',')} -->',
      if (style != null) '<!-- table-style: $style -->',
    ].join('\n');
  }

  TableData copy() {
    final data =
        TableData([for (final r in rows) List.of(r)], List.of(aligns), widths == null ? null : List.of(widths!));
    for (var r = 0; r < rowCount; r++) {
      data.colors[r].setAll(0, colors[r]);
    }
    data.wrap.setAll(0, wrap);
    data.filters.setAll(0, filters);
    data.header = header;
    return data;
  }

  void setCell(int row, int column, String value) => rows[row][column] = value;

  /// Adds an empty row at [at]; at 0 under a header row, the new row is the
  /// header.
  void insertRow(int at) {
    final r = at.clamp(0, rows.length);
    rows.insert(r, List<String>.filled(columns, '', growable: true));
    colors.insert(r, List<String?>.filled(columns, null, growable: true));
  }

  /// Adds a copy of row [at] under it.
  void duplicateRow(int at) {
    rows.insert(at + 1, List.of(rows[at]));
    colors.insert(at + 1, List.of(colors[at]));
  }

  /// Removes a row; the last one stays. Removing the header row makes the
  /// next row the header. False when it is the only row.
  bool removeRow(int at) {
    if (rows.length <= 1 || at < 0 || at >= rows.length) return false;
    rows.removeAt(at);
    colors.removeAt(at);
    return true;
  }

  /// Moves row [from] so it lands before the row now at [before] (which may
  /// be [rowCount], for the end).
  void moveRow(int from, int before) {
    if (from < 0 || from >= rowCount) return;
    var to = before.clamp(0, rowCount);
    if (to == from || to == from + 1) return;
    final row = rows.removeAt(from), colour = colors.removeAt(from);
    if (to > from) to--;
    rows.insert(to, row);
    colors.insert(to, colour);
  }

  void insertColumn(int at, {String header = ''}) {
    final c = at.clamp(0, columns);
    for (var r = 0; r < rows.length; r++) {
      rows[r].insert(c, r == 0 && this.header ? header : '');
      colors[r].insert(c, null);
    }
    aligns.insert(c, TableAlign.none);
    widths?.insert(c, defaultWidth);
    wrap.insert(c, true);
    filters.insert(c, null);
  }

  /// Adds a copy of column [at] (cells, colours, alignment, width and
  /// wrapping, not the filter) to its right.
  void duplicateColumn(int at) {
    for (var r = 0; r < rows.length; r++) {
      rows[r].insert(at + 1, rows[r][at]);
      colors[r].insert(at + 1, colors[r][at]);
    }
    aligns.insert(at + 1, aligns[at]);
    widths?.insert(at + 1, widths![at]);
    wrap.insert(at + 1, wrap[at]);
    filters.insert(at + 1, null);
  }

  /// Removes a column; the last one stays. False when it is the only column.
  bool removeColumn(int at) {
    if (columns <= 1 || at < 0 || at >= columns) return false;
    for (var r = 0; r < rows.length; r++) {
      rows[r].removeAt(at);
      colors[r].removeAt(at);
    }
    aligns.removeAt(at);
    widths?.removeAt(at);
    wrap.removeAt(at);
    filters.removeAt(at);
    return true;
  }

  /// Moves column [from] so it lands before the column now at [before]
  /// (which may be [columns], for the end), with everything it carries.
  void moveColumn(int from, int before) {
    if (from < 0 || from >= columns) return;
    var to = before.clamp(0, columns);
    if (to == from || to == from + 1) return;
    if (to > from) to--;
    void move<T>(List<T> list) => list.insert(to, list.removeAt(from));
    for (var r = 0; r < rows.length; r++) {
      move(rows[r]);
      move(colors[r]);
    }
    move(aligns);
    if (widths != null) move(widths!);
    move(wrap);
    move(filters);
  }

  /// Sorts the rows under the header by [column]: numbers by value (a
  /// leading currency sign, thousands commas and a trailing % are allowed),
  /// other text alphabetically ignoring case, and empty cells always last.
  void sortBy(int column, {bool descending = false}) {
    final first = firstBodyRow;
    if (rowCount - first < 2) return;
    final order = [for (var r = first; r < rowCount; r++) r];
    int compare(int a, int b) {
      final x = rows[a][column].trim(), y = rows[b][column].trim();
      if (x.isEmpty || y.isEmpty) {
        if (x.isEmpty && y.isEmpty) return a - b;
        return x.isEmpty ? 1 : -1;
      }
      final nx = _number(x), ny = _number(y);
      int result;
      if (nx != null && ny != null) {
        result = nx.compareTo(ny);
      } else if (nx != null || ny != null) {
        result = nx != null ? -1 : 1; // numbers before words
      } else {
        result = x.toLowerCase().compareTo(y.toLowerCase());
      }
      if (descending) result = -result;
      return result != 0 ? result : a - b; // stable
    }

    order.sort(compare);
    final sortedRows = [for (final r in order) rows[r]];
    final sortedColors = [for (final r in order) colors[r]];
    rows.replaceRange(first, rowCount, sortedRows);
    colors.replaceRange(first, colors.length, sortedColors);
  }

  static final _numberText = RegExp(r'^[-+]?[$€£¥]?\s*[-+]?[\d,]*\.?\d+(e[-+]?\d+)?\s*%?$', caseSensitive: false);

  static double? number(String text) => _number(text.trim());

  static double? _number(String text) {
    if (!_numberText.hasMatch(text)) return null;
    final negative = text.startsWith('-') || text.contains(RegExp(r'^[$€£¥]\s*-'));
    final digits = text.replaceAll(RegExp(r'[^\d.eE+-]'), '').replaceAll(RegExp(r'^[-+]'), '');
    final value = double.tryParse(digits);
    if (value == null) return null;
    return negative ? -value : value;
  }

  /// Sets the background colour of the cells from ([top], [left]) to
  /// ([bottom], [right]); null clears it.
  void setColor(int top, int left, int bottom, int right, String? color) {
    for (var r = top; r <= bottom; r++) {
      for (var c = left; c <= right; c++) {
        colors[r][c] = color;
      }
    }
  }

  /// The cells from ([top], [left]) to ([bottom], [right]) as tab-separated
  /// lines, the way spreadsheets copy them. A cell with a tab, a line break
  /// or a quote is quoted.
  String toTsv(int top, int left, int bottom, int right) {
    String field(String cell) => cell.contains(RegExp('[\t\n\r"]')) ? '"${cell.replaceAll('"', '""')}"' : cell;
    return [
      for (var r = top; r <= bottom; r++) [for (var c = left; c <= right; c++) field(rows[r][c])].join('\t'),
    ].join('\n');
  }

  /// Reads tab-separated text (from a spreadsheet, or [toTsv]) as rows of
  /// cells. Quoted cells may hold tabs, line breaks and `""` for a quote.
  static List<List<String>> parseTsv(String text) {
    var s = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (s.endsWith('\n')) s = s.substring(0, s.length - 1);
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var i = 0;
    var atCellStart = true;
    while (i < s.length) {
      final ch = s[i];
      if (atCellStart && ch == '"') {
        // A quoted cell runs to the quote before a tab, a line break or the end.
        i++;
        while (i < s.length) {
          if (s[i] == '"') {
            if (i + 1 < s.length && s[i + 1] == '"') {
              cell.write('"');
              i += 2;
              continue;
            }
            i++;
            break;
          }
          cell.write(s[i]);
          i++;
        }
        atCellStart = false;
        continue;
      }
      atCellStart = false;
      if (ch == '\t') {
        row.add(cell.toString());
        cell.clear();
        atCellStart = true;
      } else if (ch == '\n') {
        row.add(cell.toString());
        cell.clear();
        rows.add(row);
        row = <String>[];
        atCellStart = true;
      } else {
        cell.write(ch);
      }
      i++;
    }
    row.add(cell.toString());
    rows.add(row);
    return rows;
  }

  /// Moves (or with [copy], copies) the cells from ([top], [left]) to
  /// ([bottom], [right]) with their colours so the block's top left lands on
  /// ([toRow], [toColumn]), which is clamped so the block stays inside the
  /// table. The cells it leaves (and that the block does not cover again)
  /// are emptied. Returns where the block went as (top, left, bottom, right).
  (int, int, int, int) moveBlock(int top, int left, int bottom, int right, int toRow, int toColumn,
      {bool copy = false}) {
    final height = bottom - top + 1, width = right - left + 1;
    final r0 = toRow.clamp(0, rowCount - height), c0 = toColumn.clamp(0, columns - width);
    final text = [
      for (var r = top; r <= bottom; r++) rows[r].sublist(left, right + 1),
    ];
    final colour = [
      for (var r = top; r <= bottom; r++) colors[r].sublist(left, right + 1),
    ];
    if (!copy) {
      for (var r = top; r <= bottom; r++) {
        for (var c = left; c <= right; c++) {
          rows[r][c] = '';
          colors[r][c] = null;
        }
      }
    }
    for (var r = 0; r < height; r++) {
      for (var c = 0; c < width; c++) {
        rows[r0 + r][c0 + c] = text[r][c];
        colors[r0 + r][c0 + c] = colour[r][c];
      }
    }
    return (r0, c0, r0 + height - 1, c0 + width - 1);
  }

  /// Fills from the cells ([top], [left]) to ([bottom], [right]) out to row
  /// [toRow] (down or up) or column [toColumn] (right or left), the way a
  /// spreadsheet's fill handle does: each row or column of the block is
  /// carried on as a series (see [series]), and colours repeat. Only one of
  /// [toRow] and [toColumn] is used. Returns the cells filled.
  (int, int, int, int) fill(int top, int left, int bottom, int right, {int? toRow, int? toColumn}) {
    if (toRow != null && (toRow > bottom || toRow < top)) {
      final down = toRow > bottom;
      final count = down ? toRow - bottom : top - toRow;
      for (var c = left; c <= right; c++) {
        var source = [for (var r = top; r <= bottom; r++) rows[r][c]];
        final colour = [for (var r = top; r <= bottom; r++) colors[r][c]];
        if (!down) source = source.reversed.toList();
        final values = series(source, count);
        for (var i = 0; i < count; i++) {
          final r = down ? bottom + 1 + i : top - 1 - i;
          rows[r][c] = values[i];
          colors[r][c] = (down ? colour : colour.reversed.toList())[i % colour.length];
        }
      }
      return down ? (top, left, toRow, right) : (toRow, left, bottom, right);
    }
    if (toColumn != null && (toColumn > right || toColumn < left)) {
      final rightwards = toColumn > right;
      final count = rightwards ? toColumn - right : left - toColumn;
      for (var r = top; r <= bottom; r++) {
        var source = rows[r].sublist(left, right + 1);
        var colour = colors[r].sublist(left, right + 1);
        if (!rightwards) {
          source = source.reversed.toList();
          colour = colour.reversed.toList();
        }
        final values = series(source, count);
        for (var i = 0; i < count; i++) {
          final c = rightwards ? right + 1 + i : left - 1 - i;
          rows[r][c] = values[i];
          colors[r][c] = colour[i % colour.length];
        }
      }
      return rightwards ? (top, left, bottom, toColumn) : (top, toColumn, bottom, right);
    }
    return (top, left, bottom, right);
  }

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final _plainNumber = RegExp(r'^([-+]?[$€£¥]?)(-?\d[\d,]*(?:\.(\d+))?)(%?)$');
  static final _trailingNumber = RegExp(r'^(.*?)(\d+)$');

  /// The next [count] values after [source], the way a fill handle
  /// continues them: numbers go on by the step between the last two (one
  /// number repeats), dates by days, day and month names in order, text
  /// that ends in a number counts up ("Item 3", "Item 4"), and anything else
  /// repeats the cells in turn.
  static List<String> series(List<String> source, int count) {
    if (count <= 0 || source.isEmpty) return const [];
    final cells = [for (final s in source) s.trim()];
    String repeat(int i) => source[i % source.length];

    // Numbers, with a currency sign or % kept.
    final numbers = [for (final c in cells) _plainNumber.firstMatch(c)];
    if (cells.length > 1 && numbers.every((m) => m != null)) {
      final values = [for (final m in numbers) double.parse(m!.group(2)!.replaceAll(',', ''))];
      final step = values.last - values[values.length - 2];
      final decimals = numbers.map((m) => m!.group(3)?.length ?? 0).fold(0, (a, b) => a > b ? a : b);
      final prefix = numbers.last!.group(1)!, suffix = numbers.last!.group(4)!;
      final grouped = numbers.any((m) => m!.group(2)!.contains(','));
      return [
        for (var i = 1; i <= count; i++) '$prefix${_formatNumber(values.last + step * i, decimals, grouped)}$suffix',
      ];
    }

    // Dates.
    final dates = [for (final c in cells) _isoDate.hasMatch(c) ? DateTime.tryParse(c) : null];
    if (dates.every((d) => d != null)) {
      final step = dates.length > 1 ? dates.last!.difference(dates[dates.length - 2]!).inDays : 1;
      String format(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final last = dates.last!;
      return [for (var i = 1; i <= count; i++) format(DateTime(last.year, last.month, last.day + step * i))];
    }

    // Day and month names, full or short, keeping the case written.
    for (final names in [_days, _months]) {
      int? indexOf(String c) {
        final lower = c.toLowerCase();
        for (var i = 0; i < names.length; i++) {
          final name = names[i].toLowerCase();
          if (lower == name || (lower.length == 3 && name.startsWith(lower))) return i;
        }
        return null;
      }

      final found = [for (final c in cells) indexOf(c)];
      if (found.every((i) => i != null)) {
        final step = found.length > 1 ? (found.last! - found[found.length - 2]!) % names.length : 1;
        final sample = cells.last;
        final short = sample.length == 3;
        String styled(String name) {
          final word = short ? name.substring(0, 3) : name;
          if (sample == sample.toUpperCase()) return word.toUpperCase();
          if (sample == sample.toLowerCase()) return word.toLowerCase();
          return word;
        }

        return [for (var i = 1; i <= count; i++) styled(names[(found.last! + step * i) % names.length])];
      }
    }

    // Text ending in a number: "Item 3" → "Item 4"; the step comes from the
    // last two when they share the text.
    final last = _trailingNumber.firstMatch(cells.last);
    if (last != null && last.group(1)!.isNotEmpty) {
      final head = last.group(1)!, digits = last.group(2)!;
      var step = 1;
      if (cells.length > 1) {
        final before = _trailingNumber.firstMatch(cells[cells.length - 2]);
        if (before != null && before.group(1) == head) step = int.parse(digits) - int.parse(before.group(2)!);
      }
      return [
        for (var i = 1; i <= count; i++)
          '$head${math.max(0, int.parse(digits) + step * i).toString().padLeft(digits.length, '0')}',
      ];
    }
    return [for (var i = 0; i < count; i++) repeat(i)];
  }

  static String _formatNumber(double value, int decimals, bool grouped) {
    var text = value.toStringAsFixed(decimals);
    if (text == '-0' || RegExp(r'^-0\.0+$').hasMatch(text)) text = text.substring(1);
    if (!grouped) return text;
    final negative = text.startsWith('-');
    if (negative) text = text.substring(1);
    final dot = text.indexOf('.');
    final whole = dot < 0 ? text : text.substring(0, dot), rest = dot < 0 ? '' : text.substring(dot);
    final out = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) out.write(',');
      out.write(whole[i]);
    }
    return '${negative ? '-' : ''}$out$rest';
  }

  /// Count, sum and average of the cells from ([top], [left]) to
  /// ([bottom], [right]), as a spreadsheet's status bar shows them: count is
  /// of cells with something in them, sum and average of those that are
  /// numbers (null when none are).
  ({int count, int numbers, double? sum, double? average}) stats(int top, int left, int bottom, int right) {
    var count = 0, numbers = 0;
    var sum = 0.0;
    for (var r = top; r <= bottom; r++) {
      for (var c = left; c <= right; c++) {
        final text = rows[r][c].trim();
        if (text.isEmpty) continue;
        count++;
        final value = _number(text);
        if (value != null) {
          numbers++;
          sum += value;
        }
      }
    }
    return (
      count: count,
      numbers: numbers,
      sum: numbers == 0 ? null : sum,
      average: numbers == 0 ? null : sum / numbers,
    );
  }

  /// Empties the cells from ([top], [left]) to ([bottom], [right]).
  void clear(int top, int left, int bottom, int right) {
    for (var r = top; r <= bottom; r++) {
      for (var c = left; c <= right; c++) {
        rows[r][c] = '';
      }
    }
  }

  /// Pastes [grid] into the cells from ([top], [left]) to ([bottom],
  /// [right]), the way a spreadsheet does: one value fills every selected
  /// cell, a grid that fits the selection a whole number of times repeats,
  /// and anything else is pasted once from the top left corner. Rows and
  /// columns are added when the grid runs past the table's edge. Returns the
  /// cells written as (top, left, bottom, right).
  (int, int, int, int) paste(int top, int left, int bottom, int right, List<List<String>> grid) {
    final height = grid.length;
    final width = grid.map((r) => r.length).fold(0, (a, b) => a > b ? a : b);
    if (height == 0 || width == 0) return (top, left, bottom, right);
    final selRows = bottom - top + 1, selColumns = right - left + 1;
    final repeats = selRows % height == 0 && selColumns % width == 0;
    final lastRow = repeats ? bottom : top + height - 1;
    final lastColumn = repeats ? right : left + width - 1;
    while (rowCount <= lastRow) {
      insertRow(rowCount);
    }
    while (columns <= lastColumn) {
      insertColumn(columns, header: 'Column ${columns + 1}');
    }
    for (var r = top; r <= lastRow; r++) {
      final source = grid[(r - top) % height];
      for (var c = left; c <= lastColumn; c++) {
        final i = (c - left) % width;
        rows[r][c] = i < source.length ? source[i].replaceAll('\t', ' ') : '';
      }
    }
    return (top, left, lastRow, lastColumn);
  }
}
