import 'package:flutter/material.dart';

import '../editor/page_editor_controller.dart';

const monoFont = 'Consolas';
const monoFallback = ['Cascadia Mono', 'Menlo', 'DejaVu Sans Mono', 'monospace'];

class EditorPane extends StatelessWidget {
  const EditorPane({super.key, required this.controller, required this.locked, required this.onNewPage});

  final PageEditorController controller;

  /// True while the assistant is working, so the user's typing can't race its edits.
  final bool locked;
  final VoidCallback onNewPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final path = controller.path;
        if (path == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.description_outlined, size: 40, color: scheme.outline),
                const SizedBox(height: 12),
                Text(controller.error ?? 'Open a page from the sidebar.', style: theme.textTheme.bodyLarge),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: onNewPage, icon: const Icon(Icons.add), label: const Text('New page')),
              ],
            ),
          );
        }
        final (line, column) = controller.cursor;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Expanded(
                    child: Text(path, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                  ),
                  if (locked)
                    _Badge(icon: Icons.lock_outline, text: 'Assistant is working', color: scheme.tertiary),
                  if (controller.isLarge)
                    _Badge(icon: Icons.visibility_outlined, text: 'Large file: read-only', color: scheme.tertiary),
                  if (controller.error != null) _Badge(icon: Icons.error_outline, text: controller.error!, color: scheme.error),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: controller.isLarge
                  ? _LargeFileView(lines: controller.largeLines!)
                  : TextField(
                      controller: controller.text,
                      readOnly: locked,
                      expands: true,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(fontFamily: monoFont, fontFamilyFallback: monoFallback, fontSize: 14, height: 1.45),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.fromLTRB(20, 14, 20, 80),
                      ),
                    ),
            ),
            Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              color: scheme.surfaceContainerLow,
              child: Row(
                children: [
                  Text(
                    controller.isLarge ? '${controller.largeLines!.length} lines' : 'Ln $line, Col $column',
                    style: theme.textTheme.labelSmall,
                  ),
                  const Spacer(),
                  Text(controller.dirty ? 'Unsaved' : 'Saved', style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
        ]),
      );
}

/// Shows a huge file one line per row, building only the rows on screen.
class _LargeFileView extends StatelessWidget {
  const _LargeFileView({required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.outline;
    final width = '${lines.length}'.length * 9.0 + 16;
    const style = TextStyle(fontFamily: monoFont, fontFamilyFallback: monoFallback, fontSize: 14, height: 1.45);
    return Scrollbar(
      child: ListView.builder(
        itemExtent: 20.3,
        padding: const EdgeInsets.symmetric(vertical: 10),
        itemCount: lines.length,
        itemBuilder: (context, i) => Row(
          children: [
            SizedBox(
              width: width,
              child: Text('${i + 1}', textAlign: TextAlign.right, style: style.copyWith(color: muted)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(lines[i], style: style, maxLines: 1, softWrap: false, overflow: TextOverflow.clip)),
          ],
        ),
      ),
    );
  }
}
