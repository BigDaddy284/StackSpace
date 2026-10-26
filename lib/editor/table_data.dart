/// A Markdown (GitHub style) table as cells: the header row, the column
/// alignments and the body rows.
///
/// `| a | b |` lines are read and written here; the block keeps the lines
/// as its text, so a page that is never edited writes back exactly as read.
/// Column widths set by dragging are kept on one HTML comment line right
/// under the rows (`<!-- table-widths: 120,200 -->`), which other Markdown
/// readers hide.
enum TableAlign { none, left, center, right }

class TableData {
  TableData(this.rows, this.aligns, [this.widths]) : assert(rows.isNotEmpty);

  /// Row 0 is the header; every row has [columns] cells.
  final List<List<String>> rows;
  final List<TableAlign> aligns;

  /// Each column's width in logical pixels, or null for even columns that
  /// fill the page width.
  List<double>? widths;

  /// The width a column added to a table with set widths starts at.
  static const defaultWidth = 160.0;

  /// The narrowest a column can be dragged.
  static const minWidth = 48.0;

  /// The line that keeps the column widths, under the table's rows.
  static final widthsLine = RegExp(r'^<!--\s*table-widths:\s*([\d.,\s]*?)\s*-->\s*$');

  int get columns => aligns.length;
  int get rowCount => rows.length;

  static final _separatorCell = RegExp(r'^:?-+:?$');

  /// Reads the lines of a table block. Lines that are not `| ... |` rows are
  /// skipped; a missing separator row makes every row a body row after the
  /// first. Null when there is no row at all.
  static TableData? parse(String markdown) {
    final lines = markdown.split('\n').where((l) => l.trim().isNotEmpty).toList();
    List<double>? widths;
    lines.removeWhere((line) {
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
    return TableData(rows, filled, read == null || read.isEmpty ? null : read);
  }

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
        cells.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    cells.add(buffer.toString().trim());
    return cells;
  }

  /// The table as Markdown lines with the columns padded to equal width.
  String toMarkdown() {
    final escaped = rows.map((r) => r.map((c) => c.replaceAll('|', r'\|').replaceAll('\n', ' ')).toList()).toList();
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
    return [
      line(escaped[0]),
      separator,
      for (var r = 1; r < escaped.length; r++) line(escaped[r]),
      if (set != null) '<!-- table-widths: ${set.map((w) => w.round()).join(',')} -->',
    ].join('\n');
  }

  TableData copy() =>
      TableData([for (final r in rows) List.of(r)], List.of(aligns), widths == null ? null : List.of(widths!));

  void setCell(int row, int column, String value) => rows[row][column] = value;

  void insertRow(int at) => rows.insert(at.clamp(1, rows.length), List<String>.filled(columns, '', growable: true));

  /// Removes a body row; the header stays. False when there is no body row.
  bool removeRow(int at) {
    if (at < 1 || at >= rows.length) return false;
    rows.removeAt(at);
    return true;
  }

  void insertColumn(int at, {String header = ''}) {
    final c = at.clamp(0, columns);
    for (var r = 0; r < rows.length; r++) {
      rows[r].insert(c, r == 0 ? header : '');
    }
    aligns.insert(c, TableAlign.none);
    widths?.insert(c, defaultWidth);
  }

  /// Removes a column; the last one stays. False when it is the only column.
  bool removeColumn(int at) {
    if (columns <= 1 || at < 0 || at >= columns) return false;
    for (final row in rows) {
      row.removeAt(at);
    }
    aligns.removeAt(at);
    widths?.removeAt(at);
    return true;
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
  /// cells. Quoted cells may hold tabs, line breaks and `""` for a quote; a
  /// line break inside a cell becomes a space, as cells hold one line.
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
          cell.write(s[i] == '\n' ? ' ' : s[i]);
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
        rows[r][c] = i < source.length ? source[i].replaceAll(RegExp('[\t\n\r]'), ' ') : '';
      }
    }
    return (top, left, lastRow, lastColumn);
  }
}
