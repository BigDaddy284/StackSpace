import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/editor/links.dart';
import 'package:stack_space/editor/page_editor_controller.dart';
import 'package:stack_space/ui/editor/block_editor.dart';
import 'package:stack_space/ui/editor/inline_markdown.dart';
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
  group('link helpers', () {
    test('finds Markdown links and bare URLs, not URLs inside a Markdown link', () {
      final links = linksIn('see [docs](https://a.io/x) or https://b.io/y?q=1, and www.c.org/z.');
      expect(links.map((l) => l.url).toList(), ['https://a.io/x', 'https://b.io/y?q=1', 'www.c.org/z']);
      expect(links[0].label, 'docs');
      expect(links[0].isMarkdown, true);
      expect(links[1].isMarkdown, false);
      expect(links[1].end, 'see [docs](https://a.io/x) or https://b.io/y?q=1'.length,
          reason: 'the comma is not part of it');
      expect(links[2].end, 'see [docs](https://a.io/x) or https://b.io/y?q=1, and www.c.org/z'.length);
    });

    test('linkAt finds the link under the caret, including just after it', () {
      const t = 'go to https://x.io now';
      expect(linkAt(t, 0), isNull);
      expect(linkAt(t, 6)?.url, 'https://x.io');
      expect(linkAt(t, 18)?.url, 'https://x.io', reason: 'caret right after the link');
      expect(linkAt(t, 19), isNull);
    });

    test('isUrl and pastedUrl recognise one pasted URL and what it replaced', () {
      expect(isUrl('https://example.com/a?b=1#c'), true);
      expect(isUrl('www.example.com'), true);
      expect(isUrl('example.com'), false);
      expect(isUrl('https://a.io and more'), false);
      expect(pastedUrl('click here please', 'click https://a.io please'),
          (start: 6, removed: 'here', url: 'https://a.io'));
      expect(pastedUrl('[x] ', '[x] https://a.io/z'), (start: 4, removed: '', url: 'https://a.io/z'));
      expect(pastedUrl('see here now', 'see https://here.io now'), (start: 4, removed: 'here', url: 'https://here.io'),
          reason: 'shared letters between the words and the URL');
      expect(pastedUrl('abc', 'abcd'), isNull, reason: 'typing');
      expect(pastedUrl('abc', 'ab'), isNull, reason: 'deleting');
      expect(pastedUrl('x', 'xsome text https://a.io'), isNull, reason: 'a longer paste');
    });

    test('only web and mail links are opened', () {
      expect(safeUri('https://a.io/p')!.toString(), 'https://a.io/p');
      expect(safeUri('www.a.io')!.toString(), 'https://www.a.io');
      expect(safeUri('mailto:x@y.z')!.toString(), 'mailto:x@y.z');
      expect(safeUri('javascript:alert(1)'), isNull);
      expect(safeUri('file:///etc/passwd'), isNull);
      expect(safeUri('ftp://a.io'), isNull);
      expect(safeUri('https://'), isNull);
      expect(safeUri('not a url'), isNull);
    });

    test('openLink refuses unsafe schemes without calling the launcher and reports failures', () async {
      final opened = <Uri>[];
      launch = (uri) async {
        opened.add(uri);
        return uri.host != 'down.io';
      };
      expect(await openLink('javascript:alert(1)'), contains('Only web and mail links'));
      expect(opened, isEmpty);
      expect(await openLink('https://ok.io/a'), isNull);
      expect(await openLink('https://down.io'), contains('Could not open'));
      expect(opened.map((u) => u.toString()).toList(), ['https://ok.io/a', 'https://down.io']);
    });

    test('the inline renderer styles bare URLs and Markdown links as links', () {
      const base = TextStyle(fontSize: 14);
      final span = InlineMarkdownController.spanFor('a https://x.io/p, and [b](https://y.io).', base,
          styled: true, markerColor: Colors.grey, codeColor: Colors.red, linkColor: Colors.blue);
      final texts = <String>[];
      final linked = <String>[];
      span.visitChildren((s) {
        final t = (s as TextSpan).text ?? '';
        texts.add(t);
        if (s.style?.decoration == TextDecoration.underline && s.style?.color == Colors.blue) linked.add(t);
        return true;
      });
      expect(texts.join(), 'a https://x.io/p, and [b](https://y.io).');
      expect(linked, ['https://x.io/p', 'b']);
    });
  });

  group('links in the editor', () {
    late Directory dir;
    late PageEditorController editor;
    late List<Uri> opened;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('links_');
      final workspace = Workspace(dir.path);
      await workspace.init();
      editor = PageEditorController(workspace);
      opened = [];
      launch = (uri) async {
        opened.add(uri);
        return true;
      };
    });

    tearDown(() async {
      editor.dispose();
      await deleteTemp(dir);
    });

    Future<void> pumpEditor(WidgetTester tester, String markdown, {bool readOnly = false}) async {
      await tester.runAsync(() async {
        await File('${dir.path}/page.md').writeAsString(markdown);
        await editor.open('page.md');
      });
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: BlockEditor(controller: editor, readOnly: readOnly))));
      await tester.pump();
    }

    String saved() => File('${dir.path}/page.md').readAsStringSync();
    TextField fieldAt(WidgetTester tester, int i) => tester.widget<TextField>(find.byType(TextField).at(i));

    /// Pastes [text] over the field's selection the way the platform does:
    /// one editing-value update with the replacement.
    Future<void> paste(WidgetTester tester, int i, String text) async {
      final c = fieldAt(tester, i).controller!;
      final sel = c.selection;
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: c.text.replaceRange(sel.start, sel.end, text),
        selection: TextSelection.collapsed(offset: sel.start + text.length),
      ));
      await tester.pump();
      await tester.pump();
    }

    Future<void> withCtrl(WidgetTester tester, Future<void> Function() body) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await body();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets('a URL pasted over selected words links them; pasted alone it stays a bare link', (tester) async {
      await pumpEditor(tester, 'Read the manual today.\n\nMore\n');
      await tester.tap(find.byType(TextField).at(0));
      await tester.pump();
      fieldAt(tester, 0).controller!.selection = const TextSelection(baseOffset: 9, extentOffset: 15);
      await paste(tester, 0, 'https://docs.example.com/manual');
      expect(editor.document[0].text, 'Read the [manual](https://docs.example.com/manual) today.');
      expect(fieldAt(tester, 0).controller!.selection.extentOffset,
          'Read the [manual](https://docs.example.com/manual)'.length);

      await tester.tap(find.byType(TextField).at(1));
      await tester.pump();
      fieldAt(tester, 1).controller!.selection = const TextSelection.collapsed(offset: 4);
      await paste(tester, 1, ' https://example.com/x');
      expect(editor.document[1].text, 'More https://example.com/x');
      expect(linksIn(editor.document[1].text).single.url, 'https://example.com/x');

      // Multi-line paste keeps its text and links; ordinary text pastes as it is.
      await paste(tester, 1, '\nline two https://two.io\nline [three](https://three.io)');
      await tester.pump();
      expect(editor.document.blocks.map((b) => b.text).join('|'),
          'Read the [manual](https://docs.example.com/manual) today.|More https://example.com/x\nline two https://two.io\nline [three](https://three.io)');
      await paste(tester, 1, ' plain words');
      expect(editor.document[1].text, endsWith('[three](https://three.io) plain words'));
      await settle(tester);
      await waitSaved(tester, editor);
      expect(
          saved(),
          'Read the [manual](https://docs.example.com/manual) today.\n\nMore https://example.com/x\n'
          'line two https://two.io\nline [three](https://three.io) plain words\n');
    });

    testWidgets('Ctrl+click opens the link under the caret with its exact destination; a plain click only edits',
        (tester) async {
      await pumpEditor(
          tester, 'See [the site](https://example.com/path?q=1) or https://bare.io/x. Not javascript:alert(1)\n');
      final field = find.byType(TextField).first;
      final linkPos = tester.getTopLeft(field) + const Offset(60, 10); // inside "the site"
      await tester.tapAt(linkPos);
      await tester.pump(const Duration(seconds: 1)); // not a double tap
      expect(opened, isEmpty, reason: 'a plain click places the caret');
      expect(fieldAt(tester, 0).controller!.selection.isCollapsed, true);

      await withCtrl(tester, () => tester.tapAt(linkPos));
      expect(opened.map((u) => u.toString()).toList(), ['https://example.com/path?q=1']);
      await tester.pump(const Duration(seconds: 1));

      // The bare URL opens too: aim at its third character.
      final c = fieldAt(tester, 0).controller!;
      final editable = tester.state<EditableTextState>(find.byType(EditableText).first).renderEditable;
      final bareAt = c.text.indexOf('https://bare') + 3;
      final barePos = editable.localToGlobal(editable.getLocalRectForCaret(TextPosition(offset: bareAt)).center);
      await withCtrl(tester, () => tester.tapAt(barePos));
      expect(linkAt(c.text, c.selection.extentOffset)?.url, 'https://bare.io/x');
      expect(opened.length, 2);
      expect(opened.last.toString(), 'https://bare.io/x');
      await tester.pump(const Duration(seconds: 1));

      // Ctrl+click on plain text opens nothing; the unsafe scheme is not a link at all.
      await withCtrl(tester, () => tester.tapAt(tester.getTopLeft(field) + const Offset(10, 10)));
      expect(opened.length, 2);
      expect(linksIn(c.text).map((l) => l.url).toList(), ['https://example.com/path?q=1', 'https://bare.io/x']);
      expect(editor.document[0].text, startsWith('See [the site]'), reason: 'clicks never changed the text');
      await settle(tester);
    });

    testWidgets('on a read-only page a plain click opens the link', (tester) async {
      await pumpEditor(tester, 'Go to https://ro.io/p now\n', readOnly: true);
      final field = find.byType(TextField).first;
      await tester.tapAt(tester.getTopLeft(field) + const Offset(90, 10));
      await tester.pump();
      expect(opened.map((u) => u.toString()).toList(), ['https://ro.io/p']);
      await settle(tester);
    });

    testWidgets('Ctrl+K links a selection, links a selected URL, and unlinks an existing link', (tester) async {
      await pumpEditor(tester, 'pick words here\n\npick https://sel.io here\n');
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      final c = fieldAt(tester, 0).controller!;
      c.selection = const TextSelection(baseOffset: 5, extentOffset: 10);
      await withCtrl(tester, () => tester.sendKeyEvent(LogicalKeyboardKey.keyK));
      expect(editor.document[0].text, 'pick [words](url) here');
      expect(c.selection, const TextSelection(baseOffset: 13, extentOffset: 16),
          reason: 'url is selected to type over');
      await paste(tester, 0, 'https://w.io');
      expect(editor.document[0].text, 'pick [words](https://w.io) here');

      // Ctrl+K with the caret inside the link removes it and keeps the label.
      c.selection = const TextSelection.collapsed(offset: 8);
      await withCtrl(tester, () => tester.sendKeyEvent(LogicalKeyboardKey.keyK));
      expect(editor.document[0].text, 'pick words here');
      expect(c.selection, const TextSelection(baseOffset: 5, extentOffset: 10));

      // A selected URL becomes the destination with a label to replace.
      await tester.tap(find.byType(TextField).at(1));
      await tester.pump();
      final c1 = fieldAt(tester, 1).controller!;
      c1.selection = const TextSelection(baseOffset: 5, extentOffset: 19);
      await withCtrl(tester, () => tester.sendKeyEvent(LogicalKeyboardKey.keyK));
      expect(editor.document[1].text, 'pick [text](https://sel.io) here');
      expect(c1.selection, const TextSelection(baseOffset: 6, extentOffset: 10));
      await settle(tester);
      await waitSaved(tester, editor);
      expect(saved(), 'pick words here\n\npick [text](https://sel.io) here\n');

      // Reopen: the link is still there.
      await tester.runAsync(() => editor.open('page.md'));
      await tester.pump();
      expect(editor.document[1].text, 'pick [text](https://sel.io) here');
      await settle(tester);
    });
  });
}
