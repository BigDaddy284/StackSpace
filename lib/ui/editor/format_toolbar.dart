import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../editor/blocks.dart';

/// What the floating toolbar can do to the selected text.
enum FormatAction { bold, italic, strike, code, link }

/// The kinds a text block can be turned into, with their labels.
const turnIntoKinds = <(BlockKind, int, String, IconData)>[
  (BlockKind.paragraph, 0, 'Text', Icons.notes),
  (BlockKind.heading, 1, 'Heading 1', Icons.title),
  (BlockKind.heading, 2, 'Heading 2', Icons.title),
  (BlockKind.heading, 3, 'Heading 3', Icons.title),
  (BlockKind.bullet, 0, 'Bulleted list', Icons.format_list_bulleted),
  (BlockKind.numbered, 0, 'Numbered list', Icons.format_list_numbered),
  (BlockKind.todo, 0, 'To-do list', Icons.check_box_outlined),
  (BlockKind.quote, 0, 'Quote', Icons.format_quote),
  (BlockKind.code, 0, 'Code block', Icons.code),
];

String turnIntoLabel(Block block) {
  for (final (kind, level, label, _) in turnIntoKinds) {
    if (kind == block.kind && (kind != BlockKind.heading || level == block.level.clamp(1, 3))) return label;
  }
  return 'Text';
}

/// The small toolbar that floats above a text selection: bold, italic,
/// strikethrough, code, link, and a "turn into" menu for the block.
class FormatToolbar extends StatelessWidget {
  const FormatToolbar({
    super.key,
    required this.anchor,
    required this.block,
    required this.onAction,
    required this.onTurnInto,
  });

  /// The selection's rectangle in overlay coordinates.
  final Rect anchor;
  final Block block;
  final ValueChanged<FormatAction> onAction;
  final void Function(BlockKind kind, int level) onTurnInto;

  static const height = 34.0;
  static const _margin = 8.0;

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    final screen = MediaQuery.sizeOf(context);
    const width = 300.0;
    final above = anchor.top - 6 - height;
    final top = above >= _margin ? above : anchor.bottom + 6;
    final left = anchor.left.clamp(_margin, (screen.width - width - _margin).clamp(_margin, double.infinity));
    return Positioned(
      left: left,
      top: top.clamp(_margin, (screen.height - height - _margin).clamp(_margin, double.infinity)),
      height: height,
      child: TapRegion(
        // Clicks here count as inside the text field, so it keeps focus and
        // its selection.
        groupId: EditableText,
        child: Semantics(
          container: true,
          label: 'Formatting toolbar',
          child: Material(
            color: palette.panel,
            elevation: 6,
            shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(7),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: palette.barBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _TurnIntoButton(block: block, onTurnInto: onTurnInto),
                  _divider(palette),
                  _ToolButton(
                      tooltip: 'Bold (Ctrl+B)', icon: Icons.format_bold, onPressed: () => onAction(FormatAction.bold)),
                  _ToolButton(
                      tooltip: 'Italic (Ctrl+I)',
                      icon: Icons.format_italic,
                      onPressed: () => onAction(FormatAction.italic)),
                  _ToolButton(
                      tooltip: 'Strikethrough (Ctrl+Shift+X)',
                      icon: Icons.strikethrough_s,
                      onPressed: () => onAction(FormatAction.strike)),
                  _ToolButton(
                      tooltip: 'Inline code (Ctrl+E)', icon: Icons.code, onPressed: () => onAction(FormatAction.code)),
                  _ToolButton(tooltip: 'Link (Ctrl+K)', icon: Icons.link, onPressed: () => onAction(FormatAction.link)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider(StackPalette palette) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Container(width: 1, height: 18, color: palette.barBorder));
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.tooltip, required this.icon, required this.onPressed});
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onPressed,
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(5),
          hoverColor: palette.hover,
          child: SizedBox(width: 30, height: 28, child: Icon(icon, size: 18, color: palette.text)),
        ),
      ),
    );
  }
}

class _TurnIntoButton extends StatelessWidget {
  const _TurnIntoButton({required this.block, required this.onTurnInto});
  final Block block;
  final void Function(BlockKind kind, int level) onTurnInto;

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    return Tooltip(
      message: 'Turn into',
      child: Semantics(
        button: true,
        label: 'Turn into, now ${turnIntoLabel(block)}',
        child: InkWell(
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(5),
          hoverColor: palette.hover,
          onTap: () async {
            final box = context.findRenderObject() as RenderBox;
            final origin = box.localToGlobal(Offset(0, box.size.height + 4));
            final choice = await showTurnIntoMenu(context, origin, block);
            if (choice != null) onTurnInto(choice.$1, choice.$2);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(turnIntoLabel(block),
                  style: TextStyle(color: palette.text, fontSize: StackType.hint, fontWeight: FontWeight.w600)),
              Icon(Icons.expand_more, size: 15, color: palette.subText),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A menu of the kinds a block can become. Returns the chosen kind and level.
Future<(BlockKind, int)?> showTurnIntoMenu(BuildContext context, Offset at, Block block) {
  final palette = StackColors.of(context);
  final current = turnIntoLabel(block);
  return showMenu<(BlockKind, int)>(
    context: context,
    position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
    items: [
      for (final (kind, level, label, icon) in turnIntoKinds)
        PopupMenuItem(
          value: (kind, level),
          height: 36,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: palette.subText),
            const SizedBox(width: 10),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            if (label == current) ...[const SizedBox(width: 16), Icon(Icons.check, size: 16, color: palette.accentA)],
          ]),
        ),
    ],
  );
}
