import 'table_data.dart';

/// Reads text copied from a table as rows of cells: tab-separated lines (a
/// spreadsheet, a web page or another StackSpace table), a Markdown table,
/// or a table drawn with lines (`+---+`, `│`, `─`, `═`). The lines that only
/// draw borders are dropped. Null when the text is not a table: plain
/// lines, a paragraph, a list, lines with tabs in some but not others.
///
/// [minRows] and [minColumns] say how big it must be to count; a page asks
/// for at least two of each, a cell for one row of two cells.
List<List<String>>? parseTableText(String text, {int minRows = 1, int minColumns = 2}) {
  var s = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  while (s.endsWith('\n')) {
    s = s.substring(0, s.length - 1);
  }
  while (s.startsWith('\n')) {
    s = s.substring(1);
  }
  if (s.trim().isEmpty) return null;
  final lines = s.split('\n');
  List<List<String>>? rows;
  if (s.contains('\t')) {
    // Spreadsheets copy every row with the same number of cells; a note
    // with a tab in one line is not a table.
    final tsv = TableData.parseTsv(s).where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
    if (tsv.every((r) => r.length == tsv.first.length)) rows = tsv;
  } else if (_drawn(lines)) {
    rows = _readDrawn(lines);
  }
  if (rows == null) return null;
  rows = [
    for (final row in rows)
      if (row.any((c) => c.trim().isNotEmpty)) row,
  ];
  if (rows.length < minRows) return null;
  final width = rows.fold(0, (w, r) => r.length > w ? r.length : w);
  if (width < minColumns) return null;
  // Every row as wide as the widest, and no column left empty at the edges
  // (a line that starts or ends with a tab).
  final grid = [
    for (final row in rows) [for (var c = 0; c < width; c++) c < row.length ? row[c].trim() : ''],
  ];
  bool emptyColumn(int c) => grid.every((r) => r[c].isEmpty);
  var left = 0, right = width - 1;
  while (left < right && emptyColumn(left)) {
    left++;
  }
  while (right > left && emptyColumn(right)) {
    right--;
  }
  if (right - left + 1 < minColumns) return null;
  return [for (final row in grid) row.sublist(left, right + 1)];
}

/// The characters a table's borders are drawn with.
const _vertical = '|│┃║';
final _borderLine = RegExp(r'^[\s+\-=_:|.─━═│┃║┌┐└┘├┤┬┴┼╔╗╚╝╠╣╦╩╬╒╕╘╛╞╡╤╧╪╓╖╙╜╟╢╥╨╫┏┓┗┛┣┫┳┻╋]*$');
final _hasRule = RegExp(r'[-=─━═]{2,}|[─━═]');
final _cellSeparator = RegExp('[$_vertical]');

/// True for a line that only draws a border: `+----+----+`, `|---|:--:|`,
/// `├────┼────┤`.
bool _isBorder(String line) => line.trim().isNotEmpty && _borderLine.hasMatch(line) && _hasRule.hasMatch(line);

/// A Markdown table, or one drawn with lines: every line that is not a
/// border has a cell separator, and either a border line is there or the
/// lines start and end with a separator.
bool _drawn(List<String> lines) {
  final content = [
    for (final l in lines)
      if (l.trim().isNotEmpty && !_isBorder(l)) l.trim(),
  ];
  if (content.isEmpty || !content.every((l) => l.contains(_cellSeparator))) return false;
  final framed = content.every((l) => _vertical.contains(l[0]) && _vertical.contains(l[l.length - 1]));
  return framed || lines.any(_isBorder);
}

List<List<String>> _readDrawn(List<String> lines) => [
      for (final line in lines)
        if (line.trim().isNotEmpty && !_isBorder(line)) _splitDrawn(line.trim()),
    ];

/// The cells of one drawn row. A Markdown row uses [TableData.splitRow], so
/// an escaped `\|` stays in the cell and `<br>` becomes a line break.
List<String> _splitDrawn(String line) {
  if (!line.contains(RegExp('[│┃║]'))) return TableData.splitRow(line);
  var s = line;
  if (_vertical.contains(s[0])) s = s.substring(1);
  if (s.isNotEmpty && _vertical.contains(s[s.length - 1])) s = s.substring(0, s.length - 1);
  return s.split(_cellSeparator).map((c) => c.trim()).toList();
}

/// [grid] as a Markdown table, its first row the header.
String gridToMarkdown(List<List<String>> grid) {
  final width = grid.fold(0, (w, r) => r.length > w ? r.length : w);
  final rows = [
    for (final r in grid) [for (var c = 0; c < width; c++) c < r.length ? r[c] : ''],
  ];
  return TableData(rows, List.filled(width, TableAlign.none, growable: true)).toMarkdown();
}
