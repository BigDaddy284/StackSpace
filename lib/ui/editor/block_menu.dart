import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../editor/blocks.dart';
import 'format_toolbar.dart';

/// What the block menu can do with a block.
enum BlockAction { turnInto, duplicate, moveUp, moveDown, delete }

/// The menu behind a block's handle. Returns the action, with the kind and
/// level when the block is to be turned into something else.
Future<(BlockAction, (BlockKind, int)?)?> showBlockMenu(
  BuildContext context,
  Offset at,
  Block block, {
  required bool canMoveUp,
  required bool canMoveDown,
}) async {
  final palette = StackColors.of(context);
  final action = await showMenu<BlockAction>(
    context: context,
    position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
    items: [
      if (block.isText)
        PopupMenuItem(
          value: BlockAction.turnInto,
          height: 36,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.swap_horiz, size: 17, color: palette.subText),
            const SizedBox(width: 10),
            Flexible(child: Text('Turn into (${turnIntoLabel(block)})', overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 24),
            Icon(Icons.chevron_right, size: 16, color: palette.subText),
          ]),
        ),
      PopupMenuItem(
        value: BlockAction.duplicate,
        height: 36,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.copy_outlined, size: 17, color: palette.subText),
          const SizedBox(width: 10),
          const Text('Duplicate'),
        ]),
      ),
      PopupMenuItem(
        value: BlockAction.moveUp,
        enabled: canMoveUp,
        height: 36,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.arrow_upward, size: 17, color: palette.subText),
          const SizedBox(width: 10),
          const Flexible(child: Text('Move up', overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 24),
          Flexible(
              child: Text('Ctrl+Shift+↑',
                  style: TextStyle(color: palette.subText, fontSize: StackType.hint), overflow: TextOverflow.ellipsis)),
        ]),
      ),
      PopupMenuItem(
        value: BlockAction.moveDown,
        enabled: canMoveDown,
        height: 36,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.arrow_downward, size: 17, color: palette.subText),
          const SizedBox(width: 10),
          const Flexible(child: Text('Move down', overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 24),
          Flexible(
              child: Text('Ctrl+Shift+↓',
                  style: TextStyle(color: palette.subText, fontSize: StackType.hint), overflow: TextOverflow.ellipsis)),
        ]),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: BlockAction.delete,
        height: 36,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.delete_outline, size: 17, color: palette.error),
          const SizedBox(width: 10),
          Text('Delete', style: TextStyle(color: palette.error)),
        ]),
      ),
    ],
  );
  if (action == null) return null;
  if (action != BlockAction.turnInto) return (action, null);
  if (!context.mounted) return null;
  final choice = await showTurnIntoMenu(context, at, block);
  return choice == null ? null : (action, choice);
}

/// The handle at the left of a block: shows when the row is hovered or the
/// block has focus, and opens the block menu.
class BlockHandle extends StatefulWidget {
  const BlockHandle(
      {super.key, required this.hover, required this.focusNode, required this.label, required this.onOpen});
  final ValueNotifier<bool> hover;
  final FocusNode focusNode;
  final String label;
  final ValueChanged<Offset> onOpen;

  static const width = 24.0;
  static const height = 20.0;

  @override
  State<BlockHandle> createState() => _BlockHandleState();
}

class _BlockHandleState extends State<BlockHandle> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.hover, widget.focusNode]),
      builder: (context, _) {
        final visible = _over || widget.hover.value || widget.focusNode.hasFocus;
        return SizedBox(
          width: BlockHandle.width,
          height: BlockHandle.height,
          child: Tooltip(
            message: visible ? 'Block options' : '',
            child: Semantics(
              button: true,
              label: widget.label,
              child: MouseRegion(
                onEnter: (_) => setState(() => _over = true),
                onExit: (_) => setState(() => _over = false),
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => widget.onOpen(d.globalPosition),
                  child: Opacity(
                    opacity: visible ? (_over ? 1 : 0.55) : 0,
                    child: Icon(Icons.drag_indicator, size: 18, color: palette.subText),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
