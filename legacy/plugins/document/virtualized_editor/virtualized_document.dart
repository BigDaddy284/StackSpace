import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Virtualized document rendering system to handle large documents efficiently
class VirtualizedDocument {
  /// The total number of lines in the document
  final int totalLines;

  /// The maximum number of lines to render at once (visible area)
  final int maxVisibleLines;

  /// Current viewport start position
  int _viewportStart = 0;

  /// Current viewport end position
  int _viewportEnd = 0;

  /// Cache for rendered content chunks
  final Map<int, List<String>> _contentCache = {};

  VirtualizedDocument({
    required this.totalLines,
    this.maxVisibleLines = 100,
  }) {
    // Initialize viewport to show first section
    _updateViewport(0);
  }

  /// Get the current viewport start position
  int get viewportStart => _viewportStart;

  /// Get the current viewport end position
  int get viewportEnd => _viewportEnd;

  /// Update viewport to show content around the given line index
  void updateViewport(int targetLineIndex) {
    final newStart = math.max(0, targetLineIndex - maxVisibleLines ~/ 2);
    final newEnd = math.min(totalLines, newStart + maxVisibleLines);

    if (newStart != _viewportStart || newEnd != _viewportEnd) {
      _updateViewport(newStart);
    }
  }

  /// Update viewport boundaries
  void _updateViewport(int start) {
    _viewportStart = start;
    _viewportEnd = math.min(totalLines, start + maxVisibleLines);
  }

  /// Get lines in current viewport
  List<String> getVisibleLines() {
    final lines = <String>[];

    // Load content from cache or generate if not cached
    for (int i = _viewportStart; i < _viewportEnd; i++) {
      if (_contentCache.containsKey(i)) {
        lines.add(_contentCache[i]!);
      } else {
        // Simulate loading line content
        final lineContent = "Line ${i + 1}: This is sample content for demonstration purposes";
        lines.add(lineContent);
        _contentCache[i] = lineContent;
      }
    }

    return lines;
  }

  /// Load a specific range of lines into cache
  void loadRange(int start, int end) {
    // In a real implementation, this would fetch from storage
    for (int i = start; i < math.min(end, totalLines); i++) {
      if (!_contentCache.containsKey(i)) {
        _contentCache[i] = "Line ${i + 1}: Sample content";
      }
    }
  }

  /// Clear cache to free memory
  void clearCache() {
    _contentCache.clear();
  }

  /// Get document statistics
  Map<String, dynamic> getStats() {
    return {
      'total_lines': totalLines,
      'viewport_start': _viewportStart,
      'viewport_end': _viewportEnd,
      'visible_lines': _viewportEnd - _viewportStart,
      'cached_chunks': _contentCache.length,
    };
  }
}