import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:stack_space/editor/blocks.dart';
import 'package:stack_space/editor/page_editor_controller.dart';
import 'package:stack_space/ui/editor/block_editor.dart';
import 'package:stack_space/ui/editor/code_block.dart';
import 'package:stack_space/workspace/workspace.dart';

Future<void> settle(WidgetTester tester) async {
  // Language detection (500ms) restarts the 600ms autosave timer, so wait for both.
  await tester.pump(const Duration(seconds: 2));
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  // Every test ends here; the binding checks this is back to normal.
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  late Directory dir;
  late Workspace workspace;
  late PageEditorController editor;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('code_block_');
    workspace = Workspace(dir.path);
    await workspace.init();
    editor = PageEditorController(workspace);
  });

  tearDown(() async {
    editor.dispose();
    await dir.delete(recursive: true);
  });

  Future<void> pumpEditor(WidgetTester tester, String markdown, {String name = 'page.md'}) async {
    await tester.runAsync(() async {
      await File('${dir.path}/$name').writeAsString(markdown);
      await editor.open(name);
    });
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The code editor binds keys per platform; the app runs on desktop.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BlockEditor(controller: editor, readOnly: false))));
    await tester.pump();
  }

  CodeLineEditingController codeController(WidgetTester tester, [int i = 0]) =>
      tester.widget<CodeEditor>(find.byType(CodeEditor).at(i)).controller!;

  String saved(String name) => File('${dir.path}/$name').readAsStringSync();

  /// Types into the code editor the way the platform does: through its text
  /// input client, replacing the selection.
  Future<void> typeCode(WidgetTester tester, String text, {int i = 0}) async {
    final c = codeController(tester, i);
    c.replaceSelection(text);
    await tester.pump();
  }

  testWidgets('a code block shows its language, keeps the text exact and saves the fence', (tester) async {
    const code = 'def f(x):\n\treturn "tab\\there"  # ünïcödé ✓\n\n\n# not a heading\n- not a list';
    await pumpEditor(tester, '# T\n\n```python\n$code\n```\n');
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(find.text('Python'), findsOneWidget);
    expect(codeController(tester).text, code);
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    final c = codeController(tester);
    c.selection = CodeLineSelection.collapsed(index: c.codeLines.length - 1, offset: c.codeLines.last.text.length);
    await typeCode(tester, '\nprint(f(1))');
    expect(editor.document[1].text, '$code\nprint(f(1))');
    await settle(tester);
    expect(saved('page.md'), '# T\n\n```python\n$code\nprint(f(1))\n```\n');
  });

  testWidgets('the language is guessed for typed code and written to the fence; a pick overrides it', (tester) async {
    await pumpEditor(tester, '```\n\n```\n');
    expect(find.text('Plain text'), findsOneWidget);
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    await typeCode(tester, 'using UnityEngine;\n\npublic class Player : MonoBehaviour {\n    void Update() {}\n}');
    await tester.pump(const Duration(milliseconds: 600));
    expect(editor.document[0].language, 'csharp');
    expect(find.text('C#'), findsOneWidget);
    expect(find.text('auto'), findsOneWidget);
    await settle(tester);
    expect(saved('page.md'), startsWith('```csharp\n'));

    // Choosing a language by hand stops the guessing.
    await tester.tap(find.byTooltip('Change language'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('language-search')), 'power');
    await tester.pumpAndSettle();
    await tester.tap(find.text('PowerShell'));
    await tester.pumpAndSettle();
    expect(editor.document[0].language, 'powershell');
    expect(find.text('auto'), findsNothing);
    await typeCode(tester, '\nimport os\nimport sys\ndef g():\n    pass\n');
    await tester.pump(const Duration(milliseconds: 600));
    expect(editor.document[0].language, 'powershell');

    // Back to auto-detect: guessed again from the whole text.
    await tester.tap(find.byTooltip('Change language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto-detect'));
    await tester.pumpAndSettle();
    expect(editor.document[0].language, isNotNull);
    expect(find.text('auto'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('a fence language from the file is kept and never re-guessed', (tester) async {
    await pumpEditor(tester, '```sql\nSELECT 1;\n```\n');
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    await typeCode(tester, 'def f():\n    pass\n');
    await tester.pump(const Duration(milliseconds: 600));
    expect(editor.document[0].language, 'sql');
    await settle(tester);
  });

  testWidgets('copy puts the exact code on the clipboard', (tester) async {
    const code = 'line 1\n\tline 2 ✓\n';
    await pumpEditor(tester, '```\n$code```\n');
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await tester.tap(find.byTooltip('Copy code'));
    await tester.pump();
    expect(copied, code.substring(0, code.length - 1));
    expect(find.bySemanticsLabel('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);
  });

  testWidgets('wrap toggle changes the editor and the block height', (tester) async {
    final long = 'x' * 400;
    await pumpEditor(tester, '```\n$long\n```\n');
    expect(tester.widget<CodeEditor>(find.byType(CodeEditor)).wordWrap, isFalse);
    final before = tester.getSize(find.byType(CodeEditor)).height;
    await tester.tap(find.byTooltip('Wrap lines: off'));
    await tester.pump();
    expect(tester.widget<CodeEditor>(find.byType(CodeEditor)).wordWrap, isTrue);
    expect(tester.getSize(find.byType(CodeEditor)).height, greaterThan(before));
    await settle(tester);
  });

  testWidgets('caption is saved on the fence line and read back', (tester) async {
    await pumpEditor(tester, '```js\nlet a = 1;\n```\n');
    expect(find.text('Caption'), findsNothing);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add caption'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Caption'), 'Counter setup');
    await tester.pump();
    expect(editor.document[0].caption, 'Counter setup');
    await settle(tester);
    expect(saved('page.md'), '```js Counter setup\nlet a = 1;\n```\n');
    expect(parseMarkdown(saved('page.md'))[0].caption, 'Counter setup');
  });

  testWidgets('undo and redo work across a code edit', (tester) async {
    await pumpEditor(tester, '```\na\n```\n');
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    final c = codeController(tester);
    c.selection = const CodeLineSelection.collapsed(index: 0, offset: 1);
    await typeCode(tester, 'b');
    expect(editor.document[0].text, 'ab');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(editor.document[0].text, 'a');
    expect(codeController(tester).text, 'a');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(editor.document[0].text, 'ab');
    await settle(tester);
  });

  testWidgets('Backspace in an empty code block turns it back into a paragraph; Ctrl+Enter adds one below',
      (tester) async {
    await pumpEditor(tester, '```\n\n```\n');
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    expect(editor.document.length, 2);
    expect(editor.document[1].kind, BlockKind.paragraph);
    expect(tester.binding.focusManager.primaryFocus?.debugLabel, contains('block ${editor.document[1].id}'));

    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(editor.document[0].kind, BlockKind.paragraph);
    expect(find.byType(CodeEditor), findsNothing);
    await settle(tester);
  });

  testWidgets('the slash menu and markdown shortcuts never fire inside code', (tester) async {
    await pumpEditor(tester, '```\n\n```\n');
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    await typeCode(tester, '/head\n- item\n# title');
    await tester.pump();
    expect(editor.document.length, 1);
    expect(editor.document[0].kind, BlockKind.code);
    expect(editor.document[0].text, '/head\n- item\n# title');
    await settle(tester);
  });

  testWidgets('a script file opens as one highlighted code space with its language from the extension', (tester) async {
    await pumpEditor(tester, 'x = 1\n', name: 's.py');
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(find.text('Python'), findsOneWidget);
    expect(find.text('Add caption'), findsNothing);
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    final c = codeController(tester);
    c.selection = const CodeLineSelection.collapsed(index: 0, offset: 5);
    await typeCode(tester, '\ny = 2');
    await settle(tester);
    expect(saved('s.py'), 'x = 1\ny = 2\n');
  });

  testWidgets('a large pasted script keeps every line', (tester) async {
    final script = List.generate(5000, (i) => 'line $i: value = ${i * 3}').join('\n');
    await pumpEditor(tester, '```\n\n```\n');
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    await typeCode(tester, script);
    expect(editor.document[0].text, script);
    expect(tester.getSize(find.byType(CodeEditor)).height, lessThanOrEqualTo(CodeBlockView.maxBodyHeight));
    await settle(tester);
    expect(editor.document[0].text, script);
    expect(codeController(tester).text, script);
    // The guessed language goes on the fence; every line is kept.
    expect(saved('page.md'), endsWith('\n$script\n```\n'));
  });
}
