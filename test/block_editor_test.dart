import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:stack_space/editor/blocks.dart';
import 'package:stack_space/editor/page_editor_controller.dart';
import 'package:stack_space/ui/editor/block_editor.dart';
import 'package:stack_space/workspace/workspace.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1)); // autosave timer
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

void main() {
  late Directory dir;
  late Workspace workspace;
  late PageEditorController editor;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('block_editor_');
    workspace = Workspace(dir.path);
    await workspace.init();
    editor = PageEditorController(workspace);
  });

  tearDown(() async {
    editor.dispose();
    await dir.delete(recursive: true);
  });

  Future<void> pumpEditor(WidgetTester tester, String markdown, {String name = 'page.md'}) async {
    // Real file work has to run outside the test's fake async zone.
    await tester.runAsync(() async {
      await File('${dir.path}/$name').writeAsString(markdown);
      await editor.open(name);
    });
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BlockEditor(controller: editor, readOnly: false))));
    await tester.pump();
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

  TextField fieldAt(WidgetTester tester, int i) => tester.widget<TextField>(find.byType(TextField).at(i));

  /// Types Enter the way the platform text input delivers it: as a newline in
  /// the field's text, with the caret after it.
  Future<void> enter(WidgetTester tester, int i) async {
    final c = fieldAt(tester, i).controller!;
    final at = c.selection.isValid ? c.selection.extentOffset : c.text.length;
    tester.testTextInput.updateEditingValue(TextEditingValue(
      text: c.text.replaceRange(at, at, '\n'),
      selection: TextSelection.collapsed(offset: at + 1),
    ));
    await tester.pump();
    await tester.pump();
  }

  String saved(String name) => File('${dir.path}/$name').readAsStringSync();

  testWidgets('typing in a paragraph keeps every character and autosaves', (tester) async {
    await pumpEditor(tester, '# T\n\nEnd.\n');
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    final field = fieldAt(tester, 1);
    field.controller!.selection = const TextSelection.collapsed(offset: 4);
    for (final ch in ' Added text'.split('')) {
      await tester.enterText(find.byType(TextField).at(1), '${field.controller!.text}$ch');
      await tester.pump();
    }
    expect(editor.document[1].text, 'End. Added text');
    expect(fieldAt(tester, 1).controller!.text, 'End. Added text');
    await settle(tester);
    expect(saved('page.md'), '# T\n\nEnd. Added text\n');
  });

  testWidgets('Enter splits, list shortcuts convert, Tab indents, double Enter ends the list', (tester) async {
    await pumpEditor(tester, 'End.\n');
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final doc = editor.document;
    fieldAt(tester, 0).controller!.selection = const TextSelection.collapsed(offset: 4);
    await enter(tester, 0);
    expect(doc.length, 2);
    expect(doc[1].kind, BlockKind.paragraph);
    expect(tester.binding.focusManager.primaryFocus?.debugLabel, contains('block ${doc[1].id}'));

    await tester.enterText(find.byType(TextField).at(1), '- ');
    await tester.pump();
    expect(doc[1].kind, BlockKind.bullet);
    expect(doc[1].text, '');
    await tester.enterText(find.byType(TextField).at(1), 'item one');
    await tester.pump();
    await enter(tester, 1);
    expect(doc[2].kind, BlockKind.bullet);
    await tester.enterText(find.byType(TextField).at(2), 'item two');
    await key(tester, LogicalKeyboardKey.tab);
    expect(doc[2].level, 1);
    await enter(tester, 2);
    expect(doc[3].level, 1);
    await enter(tester, 3); // empty nested item: outdent
    expect(doc[3].level, 0);
    expect(doc[3].kind, BlockKind.bullet);
    await enter(tester, 3); // empty top item: paragraph
    expect(doc[3].kind, BlockKind.paragraph);
    await tester.enterText(find.byType(TextField).at(3), '## ');
    await tester.pump();
    expect(doc[3].kind, BlockKind.heading);
    expect(doc[3].level, 2);
    await tester.enterText(find.byType(TextField).at(3), 'Sub heading');
    await tester.pump();
    await enter(tester, 3);
    await tester.enterText(find.byType(TextField).at(4), '```');
    await tester.pump();
    expect(doc[4].kind, BlockKind.code);
    // The code space is its own editor; Enter inside it is a newline, not a split.
    final code = tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;
    code.replaceSelection('let x = 1;\n');
    await tester.pump();
    expect(doc.length, 5);
    expect(doc[4].text, 'let x = 1;\n');
    // Shift+Enter in a paragraph keeps a soft break.
    await tester.tap(find.byType(TextField).at(0));
    await tester.pump();
    fieldAt(tester, 0).controller!.selection = const TextSelection.collapsed(offset: 4);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await enter(tester, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(doc.length, 5);
    expect(doc[0].text, 'End.\n');
    await settle(tester);
    expect(saved('page.md'), 'End.\n\n\n- item one\n  - item two\n\n## Sub heading\n\n```\nlet x = 1;\n\n```\n');
  });

  testWidgets('Backspace at the start merges or demotes, undo restores', (tester) async {
    await pumpEditor(tester, '# Title\n\n- a\n- b\n');
    await tester.tap(find.byType(TextField).at(2));
    await tester.pump();
    final doc = editor.document;
    fieldAt(tester, 2).controller!.selection = const TextSelection.collapsed(offset: 0);
    await key(tester, LogicalKeyboardKey.backspace);
    expect(doc[2].kind, BlockKind.paragraph);
    await key(tester, LogicalKeyboardKey.backspace);
    expect(doc.length, 2);
    expect(doc[1].text, 'ab');
    expect(tester.binding.focusManager.primaryFocus?.debugLabel, contains('block ${doc[1].id}'));
    await key(tester, LogicalKeyboardKey.keyZ, control: true);
    expect(doc.length, 3);
    expect(doc[2].kind, BlockKind.paragraph);
    await key(tester, LogicalKeyboardKey.keyZ, control: true);
    expect(doc[2].kind, BlockKind.bullet);
    await key(tester, LogicalKeyboardKey.keyY, control: true);
    expect(doc[2].kind, BlockKind.paragraph);
    await settle(tester);
    expect(saved('page.md'), '# Title\n\n- a\n\nb\n');
  });

  testWidgets('a .py file is one code space and Enter inserts a newline', (tester) async {
    await pumpEditor(tester, 'x = 1\n', name: 's.py');
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(CodeEditor), findsOneWidget);
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    final code = tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;
    code.selection = const CodeLineSelection.collapsed(index: 0, offset: 5);
    code.replaceSelection('\ny = 2');
    await tester.pump();
    expect(editor.document.length, 1);
    await settle(tester);
    expect(saved('s.py'), 'x = 1\ny = 2\n');
  });

  testWidgets('a late platform update based on the old text is moved onto the new text', (tester) async {
    await pumpEditor(tester, 'End.\n');
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final doc = editor.document;
    // "- " turns the paragraph into a bullet and clears the field...
    await tester.enterText(find.byType(TextField), '- ');
    await tester.pump();
    expect(doc[0].kind, BlockKind.bullet);
    // ...but the platform had already appended a character to "- ".
    tester.testTextInput
        .updateEditingValue(const TextEditingValue(text: '- i', selection: TextSelection.collapsed(offset: 3)));
    await tester.pump();
    expect(doc[0].text, 'i');
    expect(fieldAt(tester, 0).controller!.text, 'i');
    expect(fieldAt(tester, 0).controller!.selection.extentOffset, 1);
    // Later updates built on the new text pass through unchanged.
    tester.testTextInput
        .updateEditingValue(const TextEditingValue(text: 'it', selection: TextSelection.collapsed(offset: 2)));
    await tester.pump();
    expect(doc[0].text, 'it');

    // The same after Enter: a character typed before the split landed.
    fieldAt(tester, 0).controller!.selection = const TextSelection.collapsed(offset: 2);
    await enter(tester, 0);
    expect(doc.length, 2);
    tester.testTextInput
        .updateEditingValue(const TextEditingValue(text: 'it\nx', selection: TextSelection.collapsed(offset: 4)));
    await tester.pump();
    expect(doc[0].text, 'it');
    expect(doc[1].text, 'x');
    expect(fieldAt(tester, 1).controller!.text, 'x');
    await settle(tester);
  });

  testWidgets('turning a paragraph into a heading or list keeps the same text field', (tester) async {
    await pumpEditor(tester, 'x\n');
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final before = tester.state(find.byType(EditableText));
    for (final shortcut in ['## ', '- ', '> ', '1. ']) {
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      if (editor.document[0].kind != BlockKind.paragraph) {
        editor.document.convert(0, BlockKind.paragraph);
        await tester.pump();
      }
      await tester.enterText(find.byType(TextField), shortcut);
      await tester.pump();
      expect(editor.document[0].kind, isNot(BlockKind.paragraph), reason: shortcut);
      expect(tester.state(find.byType(EditableText)), same(before), reason: shortcut);
    }
    await settle(tester);
  });
}
