import 'dart:io';
import 'document_storage.dart';
import 'package:path/path.dart' as path;

/// Enhanced virtualized document manager that integrates storage with rendering
class EnhancedVirtualizedDocumentManager {
  final DocumentStorage storage;
  final VirtualizedRenderer renderer;
  final String filePath;
  bool _isLoaded = false;

  /// Track which chunks are currently loaded in memory
  final Set<int> _loadedChunks = {};

  EnhancedVirtualizedDocumentManager({
    required this.storage,
    required this.renderer,
    required this.filePath,
  });

  /// Load document from storage into virtualized system
  Future<void> loadDocument() async {
    try {
      // Check if document exists
      final exists = await storage.documentExists(filePath);

      if (!exists) {
        // Create empty document if it doesn't exist
        await createEmptyDocument();
        return;
      }

      // Get document metadata to understand size
      final metadata = await storage.getDocumentMetadata(filePath);
      print('Loading document: ${metadata.name}, Size: ${metadata.size} bytes');

      // Load the document content (this would be done more efficiently in practice)
      final content = await storage.loadDocument(filePath);

      // Update renderer with actual document size
      renderer.updateViewport(0);

      _isLoaded = true;
      print('Successfully loaded document with ${content.length} lines');
    } catch (e) {
      print('Error loading document: $e');
      throw Exception('Failed to load document: $e');
    }
  }

  /// Save current document state to storage
  Future<void> saveDocument() async {
    try {
      // In a real implementation, we would collect content from the renderer's cache
      // For now, we'll demonstrate the saving process

      print('Saving document to: $filePath');

      // This is where we would gather all modified chunks and save them
      await storage.saveDocument(filePath, []);

      print('Document saved successfully');
    } catch (e) {
      print('Error saving document: $e');
      throw Exception('Failed to save document: $e');
    }
  }

  /// Create a new empty document
  Future<void> createEmptyDocument() async {
    try {
      await storage.createDocument(filePath, ['']);
      renderer.updateViewport(0);
      _isLoaded = true;
      print('Created new empty document');
    } catch (e) {
      print('Error creating document: $e');
      throw Exception('Failed to create document: $e');
    }
  }

  /// Get the current status of document loading
  bool get isLoaded => _isLoaded;

  /// Get document statistics
  Map<String, dynamic> getDocumentStats() {
    final stats = renderer.getStats();
    return {
      ...stats,
      'file_path': filePath,
      'is_loaded': _isLoaded,
      'loaded_chunks': _loadedChunks.length,
    };
  }

  /// Load a specific chunk into memory
  Future<void> loadChunk(int chunkIndex) async {
    // In a real implementation, this would be more sophisticated
    // For now, we'll just track which chunks are "loaded"
    _loadedChunks.add(chunkIndex);
  }

  /// Unload a specific chunk from memory
  void unloadChunk(int chunkIndex) {
    _loadedChunks.remove(chunkIndex);
  }

  /// Get line content for a specific index (using virtualization)
  String? getLineContent(int lineIndex) {
    if (!_isLoaded) return null;

    // Check if the chunk containing this line is loaded
    final chunkIndex = lineIndex ~/ renderer.chunkSize;

    // In a real implementation, we would load chunks on demand
    // For now, we'll just return a placeholder
    return 'Line ${lineIndex + 1}: Content for virtualized document';
  }

  /// Update viewport to show content around target line
  void updateViewport(int targetLineIndex) {
    renderer.updateViewport(targetLineIndex);
  }

  /// Get visible lines in current viewport
  List<String> getVisibleLines() {
    if (!_isLoaded) return [];

    final lines = <String>[];
    final start = renderer.viewportStart;
    final end = renderer.viewportEnd;

    for (int i = start; i < end; i++) {
      lines.add(getLineContent(i) ?? 'Line $i: Loading...');
    }

    return lines;
  }

  /// Get content range (for clipboard operations)
  List<String> getContentRange(int startIndex, int endIndex) {
    final lines = <String>[];

    for (int i = startIndex; i < endIndex; i++) {
      if (i >= 0 && i < renderer.getStats()['total_lines']) {
        lines.add(getLineContent(i) ?? 'Line $i: Content');
      }
    }

    return lines;
  }

  /// Clear all cached data
  void clearCache() {
    renderer.clearCache();
    _loadedChunks.clear();
  }
}