import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:stack_space/editor/blocks.dart';
import 'package:stack_space/editor/page_document.dart';
import 'package:stack_space/editor/page_editor_controller.dart';
import 'package:stack_space/ui/editor/block_editor.dart';
import 'package:stack_space/workspace/workspace.dart';

/// Timings for large pages. They run in the test VM (JIT, debug), so the
/// numbers are upper bounds for the release build; the asserts only catch a
/// regression of an order of magnitude. The table is printed for
/// PROJECT_STATUS.md.
///
/// Shapes: one code block of N lines; N one-line paragraphs; a mix of
/// headings, lists, paragraphs and short code blocks adding up to N lines.
String codePage(int lines) =>
    '# Big script\n\n```python\n${List.generate(lines, (i) => 'value_$i = compute($i)  # line $i').join('\n')}\n```\n';

String paragraphPage(int lines) =>
    '${List.generate(lines, (i) => 'Paragraph $i with some **bold** text and `code`.').join('\n\n')}\n';

String mixedPage(int lines) {
  final b = StringBuffer();
  var n = 0;
  var section = 0;
  while (n < lines) {
    b.write('## Section $section\n\n- item one\n- item two\n  - nested\n\nA paragraph in section $section.\n\n');
    b.write('```js\nconst a$section = 1;\nconst b$section = a$section + 1;\nconsole.log(b$section);\n```\n\n');
    n += 13;
    section++;
  }
  return '${b.toString().trimRight()}\n';
}

void main() {
  final rows = <String>[];
  // Rows are also appended to this file as they come, so a run that is cut
  // short still leaves its numbers.
  final log = '${Directory.systemTemp.path}/stackspace_perf_rows.txt';
  void row(String r) {
    rows.add(r);
    File(log).writeAsStringSync('$r\n', mode: FileMode.append);
  }

  void step(String r) => File(log).writeAsStringSync('  $r\n', mode: FileMode.append);

  int ms(void Function() f) {
    final sw = Stopwatch()..start();
    f();
    return sw.elapsedMilliseconds;
  }

  for (final size in [5000, 10000, 50000, 100000]) {
    for (final (shape, page) in [
      ('code', codePage(size)),
      ('paragraphs', paragraphPage(size)),
      ('mixed', mixedPage(size))
    ]) {
      test('model: $shape $size lines', () {
        late List<Block> blocks;
        final parse = ms(() => blocks = parseMarkdown(page));
        late String out;
        final write = ms(() => out = writeMarkdown(blocks));
        expect(out, page);
        final doc = PageDocument();
        final load = ms(() => doc.load(page));
        final edit = ms(() => doc.updateText(doc.length ~/ 2, 'changed'));
        final md = ms(doc.toMarkdown);
        final undo = ms(doc.undo);
        row('| $shape | $size | ${blocks.length} | $parse | $write | $load | $edit | $md | $undo |');
        expect(parse + write + load, lessThan(5000), reason: 'model work on $size lines');
      });
    }
  }

  for (final size in [5000, 10000, 50000]) {
    for (final (shape, page) in [
      ('code', codePage(size)),
      ('paragraphs', paragraphPage(size)),
      ('mixed', mixedPage(size))
    ]) {
      testWidgets('editor: $shape $size lines', (tester) async {
        // File IO must run outside the test's fake time, or it never completes.
        late Directory dir;
        late PageEditorController editor;
        var open = 0;
        await tester.runAsync(() async {
          dir = await Directory.systemTemp.createTemp('perf_');
          final workspace = Workspace(dir.path);
          await workspace.init();
          editor = PageEditorController(workspace);
          await File('${dir.path}/page.md').writeAsString(page);
          final sw = Stopwatch()..start();
          await editor.open('page.md');
          open = sw.elapsedMilliseconds;
        });
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        // The app runs on desktop; the code editor's Android key path is not used.
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        final sw = Stopwatch()..start();
        step('$shape $size: opened in $open ms');
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: BlockEditor(controller: editor, readOnly: false))));
        step('$shape $size: pumpWidget ${sw.elapsedMilliseconds} ms');
        await tester.pump();
        final firstFrame = sw.elapsedMilliseconds;
        step('$shape $size: first frame $firstFrame ms');

        // Type one character into the first editable block.
        sw.reset();
        if (shape == 'code') {
          await tester.tap(find.byType(CodeEditor));
          await tester.pump();
          final c = tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;
          c.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
          c.replaceSelection('#');
          await tester.pump();
        } else {
          await tester.tap(find.byType(TextField).first);
          await tester.pump();
          final field = tester.widget<TextField>(find.byType(TextField).first);
          await tester.enterText(find.byType(TextField).first, '#${field.controller!.text}');
          await tester.pump();
        }
        final type = sw.elapsedMilliseconds;
        step('$shape $size: key $type ms');
        expect(editor.document.toMarkdown().length, page.length + 1, reason: 'the typed character is in the page');

        // Jump to the end and back.
        sw.reset();
        final scrollable = find.byType(Scrollable).first;
        final position = tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        step('$shape $size: jump to end ${sw.elapsedMilliseconds} ms');
        position.jumpTo(0);
        await tester.pump();
        final scroll = sw.elapsedMilliseconds;
        step('$shape $size: scroll $scroll ms');

        sw.reset();
        await tester.pump(const Duration(seconds: 1));
        for (var i = 0; i < 20 && editor.dirty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
        }
        final save = sw.elapsedMilliseconds;
        final saved = File('${dir.path}/page.md').readAsStringSync();
        expect(saved.length, page.length + 1);

        rows.add(
            '| $shape | $size | - | open $open | first frame $firstFrame | key $type | scroll $scroll | save $save | |');
        expect(firstFrame, lessThan(5000));
        expect(type, lessThan(2000), reason: 'one keystroke on $size lines');
        editor.dispose();
        await tester.runAsync(() => dir.delete(recursive: true));
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  tearDownAll(() {
    stdout.writeln('| shape | lines | blocks | parse ms | write ms | load ms | edit ms | toMarkdown ms | undo ms |');
    stdout.writeln('| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
    rows.forEach(stdout.writeln);
  });
}
