import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/editor/block_range.dart';
import 'package:stack_space/editor/blocks.dart';
import 'package:stack_space/editor/page_document.dart';
import 'package:stack_space/editor/page_editor_controller.dart';
import 'package:stack_space/ui/editor/block_editor.dart';
import 'package:stack_space/workspace/workspace.dart';
import 'support/temp.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1)); // autosave timer
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

PageDocument docOf(String markdown) => PageDocument()..load(markdown);

void main() {
  group('range edits', () {
    const page = '# Title\n\n- one\n- two\n- three\n\nLast line.\n';

    test('the selected part of each block, as Markdown', () {
      final doc = docOf(page);
      // From "ne" in "one" to "thr" in "three".
      final range = BlockRange((block: 1, offset: 1), (block: 3, offset: 3));
      expect(rangeMarkdown(doc.blocks, range), '- ne\n- two\n- thr');
      // Backwards gives the same text.
      expect(rangeMarkdown(doc.blocks, BlockRange(range.focus, range.anchor)), '- ne\n- two\n- thr');
      expect(rangeMarkdown(doc.blocks, BlockRange((block: 0, offset: 2), (block: 4, offset: 4))),
          '# tle\n\n- one\n- two\n- three\n\nLast');
    });

    test('deleting joins the text around the selection in one undo step', () {
      final doc = docOf(page);
      final caret = deleteRange(doc, BlockRange((block: 3, offset: 3), (block: 1, offset: 1)));
      expect(caret, (block: 1, offset: 1));
      expect(doc.toMarkdown(), '# Title\n\n- oee\n\nLast line.\n');
      doc.undo();
      expect(doc.toMarkdown(), page);
    });

    test('typing over a selection replaces it', () {
      final doc = docOf(page);
      final caret = deleteRange(doc, BlockRange((block: 0, offset: 2), (block: 4, offset: 4)), insert: 'X');
      expect(caret, (block: 0, offset: 3));
      expect(doc.toMarkdown(), '# TiX line.\n');
    });

    test('a selection that ends on a code block removes it whole', () {
      final doc = docOf('One\n\n```\ncode\n```\n\nTwo\n');
      deleteRange(doc, BlockRange((block: 0, offset: 1), (block: 1, offset: 0)));
      expect(doc.toMarkdown(), 'O\n\nTwo\n');
    });

    test('bold goes on every selected line, and comes off again', () {
      final doc = docOf(page);
      var range = BlockRange((block: 1, offset: 0), (block: 3, offset: 5));
      range = formatRange(doc, range, '**');
      expect(doc.toMarkdown(), '# Title\n\n- **one**\n- **two**\n- **three**\n\nLast line.\n');
      expect(range.start, (block: 1, offset: 0));
      expect(range.end, (block: 3, offset: 9));
      formatRange(doc, range, '**');
      expect(doc.toMarkdown(), page);
    });

    test('a partly bold selection is made bold everywhere, not doubled', () {
      final doc = docOf('- **one**\n- two\n');
      formatRange(doc, BlockRange((block: 0, offset: 0), (block: 1, offset: 3)), '**');
      expect(doc.toMarkdown(), '- **one**\n- **two**\n');
    });

    test('turning lines into a list keeps their text; into code joins them', () {
      final doc = docOf('One\n\nTwo\n\nThree\n');
      final range = BlockRange((block: 0, offset: 1), (block: 2, offset: 2));
      expect(convertRange(doc, range, BlockKind.bullet, 0), isNull);
      expect(doc.toMarkdown(), '- One\n- Two\n- Three\n');
      final caret = convertRange(doc, range, BlockKind.code, 0);
      expect(caret, (block: 0, offset: 13));
      expect(doc.toMarkdown(), '```\nOne\nTwo\nThree\n```\n');
    });

    test('Tab indents every list item in the selection', () {
      final doc = docOf('- one\n- two\n- three\n');
      indentRange(doc, BlockRange((block: 1, offset: 0), (block: 2, offset: 1)), 1);
      expect(doc.toMarkdown(), '- one\n  - two\n  - three\n');
    });

    test('pasting copied blocks puts them back as blocks', () {
      final doc = docOf('Start end\n');
      final caret = pasteBlocks(doc, 0, 'Start ', 'end', '- one\n- two\n\n## three');
      expect(doc.toMarkdown(), 'Start one\n\n- two\n\n## threeend\n');
      expect(caret, (block: 2, offset: 5));
      expect(pasteBlocks(doc, 0, '', '', 'just one line'), isNull);
    });
  });

  group('in the editor', () {
    late Directory dir;
    late PageEditorController editor;
    String? clipboard;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('block_range_');
      final workspace = Workspace(dir.path);
      await workspace.init();
      editor = PageEditorController(workspace);
      clipboard = null;
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
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
        if (call.method == 'Clipboard.getData') return {'text': clipboard};
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: BlockEditor(controller: editor, readOnly: false))));
      await tester.pump();
    }

    BlockRange? rangeOf(WidgetTester tester) =>
        (tester.state(find.byType(BlockEditor)) as dynamic).range as BlockRange?;

    RenderEditable editableOf(WidgetTester tester, int field) =>
        tester.state<EditableTextState>(find.byType(EditableText).at(field)).renderEditable;

    /// Where character [offset] of text field [field] is on screen.
    Offset charAt(WidgetTester tester, int field, int offset) {
      final editable = editableOf(tester, field);
      return editable.localToGlobal(editable.getLocalRectForCaret(TextPosition(offset: offset)).centerLeft);
    }

    Future<void> drag(WidgetTester tester, Offset from, List<Offset> through) async {
      final gesture = await tester.startGesture(from, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
      await tester.pump();
      for (final to in through) {
        await gesture.moveTo(to);
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // past a double-click
    }

    Future<void> key(WidgetTester tester, LogicalKeyboardKey k,
        {bool shift = false, bool control = false, String? character}) async {
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(k, character: character);
      if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.pump();
    }

    String saved() => File('${dir.path}/page.md').readAsStringSync();

    /// A test on Windows; the platform override has to be gone before the
    /// test ends.
    void testEditor(String description, Future<void> Function(WidgetTester tester) body) {
      testWidgets(description, (tester) async {
        try {
          await body(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    Future<void> click(WidgetTester tester, Offset at) async {
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 500));
    }

    const page = 'First line here.\n\n- Step one\n- Step two\n- Step three\n\nLast line.\n';

    testEditor('dragging across lines selects them all, and Ctrl+C copies them', (tester) async {
      await pumpEditor(tester, page);
      // From "line" in the first paragraph to "two" in the second item.
      await drag(tester, charAt(tester, 0, 6), [charAt(tester, 1, 4), charAt(tester, 2, 8)]);
      expect(rangeOf(tester), BlockRange((block: 0, offset: 6), (block: 2, offset: 8)));
      // The toolbar is up for the selection, without the link button.
      expect(find.byTooltip('Bold (Ctrl+B)'), findsOneWidget);
      expect(find.byTooltip('Link (Ctrl+K); Ctrl+click opens'), findsNothing);
      await key(tester, LogicalKeyboardKey.keyC, control: true);
      expect(clipboard, 'line here.\n\n- Step one\n- Step two');
      expect(rangeOf(tester), isNotNull);
    });

    testEditor('a drag back into the line it started in is an ordinary selection again', (tester) async {
      await pumpEditor(tester, page);
      final gesture =
          await tester.startGesture(charAt(tester, 0, 2), kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
      await tester.pump();
      await gesture.moveTo(charAt(tester, 2, 3));
      await tester.pump();
      expect(rangeOf(tester), isNotNull);
      await gesture.moveTo(charAt(tester, 0, 9));
      await tester.pump();
      expect(rangeOf(tester), isNull);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      final sel = tester.widget<TextField>(find.byType(TextField).first).controller!.selection;
      expect((sel.start, sel.end), (2, 9));
    });

    testEditor('Backspace deletes the selection and the lines join', (tester) async {
      await pumpEditor(tester, page);
      await drag(tester, charAt(tester, 1, 5), [charAt(tester, 3, 5)]);
      await key(tester, LogicalKeyboardKey.backspace);
      expect(rangeOf(tester), isNull);
      expect(editor.document.toMarkdown(), 'First line here.\n\n- Step three\n\nLast line.\n');
      await settle(tester);
      await waitSaved(tester, editor);
      expect(saved(), 'First line here.\n\n- Step three\n\nLast line.\n');
      // One undo brings every line back.
      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(editor.document.toMarkdown(), page);
      await settle(tester);
    });

    testEditor('typing replaces the selection', (tester) async {
      await pumpEditor(tester, page);
      await drag(tester, charAt(tester, 0, 6), [charAt(tester, 4, 4)]);
      await key(tester, LogicalKeyboardKey.keyX, character: 'x');
      expect(editor.document.toMarkdown(), 'First x line.\n');
      final field = tester.widget<TextField>(find.byType(TextField).first).controller!;
      expect(field.text, 'First x line.');
      expect(field.selection, const TextSelection.collapsed(offset: 7));
      await settle(tester);
    });

    testEditor('Ctrl+B makes every selected line bold', (tester) async {
      await pumpEditor(tester, page);
      await drag(tester, charAt(tester, 1, 0), [charAt(tester, 3, 10)]);
      await key(tester, LogicalKeyboardKey.keyB, control: true);
      expect(editor.document.toMarkdown(),
          'First line here.\n\n- **Step one**\n- **Step two**\n- **Step three**\n\nLast line.\n');
      // Still selected, so a second Ctrl+B takes it off again.
      expect(rangeOf(tester), isNotNull);
      await key(tester, LogicalKeyboardKey.keyB, control: true);
      expect(editor.document.toMarkdown(), page);
      await settle(tester);
    });

    testEditor('Ctrl+X cuts, and pasting brings the lines back as blocks', (tester) async {
      await pumpEditor(tester, page);
      await drag(tester, charAt(tester, 1, 0), [charAt(tester, 2, 8)]);
      await key(tester, LogicalKeyboardKey.keyX, control: true);
      expect(clipboard, '- Step one\n- Step two');
      expect(editor.document.toMarkdown(), 'First line here.\n\n- \n- Step three\n\nLast line.\n');
      // Paste at the end of the last line, as the platform does: the text
      // arrives in the field with the caret after it.
      await click(tester, charAt(tester, 3, 10));
      final last = tester.widget<TextField>(find.byType(TextField).last).controller!;
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: 'Last line.$clipboard',
        selection: TextSelection.collapsed(offset: 'Last line.'.length + clipboard!.length),
      ));
      await tester.pump();
      await tester.pump();
      expect(
          editor.document.toMarkdown(), 'First line here.\n\n- \n- Step three\n\nLast line.Step one\n\n- Step two\n');
      expect(last.text, 'Last line.Step one');
      await settle(tester);
    });

    testEditor('Shift+Down on the last line of a block selects into the next', (tester) async {
      await pumpEditor(tester, page);
      await click(tester, charAt(tester, 1, 5));
      await key(tester, LogicalKeyboardKey.arrowDown, shift: true);
      final range = rangeOf(tester)!;
      expect(range.anchor, (block: 1, offset: 5));
      expect(range.focus.block, 2);
      await key(tester, LogicalKeyboardKey.arrowDown, shift: true);
      expect(rangeOf(tester)!.focus.block, 3);
      await key(tester, LogicalKeyboardKey.arrowUp, shift: true);
      await key(tester, LogicalKeyboardKey.arrowUp, shift: true);
      // Back where it started: just the caret.
      expect(rangeOf(tester), isNull);
      // An arrow without Shift ends a range at its end.
      await key(tester, LogicalKeyboardKey.arrowRight, shift: true);
      await key(tester, LogicalKeyboardKey.arrowDown, shift: true);
      expect(rangeOf(tester), isNotNull);
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(rangeOf(tester), isNull);
    });

    testEditor('Shift+click in another line selects from the caret', (tester) async {
      await pumpEditor(tester, page);
      await click(tester, charAt(tester, 0, 6));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final gesture =
          await tester.startGesture(charAt(tester, 3, 4), kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
      await gesture.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump(const Duration(milliseconds: 500));
      expect(rangeOf(tester), BlockRange((block: 0, offset: 6), (block: 3, offset: 4)));
      // A plain click ends it.
      await click(tester, charAt(tester, 4, 2));
      expect(rangeOf(tester), isNull);
    });

    testEditor('Ctrl+A twice selects the whole page', (tester) async {
      await pumpEditor(tester, page);
      await click(tester, charAt(tester, 2, 2));
      await key(tester, LogicalKeyboardKey.keyA, control: true);
      expect(rangeOf(tester), isNull); // the line first
      await key(tester, LogicalKeyboardKey.keyA, control: true);
      expect(rangeOf(tester), BlockRange((block: 0, offset: 0), (block: 4, offset: 10)));
      await key(tester, LogicalKeyboardKey.keyC, control: true);
      expect(clipboard, page.trimRight());
    });

    testEditor('a typed edit elsewhere ends the selection', (tester) async {
      await pumpEditor(tester, page);
      await drag(tester, charAt(tester, 0, 6), [charAt(tester, 2, 4)]);
      expect(rangeOf(tester), isNotNull);
      editor.document.updateText(4, 'Changed.');
      await tester.pump();
      expect(rangeOf(tester), isNull);
      await settle(tester);
    });
  });
}
