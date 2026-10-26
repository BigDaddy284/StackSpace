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
import 'package:stack_space/ui/editor/image_dialog.dart';
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
    test('reads and writes a table, keeping escaped pipes and alignments', () {
      final data = TableData.parse('| Name | Count | Note |\n|:---|---:|:-:|\n| a \\| b | 1 | x |\n| c | 22 |  |')!;
      expect(data.rowCount, 3);
      expect(data.columns, 3);
      expect(data.rows[1], ['a | b', '1', 'x']);
      expect(data.rows[2], ['c', '22', '']);
      expect(data.aligns, [TableAlign.left, TableAlign.right, TableAlign.center]);
      expect(data.toMarkdown(),
          '| Name   | Count | Note |\n| :----- | ----: | :--: |\n| a \\| b | 1     | x    |\n| c      | 22    |      |');
    });

    test('a table without a separator or with ragged rows is repaired', () {
      final data = TableData.parse('| a | b |\n| 1 |\n| 2 | 3 | 4 |')!;
      expect(data.columns, 3);
      expect(data.rows, [
        ['a', 'b', ''],
        ['1', '', ''],
        ['2', '3', '4']
      ]);
      expect(data.aligns, everyElement(TableAlign.none));
      expect(data.toMarkdown().split('\n')[1], '| --- | --- | --- |');
      expect(TableData.parse('   '), isNull);
    });

    test('rows and columns are added and removed, never the header or the last column', () {
      final data = TableData.parse('| a | b |\n| --- | --- |\n| 1 | 2 |')!;
      data.insertRow(2);
      data.setCell(2, 0, 'new');
      expect(data.rows.length, 3);
      expect(data.rows[2], ['new', '']);
      data.insertColumn(1, header: 'mid');
      expect(data.rows[0], ['a', 'mid', 'b']);
      expect(data.rows[1], ['1', '', '2']);
      expect(data.removeRow(0), isFalse);
      expect(data.removeRow(1), isTrue);
      expect(data.rows[1], ['new', '', '']);
      expect(data.removeColumn(1), isTrue);
      expect(data.removeColumn(0), isTrue);
      expect(data.removeColumn(0), isFalse);
      expect(data.columns, 1);
    });

    test('column widths are kept on a comment line under the rows and follow added and removed columns', () {
      const markdown = '| a   | b   |\n| --- | --- |\n| 1   | 2   |\n<!-- table-widths: 120,200 -->';
      final data = TableData.parse(markdown)!;
      expect(data.rowCount, 2, reason: 'the widths line is not a row');
      expect(data.widths, [120, 200]);
      expect(data.toMarkdown(), markdown);
      data.insertColumn(1);
      expect(data.widths, [120, TableData.defaultWidth, 200]);
      data.removeColumn(0);
      expect(data.toMarkdown().split('\n').last, '<!-- table-widths: 160,200 -->');
      data.widths = null;
      expect(data.toMarkdown(), isNot(contains('table-widths')));
      expect(TableData.parse('| a | b | c |\n<!-- table-widths: 10 -->')!.widths,
          [TableData.minWidth, TableData.defaultWidth, TableData.defaultWidth],
          reason: 'too narrow is widened, missing widths are filled');

      final blocks = parseMarkdown('# T\n\n$markdown\n\nAfter\n');
      expect(blocks.map((b) => b.kind), [BlockKind.heading, BlockKind.table, BlockKind.paragraph]);
      expect(blocks[1].text, markdown);
      expect(writeMarkdown(blocks), '# T\n\n$markdown\n\nAfter\n');
    });

    test('cells copy as tab-separated text and paste back like a spreadsheet', () {
      final data = TableData.parse('| a | b | c |\n| --- | --- | --- |\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |')!;
      expect(data.toTsv(1, 0, 2, 1), '1\t2\n4\t5');
      data.setCell(1, 0, 'say "hi"\tthere');
      expect(data.toTsv(1, 0, 1, 1), '"say ""hi""\tthere"\t2');
      expect(TableData.parseTsv('"say ""hi""\tthere"\t2'), [
        ['say "hi"\tthere', '2']
      ]);
      expect(
          TableData.parseTsv('x\ty\r\nz\r\n'),
          [
            ['x', 'y'],
            ['z']
          ],
          reason: 'Excel ends with a line break and uses CRLF');
      expect(TableData.parseTsv('"two\nlines"'), [
        ['two lines']
      ]);

      // One value fills the selection.
      expect(
          data.paste(1, 0, 2, 1, [
            ['x']
          ]),
          (1, 0, 2, 1));
      expect(data.rows.sublist(1), [
        ['x', 'x', '3'],
        ['x', 'x', '6']
      ]);
      // A grid that fits a whole number of times repeats.
      data.paste(1, 0, 2, 2, [
        ['p', 'q', 'r']
      ]);
      expect(data.rows.sublist(1), [
        ['p', 'q', 'r'],
        ['p', 'q', 'r']
      ]);
      // Past the edge, rows and columns are added.
      expect(
          data.paste(2, 2, 2, 2, [
            ['m', 'n'],
            ['o', 'p']
          ]),
          (2, 2, 3, 3));
      expect(data.rows, [
        ['a', 'b', 'c', 'Column 4'],
        ['p', 'q', 'r', ''],
        ['p', 'q', 'm', 'n'],
        ['', '', 'o', 'p']
      ]);
      data.clear(2, 2, 3, 3);
      expect(data.rows[3], ['', '', '', '']);
    });
  });

  group('in the editor', () {
    late Directory dir;
    late PageEditorController editor;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('table_image_');
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

    Finder cell(int row, int column) => find.byKey(ValueKey('cell-${editor.document[1].id}-$row-$column'));

    Future<void> key(WidgetTester tester, LogicalKeyboardKey k, {bool shift = false, bool control = false}) async {
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(k);
      if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.pump();
    }

    bool focused(WidgetTester tester, Finder field) => tester.widget<TextField>(field).focusNode!.hasFocus;

    /// Taps a header button; the grid is rebuilt and the caret lands in it a frame later.
    Future<void> tapButton(WidgetTester tester, String label) async {
      await tester.tap(find.bySemanticsLabel(label));
      await tester.pump();
      await tester.pump();
    }

    const table = '# T\n\n| Name | Count |\n| --- | --- |\n| a | 1 |\n| b | 2 |\n\nAfter\n';

    testWidgets('a table shows as cells; typing writes padded Markdown and saves', (tester) async {
      await pumpEditor(tester, table);
      expect(find.byType(TableBlockView), findsOneWidget);
      expect(tester.widget<TextField>(cell(0, 0)).controller!.text, 'Name');
      expect(tester.widget<TextField>(cell(2, 1)).controller!.text, '2');
      expect(saved(), table, reason: 'an unedited table is written back as read');

      await tester.tap(cell(1, 1));
      await tester.pump();
      await tester.enterText(cell(1, 1), '10');
      await tester.pump();
      expect(editor.document[1].text, '| Name | Count |\n| ---- | ----- |\n| a    | 10    |\n| b    | 2     |');
      await settle(tester);
      await waitSaved(tester, editor);
      expect(saved(), '# T\n\n| Name | Count |\n| ---- | ----- |\n| a    | 10    |\n| b    | 2     |\n\nAfter\n');
    });

    testWidgets('Tab, Enter and arrows move between cells, add a row at the end and leave at the edges',
        (tester) async {
      await pumpEditor(tester, table);
      await tester.tap(cell(0, 0));
      await tester.pump();
      await key(tester, LogicalKeyboardKey.tab);
      expect(focused(tester, cell(0, 1)), isTrue);
      await key(tester, LogicalKeyboardKey.tab);
      expect(focused(tester, cell(1, 0)), isTrue, reason: 'Tab wraps to the next row');
      await key(tester, LogicalKeyboardKey.tab, shift: true);
      expect(focused(tester, cell(0, 1)), isTrue);
      await key(tester, LogicalKeyboardKey.enter);
      expect(focused(tester, cell(1, 1)), isTrue, reason: 'Enter moves down');
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(tester, cell(2, 1)), isTrue);
      await key(tester, LogicalKeyboardKey.tab);
      expect(editor.document[1].text.split('\n').length, 5, reason: 'Tab on the last cell adds a row');
      expect(focused(tester, cell(3, 0)), isTrue);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(editor.focusedBlock, 2, reason: 'Down from the last row leaves the table');
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(tester, cell(3, 1)), isTrue, reason: 'Up from the block below enters the last cell');
      await tester.tap(cell(0, 0));
      await tester.pump();
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(editor.focusedBlock, 0, reason: 'Up from the header leaves the table');
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(tester, cell(0, 0)), isTrue, reason: 'Down from the block above enters the first cell');
      await settle(tester);
    });

    testWidgets('the header buttons add and remove rows and columns; undo restores', (tester) async {
      await pumpEditor(tester, table);
      await tester.tap(cell(1, 0));
      await tester.pump();
      await tapButton(tester, 'Add column after');
      expect(editor.document[1].text.split('\n')[0], '| Name | Column 2 | Count |');
      expect(focused(tester, cell(0, 1)), isTrue, reason: 'the new header cell gets the caret');
      await tester.tap(cell(2, 0));
      await tester.pump();
      await tapButton(tester, 'Add row below');
      expect(editor.document[1].text.split('\n').length, 5);
      expect(focused(tester, cell(3, 0)), isTrue);
      await tapButton(tester, 'Delete row');
      expect(focused(tester, cell(2, 0)), isTrue, reason: 'the caret moves to the row that took its place');
      await tapButton(tester, 'Delete row');
      expect(focused(tester, cell(1, 0)), isTrue);
      expect(editor.document[1].text,
          '| Name | Column 2 | Count |\n| ---- | -------- | ----- |\n| a    |          | 1     |');
      await tapButton(tester, 'Delete column');
      expect(editor.document[1].text, '| Column 2 | Count |\n| -------- | ----- |\n|          | 1     |',
          reason: 'the focused column (Name) goes');
      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(editor.document[1].text,
          '| Name | Column 2 | Count |\n| ---- | -------- | ----- |\n| a    |          | 1     |');
      expect(find.byType(TableBlockView), findsOneWidget);
      await tapButton(tester, 'Delete table');
      expect(editor.document.length, 2);
      await settle(tester);
      await waitSaved(tester, editor);
      expect(saved(), '# T\n\nAfter\n');
    });

    String? mockClipboard(WidgetTester tester, [String? initial]) {
      String? clipboard = initial;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
        if (call.method == 'Clipboard.getData') return {'text': clipboard};
        if (call.method == 'Clipboard.hasStrings') return {'value': clipboard != null};
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      return clipboard;
    }

    Future<String?> clipboardText() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;

    TableBlockViewState tableState(WidgetTester tester) =>
        tester.state<TableBlockViewState>(find.byType(TableBlockView));

    /// Drags the mouse from the middle of one cell to the middle of another.
    Future<void> dragCells(WidgetTester tester, (int, int) from, (int, int) to) async {
      final gesture =
          await tester.startGesture(tester.getCenter(cell(from.$1, from.$2)), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(cell(to.$1, to.$2)));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('dragging across cells selects them; Ctrl+C copies, Ctrl+V pastes over, Delete empties',
        (tester) async {
      await pumpEditor(tester, table);
      mockClipboard(tester);
      await dragCells(tester, (0, 0), (1, 1));
      expect(tableState(tester).cellRange, (0, 0, 1, 1));
      expect(focused(tester, cell(0, 0)), isFalse, reason: 'no cell shows a caret while cells are selected');
      await key(tester, LogicalKeyboardKey.keyC, control: true);
      expect(await tester.runAsync(clipboardText), 'Name\tCount\na\t1');

      await key(tester, LogicalKeyboardKey.arrowDown, shift: true);
      expect(tableState(tester).cellRange, (0, 0, 2, 1), reason: 'Shift+arrows grow the selection');
      await key(tester, LogicalKeyboardKey.delete);
      expect(editor.document[1].text.split('\n').sublist(2), ['|     |     |', '|     |     |']);
      expect(tester.widget<TextField>(cell(1, 0)).controller!.text, '');

      // A copied block pastes from the top left of the selection.
      await tester.runAsync(() => Clipboard.setData(const ClipboardData(text: 'x\ty\r\nz\tw\r\n')));
      await key(tester, LogicalKeyboardKey.keyV, control: true);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      await tester.pump();
      expect(editor.document[1].text, '| x   | y   |\n| --- | --- |\n| z   | w   |\n|     |     |');
      expect(tableState(tester).cellRange, (0, 0, 1, 1), reason: 'the pasted cells stay selected');
      expect(tester.widget<TextField>(cell(1, 1)).controller!.text, 'w');

      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(editor.document[1].text.split('\n')[0], '|     |     |', reason: 'the paste is one undo step');
      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(editor.document[1].text.split('\n')[0], '| Name | Count |', reason: 'and so is the delete');

      await key(tester, LogicalKeyboardKey.escape);
      await settle(tester);
    });

    testWidgets('Shift+click selects from the caret; typing over a selection starts the first cell afresh',
        (tester) async {
      await pumpEditor(tester, table);
      mockClipboard(tester);
      await tester.tap(cell(1, 0));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(cell(2, 1), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(tableState(tester).cellRange, (1, 0, 2, 1));
      expect(focused(tester, cell(2, 1)), isFalse, reason: 'the click does not leave a caret in the cell');
      await key(tester, LogicalKeyboardKey.keyQ);
      expect(tableState(tester).hasCellRange, isFalse);
      expect(focused(tester, cell(1, 0)), isTrue);
      expect(tester.widget<TextField>(cell(1, 0)).controller!.text, 'q');
      await settle(tester);
    });

    testWidgets('pasting rows copied from a spreadsheet into one cell fills the cells from there, adding rows',
        (tester) async {
      await pumpEditor(tester, table);
      mockClipboard(tester, '7\n8\n9\n');
      await tester.tap(cell(2, 1));
      await tester.pump();
      await key(tester, LogicalKeyboardKey.keyV, control: true);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      await tester.pump();
      expect(
          editor.document[1].text.split('\n').sublist(3), ['| b    | 7     |', '|      | 8     |', '|      | 9     |']);
      expect(tableState(tester).cellRange, (2, 1, 4, 1));

      // Plain text still pastes at the caret.
      await key(tester, LogicalKeyboardKey.escape);
      expect(focused(tester, cell(2, 1)), isTrue);
      expect(tester.widget<TextField>(cell(2, 1)).controller!.selection, const TextSelection.collapsed(offset: 1));
      await tester.runAsync(() => Clipboard.setData(const ClipboardData(text: '0')));
      await key(tester, LogicalKeyboardKey.keyV, control: true);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(tester.widget<TextField>(cell(2, 1)).controller!.text, '70');
      expect(editor.document[1].text.split('\n')[3], '| b    | 70    |');
      await settle(tester);
    });

    testWidgets('a column border drags to set its width, which is saved; double-click makes columns even',
        (tester) async {
      await pumpEditor(tester, table);
      final before = tester.getSize(cell(0, 0)).width;
      var handle = find.byKey(ValueKey('resize-${editor.document[1].id}-0'));
      expect(handle, findsOneWidget);
      final gesture = await tester.startGesture(tester.getCenter(handle), kind: PointerDeviceKind.mouse);
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(-30, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
      final after = tester.getSize(cell(0, 0)).width;
      expect(after, lessThan(before - 100));
      final lines = editor.document[1].text.split('\n');
      expect(lines.last, startsWith('<!-- table-widths: '));
      final widths = TableData.parse(editor.document[1].text)!.widths!;
      expect(widths[0], closeTo(after, 1));
      expect(widths[1], closeTo(before, 1), reason: 'only the dragged column changes');
      await settle(tester);
      await waitSaved(tester, editor);
      expect(saved(), contains('| b    | 2     |\n<!-- table-widths: '));

      // Reopened, the widths are back.
      await pumpEditor(tester, saved());
      expect(tester.getSize(cell(0, 0)).width, closeTo(after, 1));
      handle = find.byKey(ValueKey('resize-${editor.document[1].id}-0'));

      await tester.tap(handle);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(handle);
      await tester.pump(const Duration(milliseconds: 400));
      expect(editor.document[1].text, isNot(contains('table-widths')));
      expect(tester.getSize(cell(0, 0)).width, closeTo(before, 1));
      await settle(tester);
    });

    testWidgets('the slash menu inserts a table and the caret lands in its first cell', (tester) async {
      await pumpEditor(tester, '# T\n\nx\n');
      final field = find.byType(TextField).at(1);
      await tester.enterText(field, '');
      await tester.pump();
      await tester.enterText(field, '/');
      await tester.pump();
      await tester.pump();
      await tester.enterText(field, '/table');
      await tester.pump();
      await tester.pump();
      await key(tester, LogicalKeyboardKey.enter);
      await tester.pump();
      expect(editor.document[1].kind, BlockKind.table);
      expect(focused(tester, cell(0, 0)), isTrue);
      await tester.enterText(cell(0, 0), 'Task');
      await tester.pump();
      await settle(tester);
      await waitSaved(tester, editor);
      expect(saved(), '# T\n\n| Task | Column 2 |\n| ---- | -------- |\n|      |          |\n');
    });

    testWidgets('an image has a description field that saves as the alt text; Enter below it adds a paragraph',
        (tester) async {
      await tester.runAsync(() => File('${dir.path}/pic.png').writeAsBytes(_png));
      await pumpEditor(tester, '# T\n\n![old](pic.png)\n');
      final alt = find.byKey(ValueKey('alt-${editor.document[1].id}'));
      expect(tester.widget<TextField>(alt).controller!.text, 'old');
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(alt);
      await tester.pump();
      await tester.enterText(alt, 'A cat');
      await tester.pump();
      expect(editor.document[1].alt, 'A cat');
      await key(tester, LogicalKeyboardKey.enter);
      expect(editor.document.length, 3);
      expect(editor.document[2].kind, BlockKind.paragraph);
      expect(editor.focusedBlock, 2);
      await settle(tester);
      await waitSaved(tester, editor);
      expect(saved(), '# T\n\n![A cat](pic.png)\n\n\n');
    });

    test('importImage copies a file from outside into images/ next to the page, keeps links and workspace files',
        () async {
      await Directory('${dir.path}/notes').create();
      await File('${dir.path}/notes/page.md').writeAsString('# P\n');
      await File('${dir.path}/shared.png').writeAsBytes(_png);
      await File('${dir.path}/notes/local.png').writeAsBytes(_png);
      final outside = await Directory.systemTemp.createTemp('outside_');
      addTearDown(() => deleteTemp(outside));
      await File('${outside.path}/my photo.png').writeAsBytes(_png);
      await editor.open('notes/page.md');

      expect(await importImage(editor, 'https://example.com/a.png'), 'https://example.com/a.png');
      expect(await importImage(editor, 'local.png'), 'local.png');
      expect(await importImage(editor, 'shared.png'), '../shared.png', reason: 'relative to the workspace root');
      expect(await importImage(editor, 'nowhere.png'), 'nowhere.png');
      expect(await importImage(editor, '${dir.path}/shared.png'), '../shared.png');
      expect(await importImage(editor, '${outside.path}/my photo.png'), 'images/my%20photo.png');
      expect(await File('${dir.path}/notes/images/my photo.png').exists(), isTrue);
      expect(await importImage(editor, '${outside.path}/my photo.png'), 'images/my%20photo-2.png',
          reason: 'a taken name gets a number');
      expect(editor.workspace.entries.any((e) => e.path == 'notes/images/my photo.png'), isTrue);
    });
  });
}

/// A 1x1 red PNG.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, //
  0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, //
  0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, //
  0x44, 0xAE, 0x42, 0x60, 0x82,
]);
