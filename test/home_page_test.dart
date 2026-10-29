import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Settles until [done] holds, for up to about five seconds of real time:
/// a slow runner can take longer than one [settle] to finish a tool call
/// and its file write.
Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 12 && !done(); i++) {
    await settle(tester);
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

  testWidgets('New folder creates a folder that shows at once, nested, persists, and reports problems', (tester) async {
    // Bug 4: the folder was created on disk but the panel hid every folder
    // without a page in it, so the button looked broken.
    await pumpApp(tester);
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    expect(find.text('Create'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Notes');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle(); // the dialog's closing animation
    await settle(tester);
    expect(find.text('Notes'), findsOneWidget, reason: 'the empty folder shows in the panel');
    expect(await tester.runAsync(() => Directory('${dir.path}/Notes').exists()), true);

    // Cancel creates nothing; an empty name creates nothing.
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Dropped');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('Dropped'), findsNothing);
    expect(await tester.runAsync(() => Directory('${dir.path}/Dropped').exists()), false);
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '   ');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle(); // the dialog's closing animation
    await settle(tester);
    expect(await tester.runAsync(() => Directory(dir.path).list().length), 2, reason: 'hello.py and Notes only');

    // A nested folder from the folder's menu, and a path typed with a slash.
    await tester.tap(find.text('Notes'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New folder here'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Notes/2026');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle(); // the dialog's closing animation
    await settle(tester);
    expect(find.text('2026'), findsOneWidget);
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Notes/2026/Q4');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle(); // the dialog's closing animation
    await settle(tester);
    expect(find.text('Q4'), findsOneWidget);
    expect(await tester.runAsync(() => Directory('${dir.path}/Notes/2026/Q4').exists()), true);

    // A duplicate name is reported, not swallowed.
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Notes');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await settle(tester); // the existence check reads the disk
    expect(find.textContaining('already exists'), findsOneWidget, reason: 'shown in a snackbar');
    await tester.pump(const Duration(seconds: 5));

    // The new folder folds, unfolds, renames and deletes like any other, and is there after a restart.
    await tester.tap(find.text('Notes'));
    await tester.pump();
    expect(find.text('2026'), findsNothing);
    await tester.tap(find.text('Notes'));
    await tester.pump();
    expect(find.text('2026'), findsOneWidget);
    final sidebar = tester.state<SidebarState>(find.byType(Sidebar));
    await tester.runAsync(() => sidebar.ws.rename('Notes', 'Ideas'));
    await settle(tester);
    expect(find.text('Ideas'), findsOneWidget);
    expect(find.text('Notes'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await pumpApp(tester);
    expect(find.text('Ideas'), findsOneWidget);
    expect(find.text('Q4'), findsOneWidget);
    final restarted = tester.state<SidebarState>(find.byType(Sidebar));
    await tester.runAsync(() => restarted.ws.delete('Ideas/2026'));
    await settle(tester);
    expect(find.text('Q4'), findsNothing);
    expect(find.text('Ideas'), findsOneWidget);
    expect(find.text('hello.py'), findsWidgets, reason: 'existing pages untouched');
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
    final page = File('${dir.path}/hello.py');
    await settleUntil(tester, () =>
        page.readAsStringSync().contains('print("hello")') &&
        find.textContaining('Done: it now prints hello.').evaluate().isNotEmpty);
    expect(page.readAsStringSync(), contains('print("hello")'));
    expect(find.textContaining('Edited hello.py'), findsOneWidget);
    expect(find.textContaining('Done: it now prints hello.'), findsOneWidget);
    // The editor reloaded the page the assistant changed.
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    expect(editor.controller!.text, contains('print("hello")'));

    await tester.tap(find.text('Undo'));
    await settleUntil(tester, () =>
        page.readAsStringSync().contains('print("hi")') && find.text('Undone').evaluate().isNotEmpty);
    expect(page.readAsStringSync(), contains('print("hi")'));
    expect(find.text('Undone'), findsOneWidget);
  });

  /// Right-clicks the row named [name] (or the empty space below the rows)
  /// and picks [item] from its menu.
  Future<void> menu(WidgetTester tester, Finder target, String item) async {
    await tester.tap(target, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(item).last);
    await settle(tester);
  }

  testWidgets('copy and paste a page or a folder from the right-click menu', (tester) async {
    await tester.runAsync(() async {
      await File('${dir.path}/alpha/one.md').create(recursive: true);
      await (await File('${dir.path}/alpha/sub/deep.md').create(recursive: true)).writeAsString('deep', flush: true);
      await File('${dir.path}/beta/two.md').create(recursive: true);
    });
    await pumpApp(tester);

    // A page into a folder.
    await menu(tester, find.text('hello.py').first, 'Copy page');
    await menu(tester, find.text('beta'), 'into this folder');
    expect(File('${dir.path}/beta/hello.py').existsSync(), isTrue);
    expect(File('${dir.path}/hello.py').existsSync(), isTrue, reason: 'the original stays');

    // A folder, with its sub-pages, beside a page in another folder.
    await menu(tester, find.text('alpha'), 'Copy folder');
    await menu(tester, find.text('two.md'), 'here');
    expect(File('${dir.path}/beta/alpha/sub/deep.md').readAsStringSync(), 'deep');

    // Pasting where the name is taken makes a duplicate.
    await menu(tester, find.text('alpha').first, 'Duplicate');
    expect(Directory('${dir.path}/alpha copy/sub').existsSync(), isTrue);
  });

  testWidgets('cut and paste moves several picked rows', (tester) async {
    await tester.runAsync(() async {
      await File('${dir.path}/a.md').create();
      await File('${dir.path}/b.md').create();
      await Directory('${dir.path}/box').create();
      await File('${dir.path}/box/keep.md').create();
    });
    await pumpApp(tester);

    await tester.tap(find.text('a.md'));
    await settle(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('b.md'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await menu(tester, find.text('b.md'), 'Cut 2 items');
    await menu(tester, find.text('box'), 'into this folder');
    expect(File('${dir.path}/box/a.md').existsSync(), isTrue);
    expect(File('${dir.path}/box/b.md').existsSync(), isTrue);
    expect(File('${dir.path}/a.md').existsSync(), isFalse);
  });

  testWidgets('drag a page into a folder and a folder back out', (tester) async {
    await tester.runAsync(() async {
      await File('${dir.path}/note.md').create();
      await File('${dir.path}/outer/inner/deep.md').create(recursive: true);
    });
    await pumpApp(tester);

    Future<void> drag(Finder from, Finder to) async {
      final start = tester.getCenter(from);
      final end = tester.getCenter(to);
      final gesture = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
      await tester.pump();
      for (var i = 1; i <= 5; i++) {
        await gesture.moveTo(Offset.lerp(start, end, i / 5)!);
        await tester.pump();
      }
      await gesture.up();
      await settle(tester);
    }

    await drag(find.text('note.md').first, find.text('outer'));
    expect(File('${dir.path}/outer/note.md').existsSync(), isTrue);

    // Dropped on a top-level page, a folder goes to the top level.
    await drag(find.text('inner'), find.text('hello.py').first);
    expect(File('${dir.path}/inner/deep.md').existsSync(), isTrue);
    expect(Directory('${dir.path}/outer/inner').existsSync(), isFalse);
  });

  testWidgets('a slow right-click on a folder opens one menu', (tester) async {
    // A press held past the tap timeout opened the row's menu and the list's
    // top-level menu on top of each other.
    await tester.runAsync(() => File('${dir.path}/box/in.md').create(recursive: true));
    await pumpApp(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.text('box')),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    debugPrint('MENUS: ${find.textContaining('Paste').evaluate().length} ${find.textContaining('New page here').evaluate().length}');
    expect(find.text('Copy folder'), findsOneWidget);
    expect(find.text('New page here'), findsOneWidget, reason: 'only the folder menu is open');

    // Right-clicking below the rows still opens the top-level menu.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    final below = tester.getBottomLeft(find.text('hello.py').first) + const Offset(0, 60);
    await tester.tapAt(below, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('New page here'), findsOneWidget);
    expect(find.text('Copy folder'), findsNothing);
  });
}
