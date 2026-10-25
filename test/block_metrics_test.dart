import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/app/theme.dart';
import 'package:stack_space/editor/page_editor_controller.dart';
import 'package:stack_space/ui/editor/block_editor.dart';
import 'package:stack_space/ui/editor/block_metrics.dart';
import 'package:stack_space/workspace/workspace.dart';
import 'support/temp.dart';

/// The list gives every row a height computed before the row is built, so a
/// wrong number would clip or overlap rows. This pumps a page with every
/// block kind at two widths and two text scales, lays each row out at its
/// natural height, and checks the computed height matches to the pixel.
void main() {
  final page = '# Heading one\n\n'
      '## Heading two\n\n'
      '### Heading three\n\n'
      'A short paragraph.\n\n'
      'A long paragraph with **bold**, _italic_, `inline code that uses another font`, ~~strike~~ and a '
      '[link](https://example.com) that goes on and on so that it wraps over several lines at any width the '
      'editor is likely to have, and then some more words to make sure of it.\n\n'
      'Soft\nbreaks\nkept\n\n'
      '- bullet item\n- a bullet item long enough to wrap around the end of the row at the narrower width used here\n'
      '  - nested item\n    - deeper\n\n'
      '1. first\n2. second\n\n'
      '- [ ] todo\n- [x] done todo with a longer text that wraps at the narrow width used in this test as well\n\n'
      '> A quote\n> with two lines\n\n'
      '---\n\n'
      '![Missing picture](missing/pic.png)\n\n'
      '![](nowhere.png)\n\n'
      '| a | b |\n| --- | --- |\n| 1 | 2 |\n\n'
      '<div>raw html</div>\n\n'
      '```python Download helper\ndef f():\n    return 1\n```\n\n'
      '```\n${'x' * 300}\n```\n\n'
      '\n\n'
      'Last.\n';

  for (final width in [700.0, 1100.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('measured heights match rendered rows at ${width.toInt()} px, scale $scale', (tester) async {
        late Directory dir;
        late PageEditorController editor;
        await tester.runAsync(() async {
          dir = await Directory.systemTemp.createTemp('metrics_');
          final workspace = Workspace(dir.path);
          await workspace.init();
          editor = PageEditorController(workspace);
          await File('${dir.path}/page.md').writeAsString(page);
          await editor.open('page.md');
        });
        tester.view.physicalSize = Size(width, 4000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 4000), textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: BlockEditor(controller: editor, readOnly: false)),
          ),
        ));
        await tester.pump();

        final doc = editor.document;
        final element = tester.element(find.byType(BlockEditor));
        final metrics = BlockMetrics(
            palette: StackColors.of(element),
            textScaler: TextScaler.linear(scale),
            inputStyle: BlockMetrics.inputStyleOf(element));
        final rowWidth = width - BlockMetrics.listPadding - BlockMetrics.gutter;
        final problems = <String>[];
        for (var i = 0; i < doc.length; i++) {
          final block = doc[i];
          final body = find.byKey(ValueKey('body-${block.id}'));
          if (body.evaluate().isEmpty) continue; // below the 4000 px viewport
          final rendered = tester.getSize(body).height;
          final computed = metrics.bodyHeight(block, rowWidth, caption: block.caption.isNotEmpty);
          if ((rendered - computed).abs() > 0.5) {
            problems
                .add('${block.kind.name} "${block.text.length > 20 ? '${block.text.substring(0, 20)}…' : block.text}"'
                    ': rendered $rendered, computed $computed');
          }
        }
        expect(problems, isEmpty);
        expect(doc.length, greaterThan(20));
        debugDefaultTargetPlatformOverride = null;
        editor.dispose();
        await tester.runAsync(() => deleteTemp(dir));
      });
    }
  }
}
