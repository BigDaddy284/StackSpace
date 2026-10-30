import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/editor/spell_checker.dart';
import 'package:stack_space/ui/editor/inline_markdown.dart';
import 'package:stack_space/ui/editor/spelling.dart';

/// The bundled word list, read from disk (the same file the app loads).
List<String> bundledWords() =>
    const LineSplitter().convert(utf8.decode(gzip.decode(File(SpellChecker.asset).readAsBytesSync())));

/// The spans of [span] drawn with the wavy spelling underline, as text.
List<String> marked(InlineSpan span) {
  final out = <String>[];
  span.visitChildren((s) {
    if (s is TextSpan && s.text != null && s.style?.decorationStyle == TextDecorationStyle.wavy) out.add(s.text!);
    return true;
  });
  return out;
}

void main() {
  final words = bundledWords();

  test('the bundled word list loads through the asset bundle', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final own = SpellChecker();
    await own.load();
    expect(own.active, isTrue);
    expect(own.isCorrect('receive'), isTrue);
    expect(own.isCorrect('recieve'), isFalse);
  });

  group('SpellChecker', () {
    final checker = SpellChecker()..useWords(words);

    test('knows common words in any capitalisation', () {
      for (final w in ['the', 'The', 'receive', "don't", 'don’t', 'Windows', 'email']) {
        expect(checker.isCorrect(w), isTrue, reason: w);
      }
    });

    test('flags misspellings', () {
      for (final w in ['teh', 'recieve', 'definately', 'Teh']) {
        expect(checker.isCorrect(w), isFalse, reason: w);
      }
    });

    test('leaves acronyms, names with inner capitals and possessives alone', () {
      for (final w in ['NASA', 'XYZQ', 'StackSpace', 'iPhone', "Kevin's", 'a']) {
        expect(checker.isCorrect(w), isTrue, reason: w);
      }
    });

    test('skips paths, addresses, numbers and code', () {
      const text = 'Open notez.txt at C:\\Userz\\me, see https://exampel.com/pagez, '
          'call foo_barz, mail mee@hostz.com, 3rdd place, www.sitez.org, and teh end';
      final found = [for (final r in checker.misspellings(text)) r.textInside(text)];
      expect(found, ['teh']);
    });

    test('skips the ranges it is told to', () {
      const text = 'teh teh';
      final found = checker.misspellings(text, skip: [const TextRange(start: 0, end: 3)]);
      expect(found, [const TextRange(start: 4, end: 7)]);
    });

    test('suggests likely corrections first, in the word\'s case', () {
      expect(checker.suggestions('recieve').first, 'receive');
      expect(checker.suggestions('teh'), contains('the'));
      expect(checker.suggestions('Teh'), contains('The'));
      expect(checker.suggestions('definately'), contains('definitely'));
      expect(checker.suggestions('teh', limit: 3), hasLength(3));
    });

    test('added and ignored words are no longer flagged', () {
      final own = SpellChecker()..useWords(words);
      List<String>? saved;
      own.onAddedChanged = (w) => saved = w;
      expect(own.isCorrect('Zorbly'), isFalse);
      own.addWord('Zorbly');
      expect(own.isCorrect('Zorbly'), isTrue);
      expect(saved, ['Zorbly']);
      own.ignore('qwzz');
      expect(own.isCorrect('qwzz'), isTrue);
    });

    test('nothing is flagged before the list loads or when turned off', () {
      final own = SpellChecker();
      expect(own.misspellings('teh'), isEmpty);
      own.useWords(['the']);
      expect(own.active, isTrue);
      own.enabled = false;
      expect(own.active, isFalse);
    });
  });

  group('Spelling marks', () {
    setUpAll(() => SpellChecker.instance.useWords(words));

    testWidgets('underline misspelled words but not code, link addresses or the word being typed', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      final c = InlineMarkdownController(text: 'teh `teh` [teh](http://tehh.com) **teh** quik');
      var span = c.buildTextSpan(context: context, withComposing: false);
      // The link's label is prose; its address is not.
      expect(marked(span), ['teh', 'teh', 'teh', 'quik']);

      // The caret right after "quik": still being typed.
      c.selection = TextSelection.collapsed(offset: c.text.length);
      span = c.buildTextSpan(context: context, withComposing: true);
      expect(marked(span), ['teh', 'teh', 'teh']);

      // The text itself is unchanged by the marks.
      expect(span.toPlainText(), c.text);

      c.styled = false; // code blocks
      expect(marked(c.buildTextSpan(context: context, withComposing: false)), isEmpty);
    });

    testWidgets('the right-click menu offers corrections and applies them', (tester) async {
      final c = SpellCheckedController(text: 'I recieve mail');
      final changes = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(controller: c, contextMenuBuilder: spellingContextMenu, onChanged: changes.add),
        ),
      ));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      c.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();
      tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
      await tester.pumpAndSettle();
      expect(find.text('Add to dictionary'), findsOneWidget);
      await tester.tap(find.text('receive'));
      await tester.pumpAndSettle();
      expect(c.text, 'I receive mail');
      expect(changes, ['I receive mail']);
      expect(c.misspellings, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });
}
