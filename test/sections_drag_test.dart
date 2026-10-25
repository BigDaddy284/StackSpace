import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/editor/page_editor_controller.dart';
import 'package:stack_space/ui/editor/block_editor.dart';
import 'package:stack_space/workspace/workspace.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  late Directory dir;
  late PageEditorController editor;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sections_');
    final workspace = Workspace(dir.path);
    await workspace.init();
    editor = PageEditorController(workspace);
  });

  tearDown(() async {
    editor.dispose();
    await dir.delete(recursive: true);
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

  String saved() => File('${dir.path}/page.md').readAsStringSync();
  Finder body(int index) => find.byKey(ValueKey('body-${editor.document[index].id}'));
  Finder handle(int index) => find.byKey(ValueKey('handle-${editor.document[index].id}'));
  Finder toggle(int index) => find.byKey(ValueKey('toggle-${editor.document[index].id}'));

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
    await tester.pump();
  }

  const page = '# One\n\nunder one\n\n## One point one\n\nunder one point one\n\n# Two\n\nunder two\n';

  testWidgets('the chevron folds a heading section; a caret move into it unfolds it', (tester) async {
    await pumpEditor(tester, page);
    expect(toggle(0), findsOneWidget);
    expect(toggle(1), findsNothing, reason: 'only headings have a chevron');
    for (var i = 0; i < 6; i++) {
      expect(body(i), findsOneWidget);
    }

    await tester.tap(toggle(0));
    await tester.pump();
    for (final i in [1, 2, 3]) {
      expect(body(i), findsNothing, reason: 'block $i is inside the folded section');
    }
    expect(body(4), findsOneWidget, reason: 'the next heading of the same level stays');
    expect(body(5), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Expand section, 3 hidden blocks')), findsOneWidget);
    expect(tester.getTopLeft(body(4)).dy - tester.getBottomLeft(body(0)).dy, lessThan(20),
        reason: 'the hidden rows take no space');
    expect(saved(), page, reason: 'folding changes nothing in the file');

    // Arrow Down from the folded heading lands in the hidden block and unfolds it.
    await tester.tap(body(0));
    await tester.pump();
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(editor.focusedBlock, 1);
    expect(body(1), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Expand section')), findsNothing);

    // Fold the inner section from the block menu, then unfold with the chevron.
    await tester.tap(handle(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collapse section'));
    await tester.pumpAndSettle();
    expect(body(3), findsNothing);
    expect(body(4), findsOneWidget);
    await tester.tap(toggle(2));
    await tester.pump();
    expect(body(3), findsOneWidget);
    await settle(tester);
  });

  testWidgets('folding a section with the caret inside moves the caret to the heading', (tester) async {
    await pumpEditor(tester, page);
    await tester.tap(body(2));
    await tester.pump();
    expect(editor.focusedBlock, 2);
    await tester.tap(toggle(0));
    await tester.pump();
    await tester.pump();
    expect(editor.focusedBlock, 0);
    expect(body(2), findsNothing);
    await settle(tester);
  });

  testWidgets('dragging a handle onto another row moves the block there and saves', (tester) async {
    await pumpEditor(tester, page);
    final target = tester.getCenter(body(5));
    final start = tester.getCenter(handle(1));
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
    await gesture.moveTo(Offset(target.dx, target.dy + 5)); // lower half: below "under two"
    await tester.pump();
    expect(find.byKey(const ValueKey('drop-line')), findsOneWidget, reason: 'the insertion line shows');
    await gesture.up();
    await tester.pump();
    await tester.pump();
    expect(editor.document.blocks.map((b) => b.text).toList(),
        ['One', 'One point one', 'under one point one', 'Two', 'under two', 'under one']);
    expect(find.byKey(const ValueKey('drop-line')), findsNothing);
    await settle(tester);
    expect(saved(), '# One\n\n## One point one\n\nunder one point one\n\n# Two\n\nunder two\n\nunder one\n');

    // Upper half of a row puts the block above it.
    final upper = tester.getTopLeft(body(0)) + const Offset(40, 3);
    final g2 = await tester.startGesture(tester.getCenter(handle(5)));
    await g2.moveBy(const Offset(0, -10));
    await tester.pump();
    await g2.moveTo(upper);
    await tester.pump();
    await g2.up();
    await tester.pump();
    await tester.pump();
    expect(editor.document[0].text, 'under one');
    expect(editor.document[1].text, 'One');
    await settle(tester);
  });

  testWidgets('a dropped block that lands where it was changes nothing', (tester) async {
    await pumpEditor(tester, page);
    final before = editor.document.version;
    final g = await tester.startGesture(tester.getCenter(handle(2)));
    await g.moveBy(const Offset(0, 5));
    await tester.pump();
    await g.moveTo(tester.getCenter(body(2)) + const Offset(0, 4));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(editor.document.version, before);
    await settle(tester);
  });
}
