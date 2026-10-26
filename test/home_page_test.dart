import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stack_space/ai/chat_controller.dart';
import 'package:stack_space/ai/ollama_client.dart';
import 'package:stack_space/app/settings.dart';
import 'package:stack_space/ui/home_page.dart';
import 'package:stack_space/ui/sidebar.dart';

import 'support/fake_ollama.dart';
import 'support/temp.dart';

/// Lets real file and fake-network work finish between frames.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

void main() {
  late Directory dir;
  late FakeOllama fake;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('home_test_');
    await File('${dir.path}/hello.py').writeAsString('def greet():\n    print("hi")\n');
    SharedPreferences.setMockInitialValues({'workspacePath': dir.path});
    fake = FakeOllama();
  });

  tearDown(() => deleteTemp(dir));

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
    // Let the workspace load from disk and the chat connect.
    await settle(tester);
  }

  testWidgets('the sidebar hides pictures and folders that hold only pictures', (tester) async {
    await tester.runAsync(() async {
      await File('${dir.path}/cover.png').writeAsBytes([1, 2, 3]);
      await Directory('${dir.path}/images').create();
      await File('${dir.path}/images/shot.jpg').writeAsBytes([1]);
      await Directory('${dir.path}/docs').create();
      await File('${dir.path}/docs/pic.gif').writeAsBytes([1]);
      await File('${dir.path}/docs/readme.md').writeAsString('# R\n');
    });
    await pumpApp(tester);
    expect(find.text('hello.py'), findsWidgets);
    expect(find.text('readme.md'), findsOneWidget);
    expect(find.text('docs'), findsOneWidget, reason: 'a folder with a page shows');
    expect(find.text('cover.png'), findsNothing);
    expect(find.text('shot.jpg'), findsNothing);
    expect(find.text('pic.gif'), findsNothing);
    expect(find.text('images'), findsNothing, reason: 'a folder of pictures only is hidden');
  });

  testWidgets('folder fold state survives hiding the panel, renames, deletes and a restart', (tester) async {
    // Bug 3: the folded set lived in the panel's widget state, which is lost
    // whenever the panel is hidden (it is unmounted) and on every restart.
    await tester.runAsync(() async {
      await File('${dir.path}/alpha/one.md').create(recursive: true);
      await File('${dir.path}/alpha/inner/deep.md').create(recursive: true);
      await File('${dir.path}/beta/two.md').create(recursive: true);
      await File('${dir.path}/gamma/three.md').create(recursive: true);
    });
    await pumpApp(tester);
    expect(find.text('one.md'), findsOneWidget);
    expect(find.text('deep.md'), findsOneWidget);
    expect(find.text('two.md'), findsOneWidget);

    // Fold alpha and gamma, leave beta open.
    await tester.tap(find.text('alpha'));
    await tester.pump();
    await tester.tap(find.text('gamma'));
    await tester.pump();
    expect(find.text('one.md'), findsNothing);
    expect(find.text('inner'), findsNothing);
    expect(find.text('three.md'), findsNothing);
    expect(find.text('two.md'), findsOneWidget);
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getStringList('collapsedFolders:${dir.path}'), ['alpha', 'gamma'], reason: 'saved at once');

    // Hide and show the panel: the same folders stay folded.
    await tester.tap(find.byTooltip('Hide the pages panel'));
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsNothing, reason: 'the panel is gone');
    await tester.tap(find.byTooltip('Show the pages panel'));
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('one.md'), findsNothing, reason: 'alpha is still folded');
    expect(find.text('three.md'), findsNothing, reason: 'gamma is still folded');
    expect(find.text('two.md'), findsOneWidget, reason: 'beta is still open');

    // Unfold alpha, fold inner; the open page stays usable.
    await tester.tap(find.text('alpha'));
    await tester.pump();
    expect(find.text('one.md'), findsOneWidget);
    await tester.tap(find.text('inner'));
    await tester.pump();
    expect(find.text('deep.md'), findsNothing);
    await tester.tap(find.text('one.md'));
    await settle(tester);
    expect(find.text('one.md'), findsWidgets, reason: 'the page opened (name in the sidebar and the editor)');

    // Rename a folded folder: its state follows it. Delete one: nothing is left behind.
    final sidebar = tester.state<SidebarState>(find.byType(Sidebar));
    await tester.runAsync(() => sidebar.ws.rename('gamma', 'delta'));
    await settle(tester);
    expect(find.text('delta'), findsOneWidget);
    expect(find.text('three.md'), findsNothing, reason: 'delta is folded like gamma was');
    await tester.runAsync(() => sidebar.ws.rename('alpha/inner', 'beta/inner'));
    await settle(tester);
    expect(find.text('deep.md'), findsNothing, reason: 'the moved folder is still folded');
    expect(prefs.getStringList('collapsedFolders:${dir.path}'), ['beta/inner', 'delta']);
    await tester.runAsync(() => sidebar.ws.delete('delta'));
    await settle(tester);
    expect(prefs.getStringList('collapsedFolders:${dir.path}'), ['beta/inner']);

    // Restart: a fresh app on the same settings restores the folded set.
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await pumpApp(tester);
    expect(find.text('beta'), findsOneWidget);
    expect(find.text('inner'), findsOneWidget);
    expect(find.text('deep.md'), findsNothing, reason: 'beta/inner is folded after the restart');
    expect(find.text('one.md'), findsOneWidget);
    expect(find.text('two.md'), findsOneWidget);
    await tester.tap(find.text('inner'));
    await tester.pump();
    expect(find.text('deep.md'), findsOneWidget, reason: 'folders still open after restoring');
  });

  testWidgets('chat opens, minimises, maximises and closes', (tester) async {
    await pumpApp(tester);
    expect(find.text('hello.py'), findsWidgets);
    const open = 'Open the assistant (Ctrl+J)';
    expect(find.byTooltip(open), findsOneWidget); // the Assistant cell in the top-bar pill

    await tester.tap(find.byTooltip(open));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Minimize'), findsOneWidget);
    // The .py file is a code space; the composer is the only TextField.
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byTooltip('Minimize'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Restore'), findsOneWidget);
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byTooltip('Restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Maximize'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Restore size'), findsOneWidget);
    expect(find.byType(CodeEditor), findsNothing); // editor hidden
    expect(find.byType(TextField), findsOneWidget); // composer

    await tester.tap(find.byTooltip('Close (Ctrl+J)'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Minimize'), findsNothing);
    expect(find.byTooltip(open), findsOneWidget);
  });

  testWidgets('the model can edit the open page from the chat', (tester) async {
    fake
      ..queueToolCall('replace_text', {'path': 'hello.py', 'old_text': 'print("hi")', 'new_text': 'print("hello")'})
      ..queueText('Done: it now prints hello.');
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Open the assistant (Ctrl+J)'));
    await tester.pumpAndSettle();
    expect(find.text('Thinking: Medium'), findsWidgets);
    expect(find.text('llama3.2:3b'), findsWidgets);
    expect(find.text('hello.py'), findsWidgets); // context chip

    await tester.enterText(find.byKey(const Key('composer')), 'say hello instead');
    await tester.pump();
    await tester.tap(find.byTooltip('Send (Enter)'));
    await settle(tester);
    expect(File('${dir.path}/hello.py').readAsStringSync(), contains('print("hello")'));
    expect(find.textContaining('Edited hello.py'), findsOneWidget);
    expect(find.textContaining('Done: it now prints hello.'), findsOneWidget);
    // The editor reloaded the page the assistant changed.
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    expect(editor.controller!.text, contains('print("hello")'));

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(File('${dir.path}/hello.py').readAsStringSync(), contains('print("hi")'));
    expect(find.text('Undone'), findsOneWidget);
  });
}
