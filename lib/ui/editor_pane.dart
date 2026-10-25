import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../editor/page_editor_controller.dart';
import 'editor/block_editor.dart';
import 'widgets/controls.dart';

const _codeStyle =
    TextStyle(fontFamily: 'Cascadia Mono', fontFamilyFallback: StackType.mono, fontSize: 14, height: 1.45);

class EditorPane extends StatelessWidget {
  const EditorPane({super.key, required this.controller, required this.locked, required this.onNewPage});

  final PageEditorController controller;

  /// True while the assistant is working, so the user's typing can't race its edits.
  final bool locked;
  final VoidCallback onNewPage;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    return ColoredBox(
      color: p.canvas,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final path = controller.path;
          if (path == null) {
            return EmptyState(
              icon: Icons.edit_outlined,
              title: controller.error ?? 'Pick a page to edit',
              detail: 'Choose a page on the left, or create a new one.\nThe assistant can read and change it with you.',
              actions: [SsButton(icon: Icons.add, label: 'New page', primary: true, onPressed: onNewPage)],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(path,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.subText, fontSize: StackType.button)),
                    ),
                    if (locked) _Badge(icon: Icons.lock_outline, text: 'Assistant is working'),
                    if (controller.isLarge) _Badge(icon: Icons.visibility_outlined, text: 'Large file: read-only'),
                    if (controller.error != null)
                      _Badge(icon: Icons.error_outline, text: controller.error!, error: true),
                  ],
                ),
              ),
              Expanded(
                child: controller.isLarge
                    ? _LargeFileView(lines: controller.largeLines!)
                    : BlockEditor(controller: controller, readOnly: locked),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text, this.error = false});
  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: error ? p.error : p.warning),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(color: error ? p.error : p.subText, fontSize: StackType.button)),
      ]),
    );
  }
}

/// Shows a huge file one line per row, building only the rows on screen.
class _LargeFileView extends StatelessWidget {
  const _LargeFileView({required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    final width = '${lines.length}'.length * 9.0 + 16;
    final style = _codeStyle.copyWith(color: p.text);
    return Scrollbar(
      child: ListView.builder(
        itemExtent: 20.3,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: lines.length,
        itemBuilder: (context, i) => Row(
          children: [
            SizedBox(
              width: width,
              child: Text('${i + 1}', textAlign: TextAlign.right, style: style.copyWith(color: p.subText)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(lines[i], style: style, maxLines: 1, softWrap: false, overflow: TextOverflow.clip)),
          ],
        ),
      ),
    );
  }
}
