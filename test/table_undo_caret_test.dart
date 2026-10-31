import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/editor/page_editor_controller.dart';
import 'package:stack_space/editor/table_data.dart';
import 'package:stack_space/ui/editor/block_editor.dart';
import 'package:stack_space/ui/editor/table_block.dart';
import 'package:stack_space/workspace/workspace.dart';

import 'support/temp.dart';

/// Ctrl+Z and Ctrl+Y in a table put the caret in the cell the change was in,
/// not in the table's last cell.
Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  group('TableData.firstChange', () {
    const table = '| Name | Count | Note |\n| --- | --- | --- |\n| a | 1 | x |\n| b | 2 | y |';

    test('finds the changed cell even when its column is re-padded on every row', () {
      final edited = TableData.parse(table)!..setCell(1, 1, '1 and a much longer value');
      expect(TableData.firstChange(edited.toMarkdown(), table), (1, 1, 1), reason: 'undo: after the "1"');
      expect(TableData.firstChange(table, edited.toMarkdown()), (1, 1, 25), reason: 'redo: after the typed text');
    });

    test('puts the caret at the end of the changed text inside the cell', () {
      final before = TableData.parse(table)!..setCell(2, 2, 'hello world');
      final after = TableData.parse(table)!..setCell(2, 2, 'hello big world');
      expect(TableData.firstChange(before.toMarkdown(), after.toMarkdown()), (2, 2, 10), reason: 'after "big "');
      expect(TableData.firstChange(after.toMarkdown(), before.toMarkdown()), (2, 2, 6), reason: 'where "big " was');
    });

    test('a row or column added or removed gives a cell next to it', () {
      final rowAbove = TableData.parse(table)!..insertRow(1);
      expect(TableData.firstChange(table, rowAbove.toMarkdown()), (1, 0, 0), reason: 'redo: the new row');
      expect(TableData.firstChange(rowAbove.toMarkdown(), table), (1, 0, 1), reason: 'undo: the row back in its place');
      final rowAtEnd = TableData.parse(table)!..insertRow(3);
      expect(TableData.firstChange(rowAtEnd.toMarkdown(), table), (2, 0, 0), reason: 'undo: the last row left');
      final column = TableData.parse(table)!..insertColumn(3);
      expect(TableData.firstChange(column.toMarkdown(), table), (0, 2, 0));
    });

    test('a change of widths alone has no cell', () {
      final wide = TableData.parse(table)!..widths = [200, 100, 100];
      expect(TableData.firstChange(table, wide.toMarkdown()), isNull);
    });
  });

  group('undo and redo in a table', () {
    late Directory dir;
    late PageEditorController editor;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('table_undo_');
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

    String tableText() => editor.document[1].text;
    Finder cell(int row, int column) => find.byKey(ValueKey('cell-${editor.document[1].id}-$row-$column'));
    TableBlockViewState grid(WidgetTester tester) => tester.state(find.byType(TableBlockView));
    TextEditingController text(WidgetTester tester, int row, int column) => grid(tester).controllerAt(row, column);
    bool focused(WidgetTester tester, int row, int column) => grid(tester).focusNodeAt(row, column).hasFocus;
    Finder field(int row, int column) => find.descendant(of: cell(row, column), matching: find.byType(TextField));

    /// Which cell has the caret, or null.
    (int, int)? focusedCell(WidgetTester tester) {
      final data = TableData.parse(tableText())!;
      for (var r = 0; r < data.rowCount; r++) {
        for (var c = 0; c < data.columns; c++) {
          if (focused(tester, r, c)) return (r, c);
        }
      }
      return null;
    }

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

    const table = '# T\n\n| Name | Count | Note |\n| --- | --- | --- |\n| a | 1 | x |\n| b | 2 | y |\n| c | 3 | z |\n\n'
        'After\n';

    testWidgets('Ctrl+Z keeps the caret in the cell that was typed in, and Ctrl+Y too', (tester) async {
      await pumpEditor(tester, table);
      final original = tableText();
      await tapCell(tester, 1, 1);
      await tester.enterText(field(1, 1), '1 and a much longer value');
      await tester.pump();
      await tester.pump();
      final typed = tableText();
      expect(typed, isNot(original));

      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      await tester.pump();
      expect(tableText(), original);
      expect(focusedCell(tester), (1, 1), reason: 'not the last cell (3, 2)');
      expect(text(tester, 1, 1).text, '1');
      expect(text(tester, 1, 1).selection, const TextSelection.collapsed(offset: 1));

      await key(tester, LogicalKeyboardKey.keyY, control: true);
      await tester.pump();
      expect(tableText(), typed);
      expect(focusedCell(tester), (1, 1));
      expect(text(tester, 1, 1).selection, const TextSelection.collapsed(offset: 25));

      await key(tester, LogicalKeyboardKey.keyZ, control: true, shift: true);
      await tester.pump();
      expect(tableText(), typed, reason: 'nothing left to redo');
      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      await tester.pump();
      expect(focusedCell(tester), (1, 1));
      await settle(tester);
    });

    testWidgets('undoing edits in two cells walks the caret back through them', (tester) async {
      await pumpEditor(tester, table);
      await tapCell(tester, 2, 0);
      await tester.enterText(field(2, 0), 'b changed');
      await tester.pump();
      // Typing more than a second later is a new undo step (the clock is real).
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1100)));
      await tapCell(tester, 0, 2);
      await tester.enterText(field(0, 2), 'Notes');
      await tester.pump();
      await tester.pump();

      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      await tester.pump();
      expect(focusedCell(tester), (0, 2));
      expect(text(tester, 0, 2).text, 'Note');
      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      await tester.pump();
      expect(focusedCell(tester), (2, 0));
      expect(text(tester, 2, 0).text, 'b');
      await key(tester, LogicalKeyboardKey.keyY, control: true);
      await tester.pump();
      expect(focusedCell(tester), (2, 0));
      expect(text(tester, 2, 0).text, 'b changed');
      await settle(tester);
    });

    testWidgets('Edit > Undo and Redo put the caret in the changed cell too', (tester) async {
      await pumpEditor(tester, table);
      await tapCell(tester, 2, 2);
      await tester.enterText(field(2, 2), 'y2');
      await tester.pump();
      await tester.pump();
      editor.undo();
      await tester.pump();
      await tester.pump();
      expect(focusedCell(tester), (2, 2));
      expect(text(tester, 2, 2).text, 'y');
      editor.redo();
      await tester.pump();
      await tester.pump();
      expect(focusedCell(tester), (2, 2));
      expect(text(tester, 2, 2).text, 'y2');
      await settle(tester);
    });

    testWidgets('undoing an inserted row puts the caret where the row was', (tester) async {
      await pumpEditor(tester, table);
      await tester.tap(cell(2, 1), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insert row above').last);
      await tester.pumpAndSettle();
      expect(TableData.parse(tableText())!.rowCount, 5);

      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      await tester.pump();
      expect(TableData.parse(tableText())!.rowCount, 4);
      expect(focusedCell(tester), (2, 0));
      await key(tester, LogicalKeyboardKey.keyY, control: true);
      await tester.pump();
      expect(TableData.parse(tableText())!.rowCount, 5);
      expect(focusedCell(tester), (2, 0), reason: 'the new, empty row');
      await settle(tester);
    });

    testWidgets('Ctrl+Z from the paragraph below goes back to the changed cell', (tester) async {
      await pumpEditor(tester, table);
      await tapCell(tester, 1, 0);
      await tester.enterText(field(1, 0), 'a2');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('After'));
      await tester.pump();
      await tester.pump();
      expect(focusedCell(tester), isNull);

      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      await tester.pump();
      expect(focusedCell(tester), (1, 0));
      expect(text(tester, 1, 0).text, 'a');
      await settle(tester);
    });
  });
}
