/// A Markdown (GitHub style) table as cells: the header row, the column
/// alignments and the body rows.
///
/// `| a | b |` lines are read and written here; the block keeps the lines
/// as its text, so a page that is never edited writes back exactly as read.
enum TableAlign { none, left, center, right }

class TableData {
  TableData(this.rows, this.aligns) : assert(rows.isNotEmpty);

  /// Row 0 is the header; every row has [columns] cells.
  final List<List<String>> rows;
  final List<TableAlign> aligns;

  int get columns => aligns.length;
  int get rowCount => rows.length;

  static final _separatorCell = RegExp(r'^:?-+:?$');

  /// Reads the lines of a table block. Lines that are not `| ... |` rows are
  /// skipped; a missing separator row makes every row a body row after the
  /// first. Null when there is no row at all.
  static TableData? parse(String markdown) {
    final lines = markdown.split('\n').where((l) => l.trim().isNotEmpty).toList();
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
    return TableData(rows, filled);
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
    return [line(escaped[0]), separator, for (var r = 1; r < escaped.length; r++) line(escaped[r])].join('\n');
  }

  TableData copy() => TableData([for (final r in rows) List.of(r)], List.of(aligns));

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
  }

  /// Removes a column; the last one stays. False when it is the only column.
  bool removeColumn(int at) {
    if (columns <= 1 || at < 0 || at >= columns) return false;
    for (final row in rows) {
      row.removeAt(at);
    }
    aligns.removeAt(at);
    return true;
  }
}
