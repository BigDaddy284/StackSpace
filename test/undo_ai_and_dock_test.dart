import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stack_space/ai/chat_controller.dart';
import 'package:stack_space/ai/ollama_client.dart';
import 'package:stack_space/app/settings.dart';
import 'package:stack_space/editor/page_editor_controller.dart';
import 'package:stack_space/ui/chat/chat_dock.dart';
import 'package:stack_space/ui/editor/block_editor.dart';
import 'package:stack_space/ui/home_page.dart';
import 'package:stack_space/workspace/workspace.dart';

import 'home_page_test.dart' show settle, settleUntil;
import 'support/fake_ollama.dart';
import 'support/temp.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('undo_ai_');
    await File('${dir.path}/notes.md').writeAsString('# Notes\n\nfirst line\n');
  });

  tearDown(() => deleteTemp(dir));

  test("the assistant's change to the open page is one undo step, and undoing it saves", () async {
    final workspace = Workspace(dir.path);
    await workspace.init();
    final editor = PageEditorController(workspace);
    addTearDown(editor.dispose);
    await editor.open('notes.md');
    expect(editor.canUndo, isFalse);

    await workspace.write('notes.md', '# Notes\n\nchanged by the assistant\n', source: ChangeSource.ai);
    for (var i = 0; i < 50 && editor.document.toMarkdown().contains('first'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(editor.document.toMarkdown(), '# Notes\n\nchanged by the assistant\n');
    expect(editor.dirty, isFalse, reason: 'the file already has it');
    expect(editor.canUndo, isTrue);

    editor.undo();
    expect(editor.document.toMarkdown(), '# Notes\n\nfirst line\n');
    await editor.flush();
    expect(File('${dir.path}/notes.md').readAsStringSync(), '# Notes\n\nfirst line\n');

    editor.redo();
    await editor.flush();
    expect(File('${dir.path}/notes.md').readAsStringSync(), '# Notes\n\nchanged by the assistant\n');
  });

  group('in the app', () {
    late FakeOllama fake;

    setUp(() {
      SharedPreferences.setMockInitialValues({'workspacePath': dir.path});
      fake = FakeOllama();
    });

    Future<void> pumpApp(WidgetTester tester) async {
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
    }

    PageEditorController editorOf(WidgetTester tester) =>
        tester.widget<BlockEditor>(find.byType(BlockEditor)).controller;

    Future<void> editMenu(WidgetTester tester, String item) async {
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, item));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1)); // the autosave
      await settle(tester);
    }

    testWidgets("Edit > Undo and Redo take back the assistant's edit; Undo AI change does it from the menu",
        (tester) async {
      fake
        ..queueToolCall('replace_text', {'path': 'notes.md', 'old_text': 'first line', 'new_text': 'second line'})
        ..queueText('Done.');
      await pumpApp(tester);
      await tester.tap(find.text('notes.md').first);
      await settle(tester);
      final page = File('${dir.path}/notes.md');

      await tester.tap(find.byTooltip('Open the assistant (Ctrl+J)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('composer')), 'change the line');
      await tester.pump();
      await tester.tap(find.byTooltip('Send (Enter)'));
      await settleUntil(tester,
          () => page.readAsStringSync().contains('second line') && find.textContaining('Done.').evaluate().isNotEmpty);
      await settleUntil(tester, () => editorOf(tester).document.toMarkdown().contains('second line'));
      expect(editorOf(tester).document.toMarkdown(), contains('second line'));

      // Edit > Undo, as if the chat's own Undo button was missed.
      await editMenu(tester, 'Undo');
      expect(editorOf(tester).document.toMarkdown(), contains('first line'));
      await settleUntil(tester, () => page.readAsStringSync().contains('first line'));
      expect(page.readAsStringSync(), contains('first line'));

      await editMenu(tester, 'Redo');
      expect(editorOf(tester).document.toMarkdown(), contains('second line'));
      await settleUntil(tester, () => page.readAsStringSync().contains('second line'));

      // Edit > Undo AI change reverts the assistant's last change, on any page.
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Undo AI change: Edited notes.md'), findsOneWidget);
      await tester.tap(find.textContaining('Undo AI change'));
      await tester.pumpAndSettle();
      await settleUntil(
          tester,
          () =>
              page.readAsStringSync().contains('first line') &&
              editorOf(tester).document.toMarkdown().contains('first line'));
      expect(page.readAsStringSync(), contains('first line'));
      expect(editorOf(tester).document.toMarkdown(), contains('first line'), reason: 'the open page shows it');
      expect(find.text('Undone'), findsOneWidget, reason: "the chat's card says so too");

      // Nothing left to undo from the assistant: the item is greyed out.
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      final item = tester.widget<MenuItemButton>(
          find.ancestor(of: find.text('Undo AI change'), matching: find.byType(MenuItemButton)));
      expect(item.onPressed, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });

    testWidgets("the assistant panel's top edge stays under the mouse while it is dragged", (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Open the assistant (Ctrl+J)'));
      await tester.pumpAndSettle();
      final handle = find.byKey(const ValueKey('chat-dock-resize'));
      double top() => tester.getTopLeft(handle).dy;
      double dock() => tester.getSize(find.byType(ChatPanel)).height;
      final startTop = top(), startHeight = dock();

      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      expect(top(), closeTo(startTop - 100, 0.5));
      expect(dock(), closeTo(startHeight + 100, 0.5));

      // Far past the top limit and back: the edge comes back under the pointer.
      await gesture.moveBy(const Offset(0, -2000));
      await tester.pump();
      final highest = top();
      await gesture.moveBy(const Offset(0, 2000));
      await tester.pump();
      expect(top(), closeTo(startTop - 100, 0.5));
      expect(highest, greaterThan(0));
      await gesture.up();
      await tester.pump();
      expect(dock(), closeTo(startHeight + 100, 0.5));
      final prefs = await tester.runAsync(SharedPreferences.getInstance);
      expect(prefs!.getDouble('dockHeight'), closeTo(startHeight + 100, 0.5), reason: 'kept when the drag ends');
    });
  });
}
