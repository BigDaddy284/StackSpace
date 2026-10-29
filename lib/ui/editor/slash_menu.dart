import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../editor/slash_commands.dart';

/// The pop-up list of commands shown after typing `/` in a block.
///
/// It sits just under the slash (or above it when there is no room below)
/// and clamps to the window edges.
class SlashMenuPanel extends StatelessWidget {
  const SlashMenuPanel({
    super.key,
    required this.anchor,
    required this.items,
    required this.selected,
    required this.query,
    required this.onHover,
    required this.onPick,
  });

  /// The slash character's rectangle in overlay coordinates.
  final Rect anchor;
  final List<SlashCommand> items;
  final int selected;
  final String query;
  final ValueChanged<int> onHover;
  final ValueChanged<int> onPick;

  static const width = 300.0;
  static const maxHeight = 380.0;
  static const rowHeight = 46.0;
  static const headerHeight = 26.0;
  static const _margin = 8.0;

  /// Height the panel will take for [items].
  static double heightFor(List<SlashCommand> items) {
    if (items.isEmpty) return 56;
    final categories = items.map((c) => c.category).toSet().length;
    return (categories * headerHeight + items.length * rowHeight + 12).clamp(0, maxHeight).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    final screen = MediaQuery.sizeOf(context);
    final height = heightFor(items);
    final below = anchor.bottom + 4;
    final flip = below + height > screen.height - _margin && anchor.top - 4 - height >= _margin;
    final top = flip ? anchor.top - 4 - height : below;
    final left = anchor.left.clamp(_margin, (screen.width - width - _margin).clamp(_margin, double.infinity));
    return Positioned(
      left: left,
      top: top.clamp(_margin, (screen.height - height - _margin).clamp(_margin, double.infinity)),
      width: width,
      height: height,
      child: TapRegion(
        // Clicks here count as inside the text field, so it keeps focus.
        groupId: EditableText,
        child: Semantics(
          container: true,
          label: 'Block commands',
          child: Material(
            color: palette.panel,
            elevation: 12,
            shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: palette.barBorder),
              ),
              child: items.isEmpty ? _empty(palette) : _list(palette),
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(StackPalette palette) => Center(
        child: Text('No commands match "$query"', style: TextStyle(color: palette.subText, fontSize: StackType.button)),
      );

  Widget _list(StackPalette palette) {
    final children = <Widget>[];
    String? category;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.category != category) {
        category = item.category;
        children.add(SizedBox(
          height: headerHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(category.toUpperCase(),
                style: TextStyle(
                    color: palette.subText,
                    fontSize: StackType.section,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6)),
          ),
        ));
      }
      children.add(_SlashRow(
        key: ValueKey('slash-${item.id}'),
        item: item,
        selected: i == selected,
        onHover: () => onHover(i),
        onTap: () => onPick(i),
      ));
    }
    return ListView(
      key: const PageStorageKey('slash-menu'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: children,
    );
  }
}

class _SlashRow extends StatefulWidget {
  const _SlashRow({super.key, required this.item, required this.selected, required this.onHover, required this.onTap});
  final SlashCommand item;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  State<_SlashRow> createState() => _SlashRowState();
}

class _SlashRowState extends State<_SlashRow> {
  /// Whether the mouse is over this row. A row picked by hovering is already
  /// on screen, and scrolling it to the middle would slide another row under
  /// the mouse, which would pick that one and scroll again: the list chased
  /// the pointer. Only arrow keys scroll the list.
  bool _hovered = false;

  @override
  void didUpdateWidget(_SlashRow old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected && !_hovered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 80));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        widget.onHover();
      },
      onExit: (_) => _hovered = false,
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: '${widget.item.label}, ${widget.item.description}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: SlashMenuPanel.rowHeight,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: widget.selected ? palette.checkedGradient : null,
            ),
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: palette.control,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: palette.controlBorder),
                ),
                child: Icon(widget.item.icon, size: 17, color: palette.text),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.item.label,
                        style: TextStyle(color: palette.text, fontSize: StackType.button, fontWeight: FontWeight.w600)),
                    Text(widget.item.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.subText, fontSize: StackType.hint)),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
