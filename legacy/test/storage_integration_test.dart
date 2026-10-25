import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/plugins/document/storage/document_storage.dart';
import 'package:stack_space/plugins/document/storage/virtualized_document_manager.dart';
import 'package:stack_space/plugins/document/virtualized_editor/virtualized_renderer.dart';

void main() {
  group('Storage Integration Tests', () {
    test('should create and initialize storage system', () {
      final tempDir = Directory.systemTemp.createTempSync('storage_test_');
      final storage = FileDocumentStorage(basePath: tempDir.path);

      expect(storage, isNotNull);
      expect(tempDir.existsSync(), true);

      // Clean up
      tempDir.deleteSync(recursive: true);
    });

    test('should handle document creation and loading', () async {
      final tempDir = Directory.systemTemp.createTempSync('doc_test_');
      final filePath = '${tempDir.path}/test_document.txt';

      final storage = FileDocumentStorage(basePath: tempDir.path);
      final renderer = VirtualizedRenderer(totalLines: 100, chunkSize: 50);
      final docManager = EnhancedVirtualizedDocumentManager(
        storage: storage,
        renderer: renderer,
        filePath: filePath,
      );

      // Create a document
      final content = ['Line 1: Test content', 'Line 2: More test content'];
      await storage.createDocument(filePath, content);

      // Check if document exists
      final exists = await storage.documentExists(filePath);
      expect(exists, true);

      // Load document
      await docManager.loadDocument();
      expect(docManager.isLoaded, true);

      // Get document stats
      final stats = docManager.getDocumentStats();
      expect(stats['is_loaded'], true);
      expect(stats['file_path'], filePath);

      // Clean up
      tempDir.deleteSync(recursive: true);
    });

    test('should handle empty document creation', () async {
      final tempDir = Directory.systemTemp.createTempSync('empty_test_');
      final filePath = '${tempDir.path}/empty_document.txt';

      final storage = FileDocumentStorage(basePath: tempDir.path);
      final renderer = VirtualizedRenderer(totalLines: 1, chunkSize: 50);
      final docManager = EnhancedVirtualizedDocumentManager(
        storage: storage,
        renderer: renderer,
        filePath: filePath,
      );

      // Create empty document
      await docManager.createEmptyDocument();

      // Check if document exists and is loaded
      expect(docManager.isLoaded, true);

      // Get document stats
      final stats = docManager.getDocumentStats();
      expect(stats['is_loaded'], true);

      // Clean up
      tempDir.deleteSync(recursive: true);
    });

    test('should manage chunks properly', () {
      final tempDir = Directory.systemTemp.createTempSync('chunk_test_');
      final filePath = '${tempDir.path}/chunk_document.txt';

      final storage = FileDocumentStorage(basePath: tempDir.path);
      final renderer = VirtualizedRenderer(totalLines: 1000, chunkSize: 100);
      final docManager = EnhancedVirtualizedDocumentManager(
        storage: storage,
        renderer: renderer,
        filePath: filePath,
      );

      // Test chunk loading
      docManager.loadChunk(0);
      docManager.loadChunk(5);

      // Check loaded chunks
      expect(docManager.getDocumentStats()['loaded_chunks'], 2);

      // Test unloading
      docManager.unloadChunk(0);
      expect(docManager.getDocumentStats()['loaded_chunks'], 1);

      // Clean up
      tempDir.deleteSync(recursive: true);
    });

    test('should handle document metadata', () async {
      final tempDir = Directory.systemTemp.createTempSync('meta_test_');
      final filePath = '${tempDir.path}/metadata_document.txt';

      final storage = FileDocumentStorage(basePath: tempDir.path);

      // Create a document
      final content = ['Line 1: Metadata test', 'Line 2: More metadata'];
      await storage.createDocument(filePath, content);

      // Get metadata
      final metadata = await storage.getDocumentMetadata(filePath);

      expect(metadata.name, 'metadata_document.txt');
      expect(metadata.path, filePath);
      expect(metadata.size, greaterThan(0));
      expect(metadata.fileType, '.txt');

      // Clean up
      tempDir.deleteSync(recursive: true);
    });
  });
}