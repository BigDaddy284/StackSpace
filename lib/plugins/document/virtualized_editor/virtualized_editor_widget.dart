import 'package:flutter/material.dart';
import 'virtualized_document.dart';

/// Virtualized editor widget that renders only visible content
class VirtualizedEditorWidget extends StatefulWidget {
  final VirtualizedDocument document;
  final TextStyle? textStyle;
  final ScrollController? scrollController;

  const VirtualizedEditorWidget({
    Key? key,
    required this.document,
    this.textStyle,
    this.scrollController,
  }) : super(key: key);

  @override
  State<VirtualizedEditorWidget> createState() => _VirtualizedEditorWidgetState();
}

class _VirtualizedEditorWidgetState extends State<VirtualizedEditorWidget> {
  late VirtualizedDocument _document;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _document = widget.document;
    _scrollController = widget.scrollController ?? ScrollController();

    // Listen to scroll events to update viewport
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    // Calculate which lines are currently visible based on scroll position
    final viewport = _scrollController.position;
    final lineHeight = widget.textStyle?.fontSize ?? 20.0;
    final visibleLines = (viewport.viewportDimension / lineHeight).toInt();

    // Update viewport to show relevant content
    if (visibleLines > 0) {
      final firstVisibleLine = (viewport.pixels / lineHeight).toInt();
      _document.updateViewport(firstVisibleLine);

      // Trigger rebuild to update visible content
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _document.getVisibleLines();

    return ScrollConfiguration(
      behavior: const ScrollBehavior().copyWith(scrollbars: false),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _document.totalLines,
        itemBuilder: (context, index) {
          if (index >= lines.length) {
            return Container(); // Empty placeholder for invisible content
          }

          return Text(
            lines[index],
            style: widget.textStyle ?? const TextStyle(fontSize: 16),
          );
        },
      ),
    );
  }
}