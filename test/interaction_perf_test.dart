import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stack_space/ai/chat_controller.dart';
import 'package:stack_space/ai/ollama_client.dart';
import 'package:stack_space/app/settings.dart';
import 'package:stack_space/editor/blocks.dart';
import 'package:stack_space/editor/page_editor_controller.dart';
import 'package:stack_space/ui/editor/block_editor.dart';
import 'package:stack_space/ui/editor/table_block.dart';
import 'package:stack_space/ui/home_page.dart';

import 'support/fake_ollama.dart';
import 'support/temp.dart';

/// Timings for the things that are done most: switching pages, clicking
/// and moving around a table, typing in a cell, moving the mouse over a
/// table. They run in the test VM (JIT, debug), so they are upper bounds
/// for the release build; the asserts only catch a large regression. The
/// numbers are printed for PROJECT_STATUS.md.
String notesPage(String name, {int sections = 40, int tableRows = 30}) {
  final b = StringBuffer('# $name\n\nIntro paragraph with **bold** and `code`.\n\n');
  b.write('| Name | Owner | Status | Due | Notes | Tag |\n| --- | --- | --- | --- | --- | --- |\n');
  for (var r = 0; r < tableRows; r++) {
    b.write(
        '| Item $r | Person ${r % 7} | ${r.isEven ? 'Open' : 'Done'} | 2026-11-${(r % 28 + 1).toString().padLeft(2, '0')} '
        '| Some longer note text for row $r that may wrap | t$r |\n');
  }
  b.write('\n');
  for (var s = 0; s < sections; s++) {
    b.write('## Section $s\n\n- item one\n- item two with [a link](https://example.com)\n\n'
        'A paragraph in section $s with *italic* and **bold** words, long enough to wrap once on a normal window.\n\n');
  }
  return '${b.toString().trimRight()}\n';
}

void main() {
  late Directory dir;
  late FakeOllama fake;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('perf_ui_');
    await File('${dir.path}/a.md').writeAsString(notesPage('Page A'));
    await File('${dir.path}/b.md').writeAsString(notesPage('Page B'));
    SharedPreferences.setMockInitialValues({'workspacePath': dir.path});
    fake = FakeOllama();
  });

  tearDown(() => deleteTemp(dir));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  testWidgets('interaction timings', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = await tester.runAsync(AppSettings.load);
    await tester.pumpWidget(MaterialApp(
      home: HomePage(
        settings: settings!,
        chatFactory: (s, tools) => ChatController(
          settings: s,
          tools: tools,
          clientFactory: (url) => OllamaClient(baseUrl: url, httpClient: fake.client()),
        ),
      ),
    ));
    await settle(tester);
    final editor = (tester.state(find.byType(BlockEditor)) as dynamic).widget.controller as PageEditorController;

    final report = <String>[];
    final frame = Stopwatch();
    Future<void> timedPump([Duration? d]) async {
      frame.start();
      await tester.pump(d);
      frame.stop();
    }

    // Page switching: frame work from the click to the new page drawn.
    Future<void> open(String name) async {
      await tester.tap(find.text(name).first);
      await timedPump();
      for (var i = 0; i < 400 && editor.path != name; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
        await timedPump();
      }
      await timedPump();
      expect(editor.path, name);
    }

    await open('a.md');
    await open('b.md'); // warm-up
    frame.reset();
    for (var i = 0; i < 6; i++) {
      await open(i.isEven ? 'a.md' : 'b.md');
    }
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    report.add('page switch: ${(frame.elapsedMicroseconds / 6 / 1000).toStringAsFixed(1)} ms');

    final tableId = editor.document.blocks.firstWhere((b) => b.kind == BlockKind.table).id;
    Finder cell(int r, int c) => find.byKey(ValueKey('cell-$tableId-$r-$c'));

    // Clicking cells.
    await tester.tap(cell(1, 0));
    await timedPump();
    frame.reset();
    for (var i = 0; i < 12; i++) {
      final target = cell(1 + i % 4, i % 5);
      await tester.tap(target);
      await timedPump();
      await tester.pump(const Duration(milliseconds: 200)); // a scroll into view runs to its end
      await tester.pump(const Duration(milliseconds: 200));
    }
    report.add('click a cell: ${(frame.elapsedMicroseconds / 12 / 1000).toStringAsFixed(1)} ms');

    // Arrow keys and Tab between cells.
    frame.reset();
    for (var i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await timedPump();
    }
    for (var i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await timedPump();
    }
    report.add('arrow / tab to a cell: ${(frame.elapsedMicroseconds / 20 / 1000).toStringAsFixed(1)} ms');

    // Typing in a cell.
    final grid = tester.state<TableBlockViewState>(find.byType(TableBlockView));
    grid.focusCell(3, 1);
    await timedPump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    final field = find.descendant(of: cell(3, 1), matching: find.byType(EditableText));
    frame.reset();
    var text = (tester.widget<EditableText>(field)).controller.text;
    for (var i = 0; i < 15; i++) {
      text += 'x';
      tester.testTextInput
          .updateEditingValue(TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)));
      await timedPump();
    }
    expect(grid.controllerAt(3, 1).text, endsWith('x' * 15), reason: 'the typing went to the cell');
    report.add('type in a cell: ${(frame.elapsedMicroseconds / 15 / 1000).toStringAsFixed(1)} ms');

    // Moving the mouse over the table.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(cell(1, 0)));
    await timedPump();
    frame.reset();
    var moves = 0;
    for (var r = 1; r < 5; r++) {
      for (var c = 0; c < 6; c++) {
        await mouse.moveTo(tester.getCenter(cell(r, c)));
        await timedPump();
        moves++;
      }
    }
    report.add('mouse over a new cell: ${(frame.elapsedMicroseconds / moves / 1000).toStringAsFixed(1)} ms');
    await mouse.removePointer();

    // Typing in a paragraph after the table.
    final para =
        find.byWidgetPredicate((w) => w is EditableText && w.controller.text.startsWith('A paragraph in section 1 '));
    await tester.scrollUntilVisible(para, 300, scrollable: find.byType(Scrollable).at(2));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(para);
    await timedPump();
    await tester.pump(const Duration(milliseconds: 200));
    final paraText = tester.widget<EditableText>(para).controller;
    frame.reset();
    for (var i = 0; i < 15; i++) {
      final t = '${paraText.text}y';
      tester.testTextInput
          .updateEditingValue(TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length)));
      await timedPump();
    }
    expect(paraText.text, endsWith('y' * 15));
    report.add('type in a paragraph: ${(frame.elapsedMicroseconds / 15 / 1000).toStringAsFixed(1)} ms');

    await waitSaved(tester, editor);
    // ignore: avoid_print
    print(report.join('\n'));
    // Before the cells were drawn as text these were about 950 ms and 160 ms
    // here; the bounds leave room for a slow runner.
    for (final line in report) {
      final ms = double.parse(line.split(': ').last.split(' ').first);
      expect(ms, lessThan(line.startsWith('page switch') ? 1500 : 400), reason: line);
    }
    File('${Directory.systemTemp.path}/stackspace_interaction.txt').writeAsStringSync('${report.join('\n')}\n');
  });
}
