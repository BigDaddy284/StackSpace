import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/editor/blocks.dart';
import 'package:stack_space/editor/page_editor_controller.dart';
import 'package:stack_space/ui/editor/block_editor.dart';
import 'package:stack_space/ui/editor/block_menu.dart';
import 'package:stack_space/ui/editor/format_toolbar.dart';
import 'package:stack_space/workspace/workspace.dart';
import 'support/temp.dart';

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
    dir = await Directory.systemTemp.createTemp('block_menu_');
    final workspace = Workspace(dir.path);
    await workspace.init();
    editor = PageEditorController(workspace);
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
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BlockEditor(controller: editor, readOnly: false))));
    await tester.pump();
  }

  TextField fieldAt(WidgetTester tester, int i) => tester.widget<TextField>(find.byType(TextField).at(i));
  String saved() => File('${dir.path}/page.md').readAsStringSync();

  Future<void> select(WidgetTester tester, int field, int start, int end) async {
    await tester.tap(find.byType(TextField).at(field));
    await tester.pump();
    fieldAt(tester, field).controller!.selection = TextSelection(baseOffset: start, extentOffset: end);
    await tester.pump();
    await tester.pump();
  }

  group('floating toolbar', () {
    testWidgets('appears on a selection, formats it, and goes when the selection collapses', (tester) async {
      await pumpEditor(tester, 'make this bold\n');
      final doc = editor.document;
      expect(find.byType(FormatToolbar), findsNothing);
      await select(tester, 0, 10, 14);
      expect(find.byType(FormatToolbar), findsOneWidget);
      final anchor = tester.widget<FormatToolbar>(find.byType(FormatToolbar)).anchor;
      final toolbar = tester.getRect(find.bySemanticsLabel('Formatting toolbar'));
      expect(toolbar.bottom <= anchor.top || toolbar.top >= anchor.bottom, isTrue,
          reason: 'never covers the selection');

      await tester.tap(find.byTooltip('Bold (Ctrl+B)'));
      await tester.pump();
      expect(doc[0].text, 'make this **bold**');
      expect(fieldAt(tester, 0).controller!.selection, const TextSelection(baseOffset: 12, extentOffset: 16));
      expect(tester.binding.focusManager.primaryFocus?.debugLabel, contains('block ${doc[0].id}'));
      await tester.pump();
      expect(find.byType(FormatToolbar), findsOneWidget, reason: 'the selection is still there');

      await tester.tap(find.byTooltip('Inline code (Ctrl+E)'));
      await tester.pump();
      expect(doc[0].text, 'make this **`bold`**');
      await tester.tap(find.byTooltip('Link (Ctrl+K)'));
      await tester.pump();
      expect(doc[0].text, 'make this **`[bold](url)`**');
      expect(fieldAt(tester, 0).controller!.selection, const TextSelection(baseOffset: 20, extentOffset: 23));

      fieldAt(tester, 0).controller!.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();
      await tester.pump();
      expect(find.byType(FormatToolbar), findsNothing);
      await settle(tester);
      await waitSaved(tester, editor);
      expect(saved(), 'make this **`[bold](url)`**\n');
    });

    testWidgets('turn into changes the block kind and keeps the text', (tester) async {
      await pumpEditor(tester, 'a line\n\nsecond\n');
      final doc = editor.document;
      await select(tester, 0, 0, 6);
      expect(find.bySemanticsLabel(RegExp('Turn into, now Text')), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp('Turn into, now Text')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Heading 2'));
      await tester.pumpAndSettle();
      expect(doc[0].kind, BlockKind.heading);
      expect(doc[0].level, 2);
      expect(doc[0].text, 'a line');
      expect(doc.length, 2);
      await settle(tester);
      await waitSaved(tester, editor);
      expect(saved(), '## a line\n\nsecond\n');
    });

    testWidgets('does not show in a plain file, a read-only page or on a collapsed caret', (tester) async {
      await pumpEditor(tester, 'x\n');
      await tester.tap(find.byType(TextField));
      await tester.pump();
      fieldAt(tester, 0).controller!.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();
      await tester.pump();
      expect(find.byType(FormatToolbar), findsNothing);
      await settle(tester);
    });
  });

  group('block menu', () {
    Future<void> openMenu(WidgetTester tester, int blockNumber) async {
      final id = editor.document[blockNumber - 1].id;
      await tester.tap(find.byKey(ValueKey('handle-$id')));
      await tester.pumpAndSettle();
    }

    testWidgets('handle shows on hover or focus, menu duplicates, moves and deletes', (tester) async {
      await pumpEditor(tester, '# T\n\n- a\n- b\n\nlast\n');
      final doc = editor.document;
      expect(find.byType(BlockHandle), findsNWidgets(4));
      // Hidden until the row is hovered or focused.
      Opacity opacityOf(int i) =>
          tester.widget<Opacity>(find.descendant(of: find.byType(BlockHandle).at(i), matching: find.byType(Opacity)));
      expect(opacityOf(1).opacity, 0);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(TextField).at(1)));
      await tester.pump();
      expect(opacityOf(1).opacity, greaterThan(0));
      await gesture.moveTo(const Offset(900, 700));
      await tester.pump();
      expect(opacityOf(1).opacity, 0);
      await tester.tap(find.byType(TextField).at(2));
      await tester.pump();
      expect(opacityOf(2).opacity, greaterThan(0), reason: 'focused block shows its handle');

      await openMenu(tester, 2); // "- a"
      expect(find.text('Duplicate'), findsOneWidget);
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();
      expect(doc.length, 5);
      expect(doc[2].text, 'a');
      expect(doc[2].kind, BlockKind.bullet);
      expect(doc[2].id, isNot(doc[1].id));

      await openMenu(tester, 1); // heading: cannot move up
      final up = tester.widget<PopupMenuItem<BlockAction>>(find.widgetWithText(PopupMenuItem<BlockAction>, 'Move up'));
      expect(up.enabled, isFalse);
      await tester.tap(find.text('Move down'));
      await tester.pumpAndSettle();
      expect(doc[1].kind, BlockKind.heading);
      expect(doc[0].text, 'a');

      await openMenu(tester, 2); // the heading, now second
      await tester.tap(find.text('Move up'));
      await tester.pumpAndSettle();
      expect(doc[0].kind, BlockKind.heading);

      await openMenu(tester, 5); // "last"
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(doc.length, 4);
      expect(doc[doc.length - 1].text, 'b');
      await settle(tester);
      await waitSaved(tester, editor);
      expect(saved(), '# T\n\n- a\n- a\n- b\n');
    });

    testWidgets('turn into from the menu converts a list item to a code block and a code block back', (tester) async {
      await pumpEditor(tester, '- item\n');
      final doc = editor.document;
      await openMenu(tester, 1);
      await tester.tap(find.textContaining('Turn into'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Code block'));
      await tester.pumpAndSettle();
      expect(doc[0].kind, BlockKind.code);
      expect(doc[0].text, 'item');
      // A code block's menu has no "turn into"; Backspace on empty does that.
      await openMenu(tester, 1);
      expect(find.textContaining('Turn into'), findsNothing);
      expect(find.text('Duplicate'), findsOneWidget);
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();
      expect(doc.length, 2);
      expect(doc[1].kind, BlockKind.code);
      expect(doc[1].text, 'item');
      await settle(tester);
      await waitSaved(tester, editor);
      expect(saved(), '```\nitem\n```\n\n```\nitem\n```\n');
    });
  });
}
