import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/editor/table_clip.dart';
import 'package:stack_space/editor/table_data.dart';

void main() {
  group('parseTableText', () {
    test('reads rows copied from a spreadsheet', () {
      expect(parseTableText('Name\tQty\r\nApples\t3\r\nPears\t5\r\n'), [
        ['Name', 'Qty'],
        ['Apples', '3'],
        ['Pears', '5'],
      ]);
    });

    test('keeps a quoted spreadsheet cell with a line break in one cell', () {
      expect(parseTableText('a\t"two\nlines"\nc\td\n'), [
        ['a', 'two\nlines'],
        ['c', 'd'],
      ]);
    });

    test('reads a Markdown table without its separator line', () {
      expect(parseTableText('| Name | Qty |\n| --- | :-: |\n| Apples | 3 |\n| Pears | 5 |'), [
        ['Name', 'Qty'],
        ['Apples', '3'],
        ['Pears', '5'],
      ]);
    });

    test('reads a table drawn with + - | and drops the border lines', () {
      const drawn = '+--------+-----+\n'
          '| Name   | Qty |\n'
          '+========+=====+\n'
          '| Apples | 3   |\n'
          '+--------+-----+\n'
          '| Pears  | 5   |\n'
          '+--------+-----+\n';
      expect(parseTableText(drawn), [
        ['Name', 'Qty'],
        ['Apples', '3'],
        ['Pears', '5'],
      ]);
    });

    test('reads a table drawn with box lines', () {
      const drawn = '┌────────┬─────┐\n'
          '│ Name   │ Qty │\n'
          '├────────┼─────┤\n'
          '│ Apples │ 3   │\n'
          '└────────┴─────┘';
      expect(parseTableText(drawn), [
        ['Name', 'Qty'],
        ['Apples', '3'],
      ]);
    });

    test('reads a table framed with ║ and ═ lines', () {
      expect(parseTableText('╔═══╦═══╗\n║ a ║ b ║\n╠═══╬═══╣\n║ 1 ║ 2 ║\n╚═══╩═══╝'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('drops empty columns at the edges and empty rows', () {
      expect(parseTableText('\ta\tb\t\n\t\t\t\n\t1\t2\t\n'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('is not fooled by notes, lists or prose', () {
      expect(parseTableText('first line\nsecond line\nthird'), isNull);
      expect(parseTableText('- one\n- two\n- three'), isNull);
      expect(parseTableText('first line\r\nsecond\tpart\nthird\n'), isNull, reason: 'one line with a tab');
      expect(parseTableText('a | b in a sentence\nand more'), isNull);
      expect(parseTableText('---\n'), isNull);
      expect(parseTableText(''), isNull);
    });

    test('minRows and minColumns', () {
      expect(parseTableText('a\tb'), [
        ['a', 'b']
      ]);
      expect(parseTableText('a\tb', minRows: 2), isNull);
      expect(parseTableText('a\nb'), isNull);
    });

    test('gridToMarkdown makes a table the editor reads back', () {
      final md = gridToMarkdown([
        ['Name', 'Qty'],
        ['Apples', '3'],
        ['Pipe | in', 'two\nlines'],
      ]);
      final data = TableData.parse(md)!;
      expect(data.rows, [
        ['Name', 'Qty'],
        ['Apples', '3'],
        ['Pipe | in', 'two\nlines'],
      ]);
    });
  });

  group('fill series', () {
    test('numbers go on by the last step; one number repeats', () {
      expect(TableData.series(['1', '2'], 3), ['3', '4', '5']);
      expect(TableData.series(['10', '8'], 2), ['6', '4']);
      expect(TableData.series(['1.5', '2'], 2), ['2.5', '3.0']);
      expect(TableData.series(['\$1,000', '\$2,000'], 1), ['\$3,000']);
      expect(TableData.series(['10%', '20%'], 1), ['30%']);
      expect(TableData.series(['7'], 3), ['7', '7', '7']);
    });

    test('text ending in a number counts up', () {
      expect(TableData.series(['Item 3'], 3), ['Item 4', 'Item 5', 'Item 6']);
      expect(TableData.series(['Q1', 'Q3'], 2), ['Q5', 'Q7']);
      expect(TableData.series(['row-009'], 2), ['row-010', 'row-011']);
    });

    test('dates, days and months', () {
      expect(TableData.series(['2026-12-30'], 3), ['2026-12-31', '2027-01-01', '2027-01-02']);
      expect(TableData.series(['2026-01-01', '2026-01-08'], 2), ['2026-01-15', '2026-01-22']);
      expect(TableData.series(['Friday'], 3), ['Saturday', 'Sunday', 'Monday']);
      expect(TableData.series(['Mon', 'Wed'], 2), ['Fri', 'Sun']);
      expect(TableData.series(['nov'], 3), ['dec', 'jan', 'feb']);
      expect(TableData.series(['MARCH'], 1), ['APRIL']);
    });

    test('other text repeats the cells in turn', () {
      expect(TableData.series(['Open', 'Done'], 3), ['Open', 'Done', 'Open']);
      expect(TableData.series([''], 2), ['', '']);
    });
  });

  group('TableData block edits', () {
    TableData sample() =>
        TableData.parse('| A | B | C |\n| --- | --- | --- |\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |\n| 7 | 8 | 9 |')!;

    test('moveBlock moves cells and colours, emptying where they were', () {
      final data = sample();
      data.colors[1][0] = 'red';
      expect(data.moveBlock(1, 0, 2, 0, 2, 2), (2, 2, 3, 2));
      expect(data.rows.sublist(1), [
        ['', '2', '3'],
        ['', '5', '1'],
        ['7', '8', '4'],
      ]);
      expect(data.colors[2][2], 'red');
      expect(data.colors[1][0], isNull);
    });

    test('moveBlock with copy keeps the source, and stays inside the table', () {
      final data = sample();
      expect(data.moveBlock(1, 0, 1, 1, 9, 9, copy: true), (3, 1, 3, 2));
      expect(data.rows[1], ['1', '2', '3']);
      expect(data.rows[3], ['7', '1', '2']);
    });

    test('fill down, up, right and left', () {
      var data = sample();
      expect(data.fill(1, 0, 2, 0, toRow: 3), (1, 0, 3, 0));
      expect(data.rows[3][0], '7', reason: '1, 4 → 7');
      data = sample();
      expect(data.fill(1, 0, 1, 1, toColumn: 2), (1, 0, 1, 2));
      expect(data.rows[1], ['1', '2', '3']);
      data = sample();
      data.fill(3, 1, 3, 1, toRow: 1);
      expect([data.rows[1][1], data.rows[2][1]], ['8', '8']);
      data = sample();
      data.fill(1, 1, 1, 2, toColumn: 0);
      expect(data.rows[1][0], '1', reason: '3, 2 → 1 going left');
    });

    test('stats count filled cells and add up the numbers', () {
      final data = sample();
      data.setCell(1, 0, 'n/a');
      final s = data.stats(1, 0, 3, 2);
      expect(s.count, 9);
      expect(s.numbers, 8);
      expect(s.sum, 44);
      expect(s.average, 5.5);
      expect(data.stats(0, 0, 0, 2).sum, isNull);
    });
  });
}
