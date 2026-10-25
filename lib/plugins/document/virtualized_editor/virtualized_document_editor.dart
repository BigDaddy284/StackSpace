import 'package:flutter/material.dart';
import 'virtualized_renderer.dart';

/// Virtualized document editor widget that integrates with Flutter's scroll system
class VirtualizedDocumentEditor extends StatefulWidget {
  final int totalLines;
  final int chunkSize;
  final TextStyle? textStyle;
  final ScrollController? scrollController;
  final VoidCallback? onContentChanged;

  const VirtualizedDocumentEditor({
    Key? key,
    required this.totalLines,
    this.chunkSize = 100,
    this.textStyle,
    this.scrollController,
    this.onContentChanged,
  }) : super(key: key);

  @override
  State<VirtualizedDocumentEditor> createState() => _VirtualizedDocumentEditorState();
}

class _VirtualizedDocumentEditorState extends State<VirtualizedDocumentEditor> {
  late VirtualizedRenderer _renderer;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _renderer = VirtualizedRenderer(
      totalLines: widget.totalLines,
      chunkSize: widget.chunkSize,
    );
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
    if (!_scrollController.hasClients) return;

    // Calculate which lines are currently visible based on scroll position
    final viewport = _scrollController.position;
    final lineHeight = widget.textStyle?.fontSize ?? 20.0;

    // Estimate first visible line based on scroll offset
    final firstVisibleLine = (viewport.pixels / lineHeight).toInt();

    // Update viewport to show relevant content
    if (firstVisibleLine >= 0) {
      _renderer.updateViewport(firstVisibleLine);

      // Trigger rebuild to update visible content
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ScrollConfiguration(
        behavior: const ScrollBehavior().copyWith(scrollbars: false),
        child: ListView.builder(
          controller: _scrollController,
          itemCount: widget.totalLines,
          itemBuilder: (context, index) {
            // Only build visible lines to optimize performance
            final content = _renderer.getLineContent(index);

            if (content == null) {
              // Placeholder for loading or unavailable content
              return Container(
                height: 20.0,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: const Text(
                  'Loading...',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }

            return Container(
              height: 20.0,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                content,
                style: widget.textStyle ?? const TextStyle(fontSize: 14),
              ),
            );
          },
        ),
      ),
    );
  }
}