import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/editor/blocks.dart';

String roundTrip(String md) => writeMarkdown(parseMarkdown(md));

void main() {
  test('headings, paragraphs and inline markdown are kept as typed', () {
    const md =
        '# Title\n\nPlain **bold** and _italic_ and `code` and [link](https://x.y/z).\nSecond line of the same paragraph.\n\n## Second\n\nAnother.\n';
    final blocks = parseMarkdown(md);
    expect(blocks.map((b) => b.kind), [BlockKind.heading, BlockKind.paragraph, BlockKind.heading, BlockKind.paragraph]);
    expect(blocks[0].level, 1);
    expect(blocks[1].text,
        'Plain **bold** and _italic_ and `code` and [link](https://x.y/z).\nSecond line of the same paragraph.');
    expect(roundTrip(md), md);
  });

  test('lists keep markers, nesting, numbers and checkboxes', () {
    const md = '- one\n- two\n  - nested\n    - deeper\n- three\n\n1. first\n2. second\n\n- [ ] todo\n- [x] done\n';
    final blocks = parseMarkdown(md);
    expect(blocks[2].level, 1);
    expect(blocks[3].level, 2);
    expect(blocks[5].kind, BlockKind.numbered);
    expect(blocks[6].number, 2);
    expect(blocks[7].kind, BlockKind.todo);
    expect(blocks[8].checked, isTrue);
    expect(roundTrip(md), md);
  });

  test('blank lines between blocks are kept exactly, including none and several', () {
    const md = '# T\n\n\n\nPara\n- a\n* b\n+ c\n### Next\n1. x\n```c#\nint y;\n```\n\n\nEnd\n';
    final blocks = parseMarkdown(md);
    expect(blocks[1].gapBefore, 3);
    expect(blocks[2].gapBefore, 0);
    expect(blocks[3].marker, '*');
    expect(roundTrip(md), md);
    // New blocks without a recorded gap use the defaults.
    final fresh = [for (final b in blocks) b.copyWith(clearGap: true)];
    expect(writeMarkdown(fresh), '# T\n\nPara\n\n- a\n* b\n+ c\n\n### Next\n\n1. x\n\n```c#\nint y;\n```\n\nEnd\n');
  });

  test('quotes, callout-style quotes and dividers', () {
    const md = '> A quote\n> second line\n\n> 🎮 Callout text\n\n---\n\nAfter\n';
    final blocks = parseMarkdown(md);
    expect(blocks[0].text, 'A quote\nsecond line');
    expect(blocks[2].kind, BlockKind.divider);
    expect(roundTrip(md), md);
  });

  test('code fences keep language, blank lines, tabs, markdown characters, CR and unicode', () {
    const code = 'def **f**(x):\n\treturn _x_ * 2  # café ✓\r\n\n\n# not a heading\n- not a list\nprint("done")';
    const md = '# Script\n\n```python\n$code\n```\n\nText after.\n';
    final blocks = parseMarkdown(md);
    expect(blocks[1].kind, BlockKind.code);
    expect(blocks[1].language, 'python');
    expect(blocks[1].text, code);
    expect(roundTrip(md), md);
  });

  test('fences without a language, with ~~~, with backticks inside, and unterminated', () {
    const md = '```\nplain\n```\n\n````\nhas ``` inside\n````\n';
    final blocks = parseMarkdown(md);
    expect(blocks[0].language, isNull);
    expect(blocks[1].text, 'has ``` inside');
    expect(roundTrip(md), md);
    expect(parseMarkdown('~~~js\nx\n~~~\n')[0].language, 'js');
    final open = parseMarkdown('```c#\nint x;\n');
    expect(open.single.text, 'int x;');
    expect(open.single.language, 'c#');
  });

  test('images, tables and html are kept', () {
    const md =
        '![Untitled.png](Camera%20Controller/Untitled.png)\n\n| **Description** | **Commands** |\n| --- | --- |\n| Launch | ollama launch claude |\n\n<div>raw</div>\n';
    final blocks = parseMarkdown(md);
    expect(blocks[0].kind, BlockKind.image);
    expect(blocks[0].alt, 'Untitled.png');
    expect(blocks[1].kind, BlockKind.table);
    expect(blocks[2].kind, BlockKind.raw);
    expect(roundTrip(md), md);
  });

  test('block start lines match the written markdown', () {
    const md = '# T\n\n- a\n- b\n\n```py\nx\ny\n```\n\nlast\n';
    final blocks = parseMarkdown(md);
    final lines = writeMarkdown(blocks).split('\n');
    for (var i = 0; i < blocks.length; i++) {
      final start = blockStartLine(blocks, i);
      expect(lines[start - 1], blockToMarkdown(blocks[i], number: 1).split('\n').first, reason: 'block $i');
    }
  });

  test('writes with the same ids after copyWith', () {
    final b = Block(kind: BlockKind.paragraph, text: 'a');
    expect(b.copyWith(text: 'b').id, b.id);
    expect(b.clone().id, isNot(b.id));
  });

  // Runs over a folder of real pages when STACKSPACE_PAGES points at one.
  final pages = Platform.environment['STACKSPACE_PAGES'];
  test('real pages round-trip', () {
    final files = Directory(pages!).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.md'));
    final diffs = <String>[];
    var count = 0;
    for (final f in files) {
      count++;
      final md = f.readAsStringSync();
      final out = roundTrip(md);
      if (out != md) {
        final a = md.split('\n'), b = out.split('\n');
        var i = 0;
        while (i < a.length && i < b.length && a[i] == b[i]) {
          i++;
        }
        diffs.add(
            '${f.path.split('/').last} line ${i + 1}\n  in : ${i < a.length ? a[i] : '<end>'}\n  out: ${i < b.length ? b[i] : '<end>'}');
      }
    }
    stdout.writeln('${count - diffs.length}/$count pages identical');
    for (final d in diffs) {
      stdout.writeln(d);
    }
    expect(diffs, isEmpty);
  }, skip: pages == null ? 'set STACKSPACE_PAGES to a folder of .md pages' : false);
}
