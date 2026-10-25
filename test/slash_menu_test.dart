import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/editor/blocks.dart';
import 'package:stack_space/editor/page_editor_controller.dart';
import 'package:stack_space/editor/slash_commands.dart';
import 'package:stack_space/ui/editor/block_editor.dart';
import 'package:stack_space/ui/editor/slash_menu.dart';
import 'package:stack_space/workspace/workspace.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

void main() {
  group('filtering', () {
    test('empty query lists every command in category order', () {
      final all = filterSlashCommands('');
      expect(all.length, slashCommands.length);
      expect(all.first.id, 'text');
      expect(all.map((c) => c.category).toSet(), {'Text', 'Lists', 'Blocks', 'Media'});
    });

    test('label prefix beats alias prefix beats contains', () {
      expect(filterSlashCommands('hea').map((c) => c.id).take(3), ['h1', 'h2', 'h3']);
      expect(filterSlashCommands('h2').first.id, 'h2');
      expect(filterSlashCommands('ul').first.id, 'bullet');
      expect(filterSlashCommands('todo').first.id, 'todo');
      expect(filterSlashCommands('code space').first.id, 'code');
      expect(filterSlashCommands('```').first.id, 'code');
      expect(filterSlashCommands('line').map((c) => c.id), contains('divider'));
      expect(filterSlashCommands('  H1 ').first.id, 'h1');
    });

    test('no match gives an empty list', () {
      expect(filterSlashCommands('zzz'), isEmpty);
    });
  });

  group('in the editor', () {
    late Directory dir;
    late Workspace workspace;
    late PageEditorController editor;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('slash_');
      workspace = Workspace(dir.path);
      await workspace.init();
      editor = PageEditorController(workspace);
    });

    tearDown(() async {
      editor.dispose();
      await dir.delete(recursive: true);
    });

    Future<void> pumpEditor(WidgetTester tester, String markdown,
        {String name = 'page.md',
        Size size = const Size(1000, 800),
        Future<String?> Function(BuildContext)? pickImage}) async {
      await tester.runAsync(() async {
        await File('${dir.path}/$name').writeAsString(markdown);
        await editor.open(name);
      });
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: BlockEditor(controller: editor, readOnly: false, pickImage: pickImage))));
      await tester.pump();
    }

    Future<void> type(WidgetTester tester, Finder field, String text) async {
      await tester.enterText(field, text);
      await tester.pump();
      await tester.pump(); // the menu anchors itself after a frame
    }

    Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
      await tester.sendKeyEvent(k);
      await tester.pump();
      await tester.pump();
    }

    final menu = find.byType(SlashMenuPanel);

    testWidgets('slash opens the menu, typing filters, arrows and Enter apply, query is removed', (tester) async {
      await pumpEditor(tester, '\n');
      final field = find.byType(TextField).first;
      await type(tester, field, '/');
      expect(menu, findsOneWidget);
      expect(find.text('Heading 1'), findsOneWidget);
      expect(find.text('Bulleted list'), findsOneWidget);

      await type(tester, field, '/hea');
      expect(find.text('Heading 1'), findsOneWidget);
      expect(find.text('Bulleted list'), findsNothing);

      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.enter);
      expect(menu, findsNothing);
      expect(editor.document[0].kind, BlockKind.heading);
      expect(editor.document[0].level, 2);
      expect(editor.document[0].text, '');
      expect(tester.widget<TextField>(field).controller!.text, '');
      await settle(tester);
      expect(File('${dir.path}/page.md').readAsStringSync(), '## \n');
    });

    testWidgets('Escape closes and keeps the typed text; Up wraps to the end', (tester) async {
      await pumpEditor(tester, '\n');
      final field = find.byType(TextField).first;
      await type(tester, field, '/');
      await key(tester, LogicalKeyboardKey.arrowUp);
      final panel = tester.widget<SlashMenuPanel>(menu);
      expect(panel.selected, slashCommands.length - 1);
      await key(tester, LogicalKeyboardKey.escape);
      expect(menu, findsNothing);
      expect(editor.document[0].text, '/');
      expect(editor.document[0].kind, BlockKind.paragraph);
      await settle(tester);
    });

    testWidgets('mid-text: the query is removed and the block turns into a quote', (tester) async {
      await pumpEditor(tester, 'Hello\n');
      final field = find.byType(TextField).first;
      await type(tester, field, 'Hello ');
      await type(tester, field, 'Hello /');
      expect(menu, findsOneWidget);
      await type(tester, field, 'Hello /quo');
      await key(tester, LogicalKeyboardKey.enter);
      expect(editor.document[0].kind, BlockKind.quote);
      expect(editor.document[0].text, 'Hello ');
      await settle(tester);
    });

    testWidgets('a slash inside a word, in a code block or in a plain file does not open it', (tester) async {
      await pumpEditor(tester, 'a\n\n```\nx\n```\n');
      final para = find.byType(TextField).at(0);
      await type(tester, para, 'a/');
      expect(menu, findsNothing);
      final code = find.byType(TextField).at(1);
      await type(tester, code, 'x/');
      expect(menu, findsNothing);
      await settle(tester);
    });

    testWidgets('plain files never show the menu', (tester) async {
      await pumpEditor(tester, 'x = 1\n', name: 's.py');
      await type(tester, find.byType(TextField), 'x = 1\n/');
      expect(menu, findsNothing);
      await settle(tester);
    });

    testWidgets('deleting the slash closes the menu; no match shows an empty state and Enter closes it',
        (tester) async {
      await pumpEditor(tester, '\n');
      final field = find.byType(TextField).first;
      await type(tester, field, '/');
      expect(menu, findsOneWidget);
      await type(tester, field, '');
      expect(menu, findsNothing);

      await type(tester, field, '/');
      await type(tester, field, '/zzz');
      expect(find.textContaining('No commands match'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.enter);
      expect(menu, findsNothing);
      expect(editor.document[0].text, '/zzz');
      await settle(tester);
    });

    testWidgets('clicking a command inserts a divider after the text and focuses a new paragraph', (tester) async {
      await pumpEditor(tester, 'Intro\n');
      final field = find.byType(TextField).first;
      await type(tester, field, 'Intro ');
      await type(tester, field, 'Intro /');
      expect(menu, findsOneWidget);
      await type(tester, field, 'Intro /div');
      await tester.tap(find.text('Divider'));
      await tester.pump();
      await tester.pump();
      expect(menu, findsNothing);
      final doc = editor.document;
      expect(doc.length, 3);
      expect(doc[0].text, 'Intro ');
      expect(doc[1].kind, BlockKind.divider);
      expect(doc[2].kind, BlockKind.paragraph);
      expect(tester.binding.focusManager.primaryFocus?.debugLabel, contains('block ${doc[2].id}'));
      await settle(tester);
      expect(File('${dir.path}/page.md').readAsStringSync(), 'Intro \n\n---\n\n\n');
    });

    testWidgets('an empty paragraph is replaced by the inserted block', (tester) async {
      await pumpEditor(tester, '\n');
      final field = find.byType(TextField).first;
      await type(tester, field, '/');
      await type(tester, field, '/table');
      await key(tester, LogicalKeyboardKey.enter);
      final doc = editor.document;
      expect(doc[0].kind, BlockKind.table);
      expect(doc[0].text, startsWith('| Column 1 | Column 2 |'));
      await settle(tester);
    });

    testWidgets('image asks for a path and fills the block', (tester) async {
      await pumpEditor(tester, '\n', pickImage: (_) async => 'pics/cat.png');
      final field = find.byType(TextField).first;
      await type(tester, field, '/');
      await type(tester, field, '/ima');
      await key(tester, LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      final doc = editor.document;
      expect(doc[0].kind, BlockKind.image);
      expect(doc[0].url, 'pics/cat.png');
      expect(doc[0].alt, 'cat.png');
      await settle(tester);
      expect(File('${dir.path}/page.md').readAsStringSync(), '![cat.png](pics/cat.png)\n\n\n');
    });

    testWidgets('the menu opens below the slash and flips above it near the bottom edge', (tester) async {
      await pumpEditor(tester, '${'line\n\n' * 30}\n', size: const Size(900, 500));
      final field = find.byType(TextField).first;
      await type(tester, field, 'line ');
      await type(tester, field, 'line /');
      var panel = tester.widget<SlashMenuPanel>(menu);
      var box = tester.getRect(find.byType(Material).last);
      expect(box.top, greaterThan(panel.anchor.bottom));
      await key(tester, LogicalKeyboardKey.escape);

      // Scroll to the bottom and open it in the last block.
      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();
      final last = find.byType(TextField).last;
      await tester.tap(last);
      await tester.pump();
      await type(tester, last, 'line ');
      await type(tester, last, 'line /');
      panel = tester.widget<SlashMenuPanel>(menu);
      box = tester.getRect(find.byType(Material).last);
      expect(box.bottom, lessThanOrEqualTo(panel.anchor.top));
      expect(box.top, greaterThanOrEqualTo(0));
      await settle(tester);
    });

    testWidgets('the menu closes when the field loses focus', (tester) async {
      await pumpEditor(tester, 'a\n\nb\n');
      await type(tester, find.byType(TextField).at(0), 'a ');
      await type(tester, find.byType(TextField).at(0), 'a /');
      expect(menu, findsOneWidget);
      await tester.tap(find.byType(TextField).at(1));
      await tester.pump();
      expect(menu, findsNothing);
      await settle(tester);
    });
  });
}
