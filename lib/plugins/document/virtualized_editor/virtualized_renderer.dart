import 'dart:math' as math;
import 'document_chunk.dart';

/// Virtualized document renderer that efficiently handles large documents
class VirtualizedRenderer {
  /// Total number of lines in the document
  final int totalLines;

  /// Maximum number of lines to keep in memory at once (chunk size)
  final int chunkSize;

  /// Maximum number of chunks to keep cached
  final int maxCachedChunks;

  /// Current viewport information
  int _viewportStart = 0;
  int _viewportEnd = 0;

  /// Cached document chunks
  final Map<int, DocumentChunk> _chunkCache = {};

  /// Recently accessed chunks (for LRU cache management)
  final List<int> _recentlyAccessed = [];

  VirtualizedRenderer({
    required this.totalLines,
    this.chunkSize = 100,
    this.maxCachedChunks = 5,
  }) {
    // Initialize viewport to show first section
    _updateViewport(0);
  }

  /// Get current viewport start position
  int get viewportStart => _viewportStart;

  /// Get current viewport end position
  int get viewportEnd => _viewportEnd;

  /// Update viewport to show content around the given line index
  void updateViewport(int targetLineIndex) {
    final newStart = math.max(0, targetLineIndex - chunkSize ~/ 2);
    final newEnd = math.min(totalLines, newStart + chunkSize);

    if (newStart != _viewportStart || newEnd != _viewportEnd) {
      _updateViewport(newStart);
      _loadRequiredChunks();
    }
  }

  /// Update viewport boundaries
  void _updateViewport(int start) {
    _viewportStart = start;
    _viewportEnd = math.min(totalLines, start + chunkSize);
  }

  /// Load chunks needed for current viewport
  void _loadRequiredChunks() {
    // Determine which chunks are needed for the current viewport
    final startChunkIndex = _viewportStart ~/ chunkSize;
    final endChunkIndex = (_viewportEnd - 1) ~/ chunkSize;

    for (int i = startChunkIndex; i <= endChunkIndex; i++) {
      _loadChunk(i);
    }

    // Clean up excess cached chunks
    _manageCache();
  }

  /// Load a specific chunk into memory
  void _loadChunk(int chunkIndex) {
    if (_chunkCache.containsKey(chunkIndex)) {
      // Update access time for existing chunk
      _chunkCache[chunkIndex]?.touch();
      _updateRecentlyAccessed(chunkIndex);
      return;
    }

    // Create new chunk with sample content (in real implementation, this would load from storage)
    final startIndex = chunkIndex * chunkSize;
    final endIndex = math.min(startIndex + chunkSize, totalLines);

    final content = <String>[];
    for (int i = startIndex; i < endIndex; i++) {
      content.add("Line ${i + 1}: Content for line ${i + 1}");
    }

    final chunk = DocumentChunk(
      startIndex: startIndex,
      endIndex: endIndex,
      content: content,
      isLoaded: true,
    );

    _chunkCache[chunkIndex] = chunk;
    _updateRecentlyAccessed(chunkIndex);
  }

  /// Manage cache by removing least recently used chunks
  void _manageCache() {
    if (_chunkCache.length <= maxCachedChunks) return;

    // Remove oldest chunks (not accessed recently)
    final sortedChunks = _recentlyAccessed.map((index) => _chunkCache[index])
        .where((chunk) => chunk != null)
        .toList();

    // Keep only the most recently used chunks
    while (_chunkCache.length > maxCachedChunks) {
      if (sortedChunks.isNotEmpty) {
        final chunkToRemove = sortedChunks.removeLast();
        if (chunkToRemove != null) {
          _chunkCache.remove(chunkToRemove.startIndex ~/ chunkSize);
          _recentlyAccessed.remove(chunkToRemove.startIndex ~/ chunkSize);
        }
      } else {
        // Fallback: remove first chunk
        final firstKey = _chunkCache.keys.first;
        _chunkCache.remove(firstKey);
        _recentlyAccessed.remove(firstKey);
      }
    }
  }

  /// Update recently accessed list
  void _updateRecentlyAccessed(int chunkIndex) {
    _recentlyAccessed.remove(chunkIndex);
    _recentlyAccessed.add(chunkIndex);
  }

  /// Get content for a specific line index
  String? getLineContent(int lineIndex) {
    final chunkIndex = lineIndex ~/ chunkSize;

    if (_chunkCache.containsKey(chunkIndex)) {
      final chunk = _chunkCache[chunkIndex]!;
      chunk.touch();
      _updateRecentlyAccessed(chunkIndex);
      return chunk.getLine(lineIndex);
    }

    // Load the chunk and try again
    _loadChunk(chunkIndex);
    return _chunkCache[chunkIndex]?.getLine(lineIndex);
  }

  /// Get lines for current viewport
  List<String> getVisibleLines() {
    final lines = <String>[];

    for (int i = _viewportStart; i < _viewportEnd; i++) {
      final content = getLineContent(i);
      if (content != null) {
        lines.add(content);
      }
    }

    return lines;
  }

  /// Get document statistics
  Map<String, dynamic> getStats() {
    return {
      'total_lines': totalLines,
      'viewport_start': _viewportStart,
      'viewport_end': _viewportEnd,
      'visible_lines': _viewportEnd - _viewportStart,
      'chunks_cached': _chunkCache.length,
      'chunk_size': chunkSize,
      'max_cached_chunks': maxCachedChunks,
    };
  }

  /// Clear all cached chunks
  void clearCache() {
    _chunkCache.clear();
    _recentlyAccessed.clear();
  }
}