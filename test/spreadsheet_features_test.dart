import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/editor/blocks.dart';
import 'package:stack_space/editor/page_editor_controller.dart';
import 'package:stack_space/ui/editor/block_editor.dart';
import 'package:stack_space/ui/editor/table_block.dart';
import 'package:stack_space/workspace/workspace.dart';

import 'support/temp.dart';

/// The spreadsheet-like table features: pasting copied tables, moving and
/// filling cells by dragging, keyboard selection, the selection's sum, and
/// scrolling while a selection is dragged past the page's edge.
Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  late Directory dir;
  late PageEditorController editor;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('spreadsheet_');
    final workspace = Workspace(dir.path);
    await workspace.init();
    editor = PageEditorController(workspace);
  });

  tearDown(() async {
    editor.dispose();
    await deleteTemp(dir);
  });

  Future<void> pumpEditor(WidgetTester tester, String markdown, {Size size = const Size(1000, 800)}) async {
    await tester.runAsync(() async {
      await File('${dir.path}/page.md').writeAsString(markdown);
      await editor.open('page.md');
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BlockEditor(controller: editor, readOnly: false))));
    await tester.pump();
  }

  int tableIndex() => editor.document.blocks.indexWhere((b) => b.kind == BlockKind.table);
  List<String> lines() => editor.document[tableIndex()].text.split('\n');
  Finder cell(int row, int column) => find.byKey(ValueKey('cell-${editor.document[tableIndex()].id}-$row-$column'));
  TableBlockViewState grid(WidgetTester tester) => tester.state(find.byType(TableBlockView));
  String textAt(WidgetTester tester, int row, int column) => grid(tester).controllerAt(row, column).text;
  Finder grab(String name) => find.byKey(ValueKey('$name-${editor.document[tableIndex()].id}'));

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k, {bool shift = false, bool control = false}) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(k);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.pump();
  }

  Future<void> tapCell(WidgetTester tester, int row, int column) async {
    await tester.tap(cell(row, column));
    await tester.pump();
    await tester.pump(); // the cell's field is built, then takes the caret
  }

  Future<void> dragCells(WidgetTester tester, (int, int) from, (int, int) to) async {
    final gesture = await tester.startGesture(tester.getCenter(cell(from.$1, from.$2)), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(cell(to.$1, to.$2)));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump();
  }

  /// Drags [handle] (a frame edge or the fill handle) to the middle of the
  /// cell at [to], holding Ctrl when [control].
  Future<void> dragHandle(WidgetTester tester, Finder handle, (int, int) to, {bool control = false}) async {
    final gesture = await tester.startGesture(tester.getCenter(handle), kind: PointerDeviceKind.mouse);
    await tester.pump();
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final target = tester.getCenter(cell(to.$1, to.$2));
    await gesture.moveTo(Offset.lerp(tester.getCenter(handle), target, 0.5)!);
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
  }

  void mockClipboard(WidgetTester tester, String text) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': text};
      if (call.method == 'Clipboard.hasStrings') return {'value': true};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  }

  Future<void> pasteKeys(WidgetTester tester) async {
    await key(tester, LogicalKeyboardKey.keyV, control: true);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    await tester.pump();
  }

  const table = '# T\n\n| Name | Qty | Day |\n| --- | --- | --- |\n| Item 1 | 1 | Monday |\n| b | 2 | |\n'
      '| c | | |\n| d | | |\n\nAfter\n';

  testWidgets('a table copied from a spreadsheet pastes across the cells, adding rows; notes stay in one cell',
      (tester) async {
    await pumpEditor(tester, table);
    mockClipboard(tester, 'x\ty\r\nz\tw\r\nu\tv\r\n');
    await tapCell(tester, 3, 1);
    await pasteKeys(tester);
    expect(lines().sublist(4), ['| c      | x   | y      |', '| d      | z   | w      |', '|        | u   | v      |']);
    expect(grid(tester).cellRange, (3, 1, 5, 2), reason: 'the pasted cells are selected');
    await key(tester, LogicalKeyboardKey.escape);

    // A Markdown table pastes the same way, without its separator line.
    mockClipboard(tester, '| p | q |\n| --- | --- |\n| r | s |\n');
    await tapCell(tester, 1, 0);
    await pasteKeys(tester);
    expect(textAt(tester, 1, 0), 'p');
    expect(textAt(tester, 2, 1), 's');
    await key(tester, LogicalKeyboardKey.escape);

    // Lines of notes still go into the one cell.
    mockClipboard(tester, 'first line\nsecond line\n');
    await tapCell(tester, 4, 0);
    await pasteKeys(tester);
    expect(textAt(tester, 4, 0), 'dfirst line\nsecond line');
    expect(grid(tester).hasCellRange, isFalse);
    await settle(tester);
  });

  testWidgets('a table pasted into a paragraph becomes a table, without its border lines', (tester) async {
    await pumpEditor(tester, '# T\n\nIntro\n\nAfter\n');
    final intro = find.byWidgetPredicate((w) => w is EditableText && w.controller.text == 'Intro');
    await tester.tap(intro);
    await tester.pump();
    const drawn = '+------+-----+\n| Name | Qty |\n+======+=====+\n| a    | 1   |\n+------+-----+\n| b    | 2   |\n'
        '+------+-----+\n';
    await tester.enterText(intro, 'Intro$drawn');
    await tester.pump();
    await tester.pump();
    final kinds = editor.document.blocks.map((b) => b.kind).toList();
    expect(kinds, [BlockKind.heading, BlockKind.paragraph, BlockKind.table, BlockKind.paragraph]);
    expect(editor.document[1].text, 'Intro');
    expect(lines(), ['| Name | Qty |', '| ---- | --- |', '| a    | 1   |', '| b    | 2   |']);
    expect(find.byType(TableBlockView), findsOneWidget);

    // Undo takes the whole paste back.
    await key(tester, LogicalKeyboardKey.keyZ, control: true);
    expect(editor.document.blocks.map((b) => b.kind), isNot(contains(BlockKind.table)));
    await settle(tester);
  });

  testWidgets('a table pasted from a spreadsheet over all of a line replaces it', (tester) async {
    await pumpEditor(tester, '# T\n\nAfter\n');
    final after = find.byWidgetPredicate((w) => w is EditableText && w.controller.text == 'After');
    await tester.tap(after);
    await tester.pump();
    await tester.enterText(after, 'Name\tQty\r\nApples\t3\r\n');
    await tester.pump();
    await tester.pump();
    expect(editor.document.blocks.map((b) => b.kind), [BlockKind.heading, BlockKind.table, BlockKind.paragraph]);
    expect(lines(), ['| Name   | Qty |', '| ------ | --- |', '| Apples | 3   |']);
    await settle(tester);
  });

  testWidgets('dragging the selection border moves the cells; with Ctrl it copies them', (tester) async {
    await pumpEditor(tester, table);
    await dragCells(tester, (1, 0), (2, 1));
    expect(grid(tester).cellRange, (1, 0, 2, 1));
    // The press lands on the line between the two columns, so the block
    // moves by the rows the pointer went down: two.
    await dragHandle(tester, grab('move-cells-top'), (3, 1));
    expect([textAt(tester, 1, 0), textAt(tester, 1, 1), textAt(tester, 2, 0), textAt(tester, 2, 1)], ['', '', '', '']);
    expect([textAt(tester, 3, 0), textAt(tester, 3, 1)], ['Item 1', '1']);
    expect([textAt(tester, 4, 0), textAt(tester, 4, 1)], ['b', '2']);
    expect(lines()[4], startsWith('| Item 1 | 1 '), reason: 'saved to the page');
    expect(grid(tester).cellRange, (3, 0, 4, 1), reason: 'the moved cells stay selected');

    // Ctrl+drag copies them back, leaving these where they are.
    await dragHandle(tester, grab('move-cells-top'), (1, 0), control: true);
    expect([textAt(tester, 1, 0), textAt(tester, 1, 1)], ['Item 1', '1']);
    expect([textAt(tester, 3, 0), textAt(tester, 3, 1)], ['Item 1', '1']);
    await settle(tester);
  });

  testWidgets('one cell with the caret can be dragged by its border too', (tester) async {
    await pumpEditor(tester, table);
    await tapCell(tester, 2, 0);
    await dragHandle(tester, grab('move-cells-top'), (4, 2));
    expect(textAt(tester, 2, 0), '');
    expect(textAt(tester, 4, 2), 'b');
    expect(grid(tester).focusNodeAt(4, 2).hasFocus, isTrue, reason: 'the caret goes with it');
    await settle(tester);
  });

  testWidgets('the fill handle carries a series down and across', (tester) async {
    await pumpEditor(tester, table);
    await tapCell(tester, 1, 0);
    await dragHandle(tester, grab('fill-handle'), (4, 0));
    expect([for (var r = 1; r <= 4; r++) textAt(tester, r, 0)], ['Item 1', 'Item 2', 'Item 3', 'Item 4']);
    expect(grid(tester).cellRange, (1, 0, 4, 0), reason: 'the filled cells are selected');
    await key(tester, LogicalKeyboardKey.escape);

    // Two numbers set the step.
    await dragCells(tester, (1, 1), (2, 1));
    await dragHandle(tester, grab('fill-handle'), (4, 1));
    expect([textAt(tester, 3, 1), textAt(tester, 4, 1)], ['3', '4']);
    await key(tester, LogicalKeyboardKey.escape);

    // Day names go on in order.
    await tapCell(tester, 1, 2);
    await dragHandle(tester, grab('fill-handle'), (3, 2));
    expect([textAt(tester, 2, 2), textAt(tester, 3, 2)], ['Tuesday', 'Wednesday']);
    expect(lines()[3], contains('Tuesday'), reason: 'saved to the page');
    await settle(tester);
  });

  testWidgets('Ctrl+D and Ctrl+R copy down and right; Ctrl+Space, Shift+Space and Ctrl+Shift+arrows select',
      (tester) async {
    await pumpEditor(tester, table);
    await tapCell(tester, 2, 0);
    await key(tester, LogicalKeyboardKey.keyD, control: true);
    expect(textAt(tester, 2, 0), 'Item 1', reason: 'one cell: the cell above is copied in');
    await key(tester, LogicalKeyboardKey.keyR, control: true);
    expect(textAt(tester, 2, 0), 'Item 1', reason: 'nothing to the left of the first column');

    await dragCells(tester, (1, 1), (3, 1));
    await key(tester, LogicalKeyboardKey.keyD, control: true);
    expect([textAt(tester, 2, 1), textAt(tester, 3, 1)], ['1', '1']);
    await key(tester, LogicalKeyboardKey.escape);

    await tapCell(tester, 2, 1);
    await key(tester, LogicalKeyboardKey.space, control: true);
    expect(grid(tester).cellRange, (0, 1, 4, 1), reason: 'the whole column');
    await key(tester, LogicalKeyboardKey.space, shift: true);
    expect(grid(tester).cellRange, (0, 0, 4, 2), reason: 'the rows of the selection: all of them');
    await key(tester, LogicalKeyboardKey.escape);

    await dragCells(tester, (1, 0), (1, 1));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await key(tester, LogicalKeyboardKey.arrowDown, shift: true);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(grid(tester).cellRange, (1, 0, 4, 1), reason: 'Ctrl+Shift+Down grows to the last row');
    await settle(tester);
  });

  testWidgets('the header shows the count, sum and average of the selected cells', (tester) async {
    await pumpEditor(tester, table);
    final stats = find.byKey(ValueKey('table-stats-${editor.document[tableIndex()].id}'));
    expect(stats, findsNothing);
    await dragCells(tester, (1, 0), (2, 1));
    expect(tester.widget<Text>(stats).data, 'Count 4  ·  Sum 3  ·  Average 1.5');
    await key(tester, LogicalKeyboardKey.escape);
    expect(stats, findsNothing);
    await settle(tester);
  });

  testWidgets('with several rows or columns selected, the menu inserts that many', (tester) async {
    await pumpEditor(tester, table);
    await dragCells(tester, (1, 0), (2, 1));
    await tester.tap(cell(1, 0), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert 2 rows above'));
    await tester.pumpAndSettle();
    expect(lines().length, 2 + 6);
    expect(lines()[2], matches(RegExp(r'^\|\s+\|\s+\|\s+\|$')));
    expect(lines()[4], startsWith('| Item 1'));

    await dragCells(tester, (3, 0), (3, 1));
    await tester.tap(cell(3, 0), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert 2 columns right'));
    await tester.pumpAndSettle();
    expect(lines()[0].split('|').map((c) => c.trim()).where((c) => c.isNotEmpty),
        ['Name', 'Qty', 'Column 3', 'Column 4', 'Day']);
    await settle(tester);
  });

  testWidgets('dragging a selection past the bottom of the page scrolls it, and the selection follows', (tester) async {
    final rows = [for (var r = 1; r <= 40; r++) '| r$r | $r |'].join('\n');
    await pumpEditor(tester, '# T\n\n| A | B |\n| --- | --- |\n$rows\n\nAfter\n', size: const Size(900, 500));
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.pixels, 0);
    final gesture = await tester.startGesture(tester.getCenter(cell(2, 0)), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(cell(3, 0)));
    await tester.pump();
    // Hold the pointer at the bottom edge for a while.
    await gesture.moveTo(const Offset(200, 495));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scrollable.position.pixels, greaterThan(200), reason: 'the page scrolled down');
    final range = grid(tester).cellRange!;
    expect(range.$1, 2);
    expect(range.$3, greaterThan(10), reason: 'the selection grew with the scrolling');
    await gesture.up();
    await tester.pump();
    final at = scrollable.position.pixels;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scrollable.position.pixels, at, reason: 'letting go stops the scrolling');
    await settle(tester);
  });
}
