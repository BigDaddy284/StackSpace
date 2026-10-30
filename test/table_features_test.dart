import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/editor/blocks.dart';
import 'package:stack_space/editor/page_editor_controller.dart';
import 'package:stack_space/editor/table_data.dart';
import 'package:stack_space/ui/editor/block_editor.dart';
import 'package:stack_space/ui/editor/table_block.dart';
import 'package:stack_space/workspace/workspace.dart';
import 'support/temp.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  group('TableData', () {
    test('a line break in a cell is written as <br> and read back', () {
      final data = TableData.parse('| a | b |\n| --- | --- |\n| one<br>two | x<BR/>y<br />z |')!;
      expect(data.rows[1], ['one\ntwo', 'x\ny\nz']);
      data.setCell(1, 0, 'line 1\nline 2');
      expect(data.toMarkdown().split('\n')[2], '| line 1<br>line 2 | x<br>y<br>z |');
      expect(TableData.parse(data.toMarkdown())!.rows[1], ['line 1\nline 2', 'x\ny\nz']);
    });

    test('header row, wrapping, cell colours and filters are kept on a style line under the rows', () {
      final data = TableData.parse('| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | -> |')!;
      expect(data.toMarkdown(), isNot(contains('table-style')), reason: 'nothing is written for the defaults');
      data.header = false;
      data.wrap[1] = false;
      data.setColor(1, 0, 2, 0, 'green');
      data.filters[1] = const TableFilter(TableFilterOp.notContains, '->');
      final markdown = data.toMarkdown();
      final style = markdown.split('\n').last;
      expect(style, startsWith('<!-- table-style: {'));
      expect(style.indexOf('-->'), style.length - 3, reason: 'a ">" in a filter cannot end the comment early');

      final read = TableData.parse(markdown)!;
      expect(read.rowCount, 3, reason: 'the style line is not a row');
      expect(read.header, isFalse);
      expect(read.wrap, [true, false]);
      expect(read.colors, [
        [null, null],
        ['green', null],
        ['green', null]
      ]);
      expect(read.filters[1], const TableFilter(TableFilterOp.notContains, '->'));
      expect(read.visibleRows, [0, 1], reason: 'with no header row, row 0 is filtered like the rest');
      expect(read.toMarkdown(), markdown);

      // With widths too, both lines stay with the table block.
      read.widths = [100, 200];
      final blocks = parseMarkdown('${read.toMarkdown()}\n\nAfter\n');
      expect(blocks.first.kind, BlockKind.table);
      expect(blocks.first.text, read.toMarkdown());
      expect(blocks[1].text, 'After');

      // A damaged style line is dropped; the table still reads.
      final damaged = TableData.parse('| a |\n| --- |\n| 1 |\n<!-- table-style: {"header": -->')!;
      expect(damaged.rowCount, 2);
      expect(damaged.header, isTrue);
    });

    test('rows and columns insert above and left, duplicate and move, carrying what they hold', () {
      final data = TableData.parse('| a | b | c |\n| --- | ---: | --- |\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |')!;
      data.widths = [100, 200, 300];
      data.wrap[1] = false;
      data.setColor(1, 1, 1, 1, 'red');

      data.insertRow(0);
      expect(data.rows[0], ['', '', ''], reason: 'a row above the header becomes the header');
      expect(data.colors[2][1], 'red', reason: 'colours move down with their rows');
      data.removeRow(0);

      data.duplicateRow(1);
      expect(data.rows.sublist(1), [
        ['1', '2', '3'],
        ['1', '2', '3'],
        ['4', '5', '6']
      ]);
      expect(data.colors[2][1], 'red');
      data.removeRow(2);

      data.duplicateColumn(1);
      expect(data.rows[1], ['1', '2', '2', '3']);
      expect(data.aligns[2], TableAlign.right);
      expect(data.widths, [100, 200, 200, 300]);
      expect(data.wrap, [true, false, false, true]);
      data.removeColumn(2);

      data.moveColumn(1, 3);
      expect(data.rows[0], ['a', 'c', 'b']);
      expect(data.rows[1], ['1', '3', '2']);
      expect(data.aligns, [TableAlign.none, TableAlign.none, TableAlign.right]);
      expect(data.widths, [100, 300, 200]);
      expect(data.wrap, [true, true, false]);
      expect(data.colors[1], [null, null, 'red']);
      data.moveColumn(2, 0);
      expect(data.rows[0], ['b', 'a', 'c']);

      data.moveRow(2, 1);
      expect(data.rows.sublist(1), [
        ['5', '4', '6'],
        ['2', '1', '3']
      ]);
      expect(data.colors[2][0], 'red');
      data.moveRow(1, 3);
      expect(data.rows[2], ['5', '4', '6'], reason: 'moved to the end');
      data.moveRow(1, 2);
      expect(data.rows[2], ['5', '4', '6'], reason: 'a row dropped where it is stays');
    });

    test('sorting puts numbers in order of value, words alphabetically and empty cells last', () {
      final data = TableData.parse('| Item | Price |\n| --- | --- |\n'
          '| pear | \$1,200 |\n| apple | 9.5 |\n| Fig |  |\n| banana | -3 |\n| cherry | 10% |\n| date | n/a |')!;
      data.setColor(1, 0, 1, 0, 'blue');
      data.sortBy(1);
      expect([for (final r in data.rows.skip(1)) r[0]], ['banana', 'apple', 'cherry', 'pear', 'date', 'Fig']);
      expect(data.rows[0], ['Item', 'Price'], reason: 'the header row stays on top');
      expect(data.colors[4][0], 'blue', reason: 'colours go with their rows');
      data.sortBy(1, descending: true);
      expect([for (final r in data.rows.skip(1)) r[0]], ['date', 'pear', 'cherry', 'apple', 'banana', 'Fig'],
          reason: 'descending, still with the empty cell last');
      data.sortBy(0);
      expect([for (final r in data.rows.skip(1)) r[0]], ['apple', 'banana', 'cherry', 'date', 'Fig', 'pear'],
          reason: 'case is ignored');
      data.header = false;
      data.sortBy(0);
      expect(data.rows[0][0], 'apple', reason: 'without a header row, the first row sorts too');
      expect(data.rows.last[0], 'pear');
      expect(data.rows.any((r) => r[0] == 'Item'), isTrue);
    });

    test('filters hide rows that fail them, ignoring case; a header row always shows', () {
      final data = TableData.parse('| Name | Note |\n| --- | --- |\n| Ann | Yes |\n| Bob |  |\n| Cy | yes please |')!;
      data.filters[1] = const TableFilter(TableFilterOp.contains, 'YES');
      expect(data.visibleRows, [0, 1, 3]);
      data.filters[1] = const TableFilter(TableFilterOp.isEmpty);
      expect(data.visibleRows, [0, 2]);
      data.filters[1] = const TableFilter(TableFilterOp.isNotEmpty);
      data.filters[0] = const TableFilter(TableFilterOp.notContains, 'ann');
      expect(data.visibleRows, [0, 3]);
      expect(data.isFiltered, isTrue);
      data.removeColumn(0);
      expect(data.filters, [const TableFilter(TableFilterOp.isNotEmpty)], reason: 'a filter goes with its column');
    });
  });

  group('in the editor', () {
    late Directory dir;
    late PageEditorController editor;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('table_features_');
      final workspace = Workspace(dir.path);
      await workspace.init();
      editor = PageEditorController(workspace);
    });

    tearDown(() async {
      editor.dispose();
      await deleteTemp(dir);
    });

    Future<void> pumpEditor(WidgetTester tester, String markdown) async {
      await tester.runAsync(() async {
        await File('${dir.path}/page.md').writeAsString(markdown);
        await editor.open('page.md');
      });
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: BlockEditor(controller: editor, readOnly: false))));
      await tester.pump();
    }

    String saved() => File('${dir.path}/page.md').readAsStringSync();
    String tableText() => editor.document[1].text;
    List<String> lines() => tableText().split('\n');

    Finder cell(int row, int column) => find.byKey(ValueKey('cell-${editor.document[1].id}-$row-$column'));
    TableBlockViewState grid(WidgetTester tester) => tester.state(find.byType(TableBlockView));
    TextEditingController text(WidgetTester tester, int row, int column) => grid(tester).controllerAt(row, column);

    Future<void> key(WidgetTester tester, LogicalKeyboardKey k, {bool shift = false, bool control = false}) async {
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(k);
      if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.pump();
    }

    bool focused(WidgetTester tester, Finder field) {
      final key = (tester.widget(field).key! as ValueKey<String>).value.split('-');
      return grid(tester).focusNodeAt(int.parse(key[2]), int.parse(key[3])).hasFocus;
    }

    /// The cell's text field, which shows while the cell has the caret.
    Finder field(int row, int column) => find.descendant(of: cell(row, column), matching: find.byType(TextField));

    /// Right-clicks a cell and picks [item] from the table menu.
    Future<void> menu(WidgetTester tester, (int, int) at, String item) async {
      await tester.tap(cell(at.$1, at.$2), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    const table = '# T\n\n| Name | Count |\n| --- | --- |\n| a | 1 |\n| b | 2 |\n\nAfter\n';

    testWidgets('Shift+Tab and Shift+Enter start a new line in the cell; it saves as <br> and the row grows',
        (tester) async {
      await pumpEditor(tester, table);
      Finder box(int row, int column) => find.descendant(of: cell(row, column), matching: find.byType(Container)).first;
      final before = tester.getSize(box(1, 0)).height;
      expect(before, TableBlockView.cellHeight);
      await tester.tap(cell(1, 0));
      await tester.pump();
      await tester.pump(); // the cell's field is built, then takes the caret
      await key(tester, LogicalKeyboardKey.tab, shift: true);
      expect(focused(tester, cell(1, 0)), isTrue, reason: 'the caret stays in the cell');
      expect(text(tester, 1, 0).text, 'a\n');
      await tester.enterText(field(1, 0), 'a\nsecond');
      await tester.pump();
      await key(tester, LogicalKeyboardKey.enter, shift: true);
      await tester.enterText(field(1, 0), 'a\nsecond\nthird');
      await tester.pump();
      await tester.pump();
      expect(lines()[2], '| a<br>second<br>third | 1     |');
      final grown = tester.getSize(box(1, 0)).height;
      expect(grown, greaterThan(before + 30), reason: 'three lines need a taller row');
      expect(tester.getSize(cell(1, 0)).height, lessThanOrEqualTo(grown), reason: 'the text fits in the row');

      // Up moves between the cell's own lines before it leaves the row.
      text(tester, 1, 0).selection = const TextSelection.collapsed(offset: 12); // in "third"
      await tester.pump();
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(tester, cell(1, 0)), isTrue);
      expect(text(tester, 1, 0).selection.baseOffset, lessThan(9));

      // Plain Enter still moves down a row.
      await key(tester, LogicalKeyboardKey.enter);
      expect(focused(tester, cell(2, 0)), isTrue);

      await settle(tester);
      await waitSaved(tester, editor);
      expect(saved(), contains('| a<br>second<br>third | 1     |'));
      // Reopened, the cell has its lines back.
      await pumpEditor(tester, saved());
      expect(text(tester, 1, 0).text, 'a\nsecond\nthird');
      await settle(tester);
    });

    testWidgets('long text wraps in its column, and the column can be set not to wrap', (tester) async {
      final long = List.filled(30, 'word').join(' ');
      await pumpEditor(tester, '# T\n\n| Name | Note |\n| --- | --- |\n| a | $long |\n\nAfter\n');
      Finder box(int row, int column) => find.descendant(of: cell(row, column), matching: find.byType(Container)).first;
      expect(tester.getSize(box(1, 1)).height, greaterThan(TableBlockView.cellHeight * 2));
      expect(tester.getSize(box(1, 0)).height, tester.getSize(box(1, 1)).height,
          reason: 'every cell of a row is as tall as its tallest');

      await menu(tester, (1, 1), 'Wrap text in column');
      expect(tester.getSize(box(1, 1)).height, TableBlockView.cellHeight);
      expect(lines().last, '<!-- table-style: {"nowrap":[1]} -->');
      await menu(tester, (1, 1), 'Wrap text in column');
      expect(tester.getSize(box(1, 1)).height, greaterThan(TableBlockView.cellHeight * 2));
      expect(tableText(), isNot(contains('table-style')));
      await settle(tester);
    });

    testWidgets('the menu inserts rows above and below and columns left and right, and duplicates them',
        (tester) async {
      await pumpEditor(tester, table);
      await menu(tester, (1, 0), 'Insert row above');
      expect(lines().sublist(2), ['|      |       |', '| a    | 1     |', '| b    | 2     |']);
      expect(focused(tester, cell(1, 0)), isTrue, reason: 'the caret goes to the new row');
      await menu(tester, (2, 0), 'Insert row below');
      expect(lines().sublist(2), ['|      |       |', '| a    | 1     |', '|      |       |', '| b    | 2     |']);
      await menu(tester, (2, 1), 'Insert column left');
      expect(lines()[0], '| Name | Column 2 | Count |');
      await menu(tester, (2, 0), 'Insert column right');
      expect(lines()[0], '| Name | Column 2 | Column 2 | Count |');
      await menu(tester, (2, 0), 'Duplicate row');
      expect(lines()[3], '| a    |          |          | 1     |');
      expect(lines()[4], '| a    |          |          | 1     |');
      await menu(tester, (0, 3), 'Duplicate column');
      expect(lines()[0], '| Name | Column 2 | Column 2 | Count | Count |');

      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(lines()[0], '| Name | Column 2 | Column 2 | Count |', reason: 'each is one undo step');
      await settle(tester);
    });

    testWidgets('the menu sorts by a column, filters rows, colours cells, aligns and turns off the header row',
        (tester) async {
      await pumpEditor(tester, '# T\n\n| Name | Count |\n| --- | --- |\n| b | 10 |\n| c | 9 |\n| a | 100 |\n\nAfter\n');
      await menu(tester, (1, 1), 'Sort by Count, A → Z');
      expect(lines().sublist(2), ['| c    | 9     |', '| b    | 10    |', '| a    | 100   |']);
      await menu(tester, (1, 0), 'Sort by Name, Z → A');
      expect(lines().sublist(2), ['| c    | 9     |', '| b    | 10    |', '| a    | 100   |']);
      await menu(tester, (1, 0), 'Sort by Name, A → Z');
      expect(lines().sublist(2), ['| a    | 100   |', '| b    | 10    |', '| c    | 9     |']);

      await menu(tester, (1, 1), 'Filter by Count…');
      expect(find.text('Filter by Count'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('table-filter-text')), '10');
      await tester.tap(find.text('Filter'));
      await tester.pumpAndSettle();
      expect(cell(3, 0), findsNothing, reason: '"9" does not contain 10');
      expect(cell(1, 0), findsOneWidget);
      expect(find.text('Showing 2 of 3 rows'), findsOneWidget);
      expect(lines().last, '<!-- table-style: {"filters":{"1":{"op":"contains","value":"10"}}} -->');
      await tester.tap(find.bySemanticsLabel('Clear filters'));
      await tester.pumpAndSettle();
      expect(cell(3, 0), findsOneWidget);
      expect(tableText(), isNot(contains('table-style')));

      await menu(tester, (1, 0), 'Cell colour');
      await tester.tap(find.text('Yellow'));
      await tester.pumpAndSettle();
      expect(lines().last, '<!-- table-style: {"colors":{"1,0":"yellow"}} -->');
      final box = find.descendant(of: cell(1, 0), matching: find.byType(Container)).first;
      expect((tester.widget<Container>(box).color), isNotNull);

      await menu(tester, (1, 1), 'Align column');
      await tester.tap(find.text('Right'));
      await tester.pumpAndSettle();
      expect(lines()[1], '| ---- | ----: |');
      expect(tester.widget<TextField>(field(1, 1)).textAlign, TextAlign.right);

      await menu(tester, (1, 0), 'Header row');
      expect(lines().last, '<!-- table-style: {"header":false,"colors":{"1,0":"yellow"}} -->');
      final header = field(0, 0).evaluate().isEmpty
          ? tester.widget<Text>(find.descendant(of: cell(0, 0), matching: find.byType(Text))).textSpan!.style!
          : tester.widget<TextField>(field(0, 0)).style!;
      expect(header.fontWeight, FontWeight.normal);
      await settle(tester);
    });

    testWidgets('Shift+F10 opens the menu for the focused cell', (tester) async {
      await pumpEditor(tester, table);
      await tester.tap(cell(2, 0));
      await tester.pump();
      await tester.pump(); // the cell's field is built, then takes the caret
      await key(tester, LogicalKeyboardKey.f10, shift: true);
      await tester.pumpAndSettle();
      expect(find.text('Insert row above'), findsOneWidget);
      await tester.tap(find.text('Delete row'));
      await tester.pumpAndSettle();
      expect(lines().sublist(2), ['| a    | 1     |']);
      await settle(tester);
    });

    testWidgets('a row and a column drag to a new place by their grips', (tester) async {
      await pumpEditor(
          tester,
          '# T\n\n| Name | Count | Note |\n| --- | --- | --- |\n| a | 1 | x |\n| b | 2 | y |\n'
          '| c | 3 | z |\n\nAfter\n');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(cell(1, 1)));
      await tester.pump();
      final id = editor.document[1].id;
      final rowGrip = find.byKey(ValueKey('row-grip-$id-1'));
      expect(rowGrip, findsOneWidget, reason: 'the hovered row shows its grip');
      expect(find.byKey(ValueKey('column-grip-$id-1')), findsOneWidget);

      // Row "a" below row "c".
      final drag = await tester.startGesture(tester.getCenter(rowGrip), kind: PointerDeviceKind.mouse);
      await tester.pump();
      final target = tester.getBottomLeft(cell(3, 0)) + const Offset(20, -4);
      for (var i = 1; i <= 6; i++) {
        await drag.moveTo(Offset.lerp(tester.getCenter(rowGrip), target, i / 6)!);
        await tester.pump();
      }
      await drag.up();
      await tester.pump();
      await tester.pump();
      expect(lines().sublist(2), ['| b    | 2     | y    |', '| c    | 3     | z    |', '| a    | 1     | x    |']);

      // Column "Note" before "Name".
      await mouse.moveTo(tester.getCenter(cell(1, 2)));
      await tester.pump();
      final columnGrip = find.byKey(ValueKey('column-grip-$id-2'));
      expect(columnGrip, findsOneWidget);
      final columnDrag = await tester.startGesture(tester.getCenter(columnGrip), kind: PointerDeviceKind.mouse);
      await tester.pump();
      final left = tester.getTopLeft(cell(0, 0)) + const Offset(6, 4);
      for (var i = 1; i <= 6; i++) {
        await columnDrag.moveTo(Offset.lerp(tester.getCenter(columnGrip), left, i / 6)!);
        await tester.pump();
      }
      await columnDrag.up();
      await tester.pump();
      await tester.pump();
      expect(lines()[0], '| Note | Name | Count |');
      expect(lines()[2], '| y    | b    | 2     |');

      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(lines()[0], '| Name | Count | Note |', reason: 'a move is one undo step');
      await settle(tester);
    });

    testWidgets('Alt+Shift+arrows move the row and column with the caret in it', (tester) async {
      await pumpEditor(tester, '# T\n\n| Name | Count |\n| --- | --- |\n| a | 1 |\n| b | 2 |\n\nAfter\n');
      await tester.tap(cell(1, 0));
      await tester.pump();
      await tester.pump(); // the cell's field is built, then takes the caret
      Future<void> altShift(LogicalKeyboardKey k) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await key(tester, k, shift: true);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pump();
        await tester.pump();
      }

      await altShift(LogicalKeyboardKey.arrowDown);
      expect(lines().sublist(2), ['| b    | 2     |', '| a    | 1     |']);
      expect(focused(tester, cell(2, 0)), isTrue, reason: 'the caret moves with the row');
      await altShift(LogicalKeyboardKey.arrowRight);
      expect(lines()[0], '| Count | Name |');
      expect(focused(tester, cell(2, 1)), isTrue);
      await altShift(LogicalKeyboardKey.arrowUp);
      await altShift(LogicalKeyboardKey.arrowUp);
      expect(lines().sublist(2), ['| 1     | a    |', '| 2     | b    |'], reason: 'it stops under the header');
      await settle(tester);
    });

    testWidgets('a header row cannot be dragged, and nothing drags past it', (tester) async {
      await pumpEditor(tester, table);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(cell(0, 0)));
      await tester.pump();
      final id = editor.document[1].id;
      expect(find.byKey(ValueKey('row-grip-$id-0')), findsNothing);
      await mouse.moveTo(tester.getCenter(cell(2, 0)));
      await tester.pump();
      final grip = find.byKey(ValueKey('row-grip-$id-2'));
      final drag = await tester.startGesture(tester.getCenter(grip), kind: PointerDeviceKind.mouse);
      await tester.pump();
      for (var i = 1; i <= 6; i++) {
        await drag.moveTo(Offset.lerp(tester.getCenter(grip), tester.getTopLeft(cell(0, 0)), i / 6)!);
        await tester.pump();
      }
      await drag.up();
      await tester.pump();
      expect(lines().sublist(0, 4), ['| Name | Count |', '| ---- | ----- |', '| b    | 2     |', '| a    | 1     |'],
          reason: 'dropped on the header, the row goes just under it');
      await settle(tester);
    });

    testWidgets('arrows and Tab skip rows a filter hides', (tester) async {
      await pumpEditor(
          tester,
          '# T\n\n| Name | Keep |\n| --- | --- |\n| a | y |\n| b |  |\n| c | y |\n'
          '<!-- table-style: {"filters":{"1":{"op":"isNotEmpty"}}} -->\n\nAfter\n');
      expect(cell(2, 0), findsNothing);
      await tester.tap(cell(1, 0));
      await tester.pump();
      await tester.pump(); // the cell's field is built, then takes the caret
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(tester, cell(3, 0)), isTrue);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(tester, cell(1, 0)), isTrue);
      await key(tester, LogicalKeyboardKey.tab);
      await key(tester, LogicalKeyboardKey.tab);
      expect(focused(tester, cell(3, 0)), isTrue);
      await settle(tester);
    });
  });
}
