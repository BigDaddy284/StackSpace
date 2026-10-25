/// Represents a chunk of document content for virtualized rendering
class DocumentChunk {
  /// The starting line index of this chunk
  final int startIndex;

  /// The ending line index of this chunk
  final int endIndex;

  /// The actual content in this chunk
  final List<String> content;

  /// Whether this chunk is currently loaded and cached
  bool isLoaded;

  /// Timestamp when this chunk was last accessed (for cache management)
  DateTime? lastAccessed;

  DocumentChunk({
    required this.startIndex,
    required this.endIndex,
    required this.content,
    this.isLoaded = false,
  });

  /// Get the line at a specific index within this chunk
  String? getLine(int index) {
    if (index >= startIndex && index < endIndex) {
      final localIndex = index - startIndex;
      return content.length > localIndex ? content[localIndex] : null;
    }
    return null;
  }

  /// Update access time for cache management
  void touch() {
    lastAccessed = DateTime.now();
  }

  /// Check if this chunk contains the specified line
  bool containsLine(int lineIndex) {
    return lineIndex >= startIndex && lineIndex < endIndex;
  }

  /// Get the number of lines in this chunk
  int get lineCount => endIndex - startIndex;
}