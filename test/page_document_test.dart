import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/editor/blocks.dart';
import 'package:stack_space/editor/page_document.dart';

void main() {
  test('split, merge and convert keep the markdown consistent', () {
    final doc = PageDocument()..load('# Title\n\n- one\n- two\n');
    expect(doc.length, 3);
    final caret = doc.split(2, 2); // "tw|o"
    expect(caret, (block: 3, offset: 0));
    expect(doc[3].kind, BlockKind.bullet);
    expect(doc.toMarkdown(), '# Title\n\n- one\n- tw\n- o\n');
    doc.mergeWithPrevious(3);
    expect(doc.toMarkdown(), '# Title\n\n- one\n- two\n');
    doc.convert(2, BlockKind.paragraph);
    expect(doc.toMarkdown(), '# Title\n\n- one\n\ntwo\n');
    doc.split(0, 3);
    expect(doc[1].kind, BlockKind.paragraph);
    expect(doc.toMarkdown(), '# Tit\n\nle\n\n- one\n\ntwo\n');
  });

  test('typing coalesces into one undo step, other edits do not', () {
    final doc = PageDocument()..load('a\n');
    doc.updateText(0, 'ab');
    doc.updateText(0, 'abc');
    doc.insert(1, Block(kind: BlockKind.paragraph, text: 'new'));
    expect(doc.toMarkdown(), 'abc\n\nnew\n');
    doc.undo();
    expect(doc.toMarkdown(), 'abc\n');
    expect(doc.undo(), isNotNull);
    expect(doc.toMarkdown(), 'a\n');
    expect(doc.undo(), isNull);
    doc.redo();
    doc.redo();
    expect(doc.toMarkdown(), 'abc\n\nnew\n');
    expect(doc.canRedo, isFalse);
  });

  test('a non-markdown file is one code block and saves byte for byte', () {
    const py = 'def f():\n    return "# not a heading"\n\n- not a list\n';
    final doc = PageDocument()..load(py, markdown: false);
    expect(doc.plain, isTrue);
    expect(doc.length, 1);
    expect(doc.toMarkdown(), py);
  });

  test('removing the last block leaves an empty paragraph', () {
    final doc = PageDocument()..load('only\n');
    doc.remove(0);
    expect(doc.length, 1);
    expect(doc.toMarkdown(), '\n');
    doc.indent(0, 1); // not a list: no-op
    expect(doc.canUndo, isTrue);
  });

  test('indent, check and move', () {
    final doc = PageDocument()..load('- [ ] a\n- [ ] b\n');
    doc.indent(1, 1);
    doc.toggleChecked(0);
    expect(doc.toMarkdown(), '- [x] a\n  - [ ] b\n');
    doc.move(1, 0);
    expect(doc[0].text, 'b');
  });
}
