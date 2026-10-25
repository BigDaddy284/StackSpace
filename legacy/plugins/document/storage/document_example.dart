import 'dart:io';
import 'document_storage.dart';
import 'virtualized_document_manager.dart';
import 'package:path/path.dart' as path;

/// Example usage of the virtualized document system
class DocumentExample {
  static Future<void> runExample() async {
    print('=== Virtualized Document System Example ===\n');

    // Create a temporary directory for our example
    final tempDir = Directory.systemTemp.createTempSync('appflowy_example_');
    final testFilePath = path.join(tempDir.path, 'example_document.txt');

    try {
      // 1. Create document storage with base path
      final storage = FileDocumentStorage(basePath: tempDir.path);

      // 2. Create a virtualized renderer (simulating a large document)
      final renderer = VirtualizedRenderer(
        totalLines: 10000, // Simulate a large document
        chunkSize: 100,
        maxCachedChunks: 3,
      );

      // 3. Create document manager
      final docManager = EnhancedVirtualizedDocumentManager(
        storage: storage,
        renderer: renderer,
        filePath: testFilePath,
      );

      print('Created virtualized document system');
      print('Document path: $testFilePath');
      print('Total lines: ${renderer.getStats()['total_lines']}');
      print('Chunk size: ${renderer.getStats()['chunk_size']}');
      print('Max cached chunks: ${renderer.getStats()['max_cached_chunks']}\n');

      // 4. Create a sample document with test content
      final sampleContent = <String>[];
      for (int i = 0; i < 100; i++) {
        sampleContent.add('Line ${i + 1}: This is example content for testing virtualized rendering performance.');
      }

      // Save the sample content
      await storage.createDocument(testFilePath, sampleContent);
      print('Created sample document with ${sampleContent.length} lines');

      // 5. Load the document
      await docManager.loadDocument();
      print('Document loaded successfully');

      // 6. Show document statistics
      final stats = docManager.getDocumentStats();
      print('\nDocument Statistics:');
      print('  - File path: ${stats['file_path']}');
      print('  - Total lines: ${stats['total_lines']}');
      print('  - Viewport start: ${stats['viewport_start']}');
      print('  - Viewport end: ${stats['viewport_end']}');
      print('  - Chunks loaded: ${stats['loaded_chunks']}');

      // 7. Test viewport updates
      print('\nTesting viewport updates:');
      docManager.updateViewport(5000);
      print('  Updated viewport to line 5000');

      final statsAfter = docManager.getDocumentStats();
      print('  - Viewport start: ${statsAfter['viewport_start']}');
      print('  - Viewport end: ${statsAfter['viewport_end']}');

      // 8. Test content retrieval
      print('\nTesting content retrieval:');
      final visibleLines = docManager.getVisibleLines();
      print('  Retrieved ${visibleLines.length} visible lines');
      print('  First line: ${visibleLines.first}');

      // 9. Test cache management
      print('\nTesting cache management:');
      print('  Cache size before clearing: ${renderer.getStats()["chunks_cached"]}');
      docManager.clearCache();
      print('  Cache cleared');
      print('  Cache size after clearing: ${renderer.getStats()["chunks_cached"]}');

    } catch (e) {
      print('Error in example: $e');
    } finally {
      // Clean up temporary directory
      try {
        tempDir.deleteSync(recursive: true);
        print('\nCleaned up temporary directory');
      } catch (e) {
        print('Could not clean up temporary directory: $e');
      }
    }

    print('\n=== Example Complete ===');
  }
}