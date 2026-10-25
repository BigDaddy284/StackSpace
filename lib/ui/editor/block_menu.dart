import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../editor/blocks.dart';
import 'format_toolbar.dart';

/// What the block menu can do with a block.
enum BlockAction { turnInto, duplicate, moveUp, moveDown, collapse, expand, delete }

/// The menu behind a block's handle. Returns the action, with the kind and
/// level when the block is to be turned into something else.
Future<(BlockAction, (BlockKind, int)?)?> showBlockMenu(
  BuildContext context,
  Offset at,
  Block block, {
  required bool canMoveUp,
  required bool canMoveDown,
  bool? collapsed,
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
      if (collapsed != null)
        PopupMenuItem(
          value: collapsed ? BlockAction.expand : BlockAction.collapse,
          height: 36,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(collapsed ? Icons.unfold_more : Icons.unfold_less, size: 17, color: palette.subText),
            const SizedBox(width: 10),
            Text(collapsed ? 'Expand section' : 'Collapse section'),
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
  const BlockHandle({
    super.key,
    required this.hover,
    required this.focusNode,
    required this.label,
    required this.onOpen,
    this.dragData,
    this.dragFeedback,
    this.onDragStarted,
    this.onDragUpdate,
    this.onDragEnd,
  });
  final ValueNotifier<bool> hover;
  final FocusNode focusNode;
  final String label;
  final ValueChanged<Offset> onOpen;

  /// When set, the handle can be dragged to move the block: [dragData] goes
  /// to the row it is dropped on and [dragFeedback] follows the pointer.
  final int? dragData;
  final Widget? dragFeedback;
  final VoidCallback? onDragStarted;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragEnd;

  static const width = 24.0;
  static const height = 24.0;

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
        Offset? down;
        final Widget handle = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => down = d.globalPosition,
          onTap: () => widget.onOpen(down ?? Offset.zero),
          child: Opacity(
            opacity: visible ? (_over ? 1 : 0.55) : 0,
            child: Icon(Icons.drag_indicator, size: 18, color: palette.subText),
          ),
        );
        final data = widget.dragData;
        return SizedBox(
          width: BlockHandle.width,
          height: BlockHandle.height,
          child: Tooltip(
            message: visible ? (data == null ? 'Block options' : 'Block options; drag to move') : '',
            child: Semantics(
              button: true,
              label: widget.label,
              child: MouseRegion(
                onEnter: (_) => setState(() => _over = true),
                onExit: (_) => setState(() => _over = false),
                cursor: data == null ? SystemMouseCursors.click : SystemMouseCursors.grab,
                child: data == null
                    ? handle
                    : Draggable<int>(
                        data: data,
                        dragAnchorStrategy: pointerDragAnchorStrategy,
                        feedback: widget.dragFeedback ?? const SizedBox.shrink(),
                        childWhenDragging: Opacity(opacity: 0.3, child: handle),
                        onDragStarted: widget.onDragStarted,
                        onDragUpdate: (d) => widget.onDragUpdate?.call(d.globalPosition),
                        onDragEnd: (_) => widget.onDragEnd?.call(),
                        onDraggableCanceled: (_, __) => widget.onDragEnd?.call(),
                        child: handle,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The chevron beside a heading that folds or unfolds its section. Shown on
/// hover or focus, and always while the section is folded.
class SectionToggle extends StatefulWidget {
  const SectionToggle({
    super.key,
    required this.hover,
    required this.focusNode,
    required this.collapsed,
    required this.hiddenCount,
    required this.onToggle,
  });
  final ValueNotifier<bool> hover;
  final FocusNode focusNode;
  final bool collapsed;
  final int hiddenCount;
  final VoidCallback onToggle;

  static const size = 24.0;

  @override
  State<SectionToggle> createState() => _SectionToggleState();
}

class _SectionToggleState extends State<SectionToggle> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.hover, widget.focusNode]),
      builder: (context, _) {
        final visible = widget.collapsed || _over || widget.hover.value || widget.focusNode.hasFocus;
        final label = widget.collapsed
            ? 'Expand section, ${widget.hiddenCount} hidden block${widget.hiddenCount == 1 ? '' : 's'}'
            : 'Collapse section';
        return SizedBox(
          width: SectionToggle.size,
          height: SectionToggle.size,
          child: Tooltip(
            message: visible ? label : '',
            child: Opacity(
              opacity: visible ? (_over || widget.collapsed ? 1 : 0.55) : 0,
              child: Semantics(
                button: true,
                label: label,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _over = true),
                  onExit: (_) => setState(() => _over = false),
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onToggle,
                    child: Icon(widget.collapsed ? Icons.chevron_right : Icons.expand_more,
                        size: 18, color: widget.collapsed ? palette.accentA : palette.subText),
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
