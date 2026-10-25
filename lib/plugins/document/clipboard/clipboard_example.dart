import 'dart:io';
import 'package:flutter/material.dart';
import 'package:windows_app/lib/plugins/document/storage/virtualized_document_manager.dart';
import 'package:windows_app/lib/plugins/document/clipboard/clipboard_manager.dart';
import 'package:windows_app/lib/plugins/document/virtualized_editor/virtualized_renderer.dart';

/// Example demonstrating the complete virtualized document system with clipboard
class ClipboardSystemExample {
  static Future<void> runCompleteExample() async {
    print('=== Complete Virtualized Document System Example ===\n');

    // Create a temporary directory for our example
    final tempDir = Directory.systemTemp.createTempSync('complete_example_');
    final testFilePath = '${tempDir.path}/example_document.txt';

    try {
      print('1. Setting up virtualized document system...');

      // 1. Create storage and renderer
      final storage = FileDocumentStorage(basePath: tempDir.path);
      final renderer = VirtualizedRenderer(
        totalLines: 5000, // Simulate a large document
        chunkSize: 100,
        maxCachedChunks: 5,
      );

      // 2. Create document manager
      final docManager = EnhancedVirtualizedDocumentManager(
        storage: storage,
        renderer: renderer,
        filePath: testFilePath,
      );

      print('   - Storage system created');
      print('   - Virtualized renderer created (5000 lines)');
      print('   - Document manager created');

      // 3. Create sample content
      print('\n2. Creating sample document...');
      final sampleContent = <String>[];
      for (int i = 0; i < 100; i++) {
        sampleContent.add('Line ${i + 1}: Sample content for virtualized document system demonstration.');
      }

      await storage.createDocument(testFilePath, sampleContent);
      print('   - Created document with ${sampleContent.length} lines');

      // 4. Load the document
      print('\n3. Loading document...');
      await docManager.loadDocument();
      print('   - Document loaded successfully');

      // 5. Show initial stats
      print('\n4. Document statistics:');
      final stats = docManager.getDocumentStats();
      print('   - Total lines: ${stats['total_lines']}');
      print('   - Viewport start: ${stats['viewport_start']}');
      print('   - Viewport end: ${stats['viewport_end']}');
      print('   - Chunks loaded: ${stats['loaded_chunks']}');

      // 6. Test clipboard operations
      print('\n5. Testing clipboard operations...');

      // Get clipboard stats (should be empty)
      final clipboardStats = await ClipboardManager.getClipboardStats();
      print('   - Initial clipboard status:');
      print('     * Has content: ${clipboardStats['has_content']}');
      print('     * Content length: ${clipboardStats['content_length'] ?? 0}');

      // Test copying a range of lines
      print('\n6. Simulating copy operation...');
      try {
        await ClipboardManager.copyContent(docManager, 10, 20);
        print('   - Copy operation completed successfully');
      } catch (e) {
        print('   - Copy operation failed: $e');
      }

      // Test paste functionality
      print('\n7. Simulating paste operation...');
      try {
        await ClipboardManager.pasteContent(docManager, 50, 'Pasted content line 1\nPasted content line 2');
        print('   - Paste operation completed successfully');
      } catch (e) {
        print('   - Paste operation failed: $e');
      }

      // 7. Show final stats
      print('\n8. Final document statistics:');
      final finalStats = docManager.getDocumentStats();
      print('   - Total lines: ${finalStats['total_lines']}');
      print('   - Viewport start: ${finalStats['viewport_start']}');
      print('   - Viewport end: ${finalStats['viewport_end']}');

      // 8. Test performance with large content
      print('\n9. Testing performance with large content...');
      final largeContent = 'Large content line 1\n';
      for (int i = 0; i < 5000; i++) {
        largeContent += 'Line ${i + 2}: This is a very long line of content to test memory management.\n';
      }

      print('   - Large content generated (${largeContent.length} characters)');

      // Test chunked clipboard processing
      await ClipboardManager._copyToClipboardChunked(largeContent);
      print('   - Chunked clipboard processing completed');

      print('\n=== Complete Example Finished ===');

    } catch (e) {
      print('Error in complete example: $e');
    } finally {
      // Clean up temporary directory
      try {
        tempDir.deleteSync(recursive: true);
        print('\nCleaned up temporary directory');
      } catch (e) {
        print('Could not clean up temporary directory: $e');
      }
    }
  }
}