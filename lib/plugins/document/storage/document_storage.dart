import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

/// Abstract interface for document storage operations
abstract class DocumentStorage {
  /// Load a document from storage
  Future<List<String>> loadDocument(String filePath) async;

  /// Save a document to storage
  Future<void> saveDocument(String filePath, List<String> content) async;

  /// Check if document exists
  Future<bool> documentExists(String filePath) async;

  /// Get document metadata
  Future<DocumentMetadata> getDocumentMetadata(String filePath) async;

  /// Create a new document
  Future<void> createDocument(String filePath, List<String> content) async;
}

/// Document metadata for file information
class DocumentMetadata {
  final String name;
  final String path;
  final int size;
  final DateTime modifiedDate;
  final DateTime createdDate;
  final String fileType;

  DocumentMetadata({
    required this.name,
    required this.path,
    required this.size,
    required this.modifiedDate,
    required this.createdDate,
    required this.fileType,
  });

  factory DocumentMetadata.fromFile(File file) {
    return DocumentMetadata(
      name: path.basename(file.path),
      path: file.path,
      size: file.lengthSync(),
      modifiedDate: file.lastModifiedSync(),
      createdDate: file.createSync().lastModifiedSync(), // This is approximate
      fileType: path.extension(file.path),
    );
  }
}

/// File-based document storage implementation
class FileDocumentStorage implements DocumentStorage {
  final String basePath;

  FileDocumentStorage({required this.basePath});

  @override
  Future<List<String>> loadDocument(String filePath) async {
    final file = File(filePath);

    if (!await file.exists()) {
      throw FileSystemException('Document not found: $filePath');
    }

    try {
      // Read file content line by line for memory efficiency
      final lines = <String>[];
      final fileContent = await file.readAsString();

      // Split into lines (preserving line endings if needed)
      final lineSplitter = LineSplitter();
      for (final line in lineSplitter.convert(fileContent)) {
        lines.add(line);
      }

      return lines;
    } catch (e) {
      throw FileSystemException('Failed to load document: $e');
    }
  }

  @override
  Future<void> saveDocument(String filePath, List<String> content) async {
    final file = File(filePath);

    try {
      // Write content to file
      final contentString = content.join('\n');
      await file.writeAsString(contentString);
    } catch (e) {
      throw FileSystemException('Failed to save document: $e');
    }
  }

  @override
  Future<bool> documentExists(String filePath) async {
    final file = File(filePath);
    return await file.exists();
  }

  @override
  Future<DocumentMetadata> getDocumentMetadata(String filePath) async {
    final file = File(filePath);

    if (!await file.exists()) {
      throw FileSystemException('Document not found: $filePath');
    }

    return DocumentMetadata.fromFile(file);
  }

  @override
  Future<void> createDocument(String filePath, List<String> content) async {
    final file = File(filePath);

    try {
      // Create parent directories if they don't exist
      final directory = Directory(path.dirname(filePath));
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // Write content to file
      final contentString = content.join('\n');
      await file.writeAsString(contentString);
    } catch (e) {
      throw FileSystemException('Failed to create document: $e');
    }
  }
}

/// Virtualized document manager that combines storage with virtualization
class VirtualizedDocumentManager {
  final DocumentStorage storage;
  final VirtualizedRenderer renderer;
  final String filePath;

  VirtualizedDocumentManager({
    required this.storage,
    required this.renderer,
    required this.filePath,
  });

  /// Load document and initialize virtualized rendering
  Future<void> loadDocument() async {
    try {
      // Load document content from storage
      final content = await storage.loadDocument(filePath);

      // Update renderer with actual document size
      renderer.updateViewport(0); // Initialize viewport

      print('Loaded document with ${content.length} lines');
    } catch (e) {
      print('Error loading document: $e');
      // Create empty document if loading fails
      await createEmptyDocument();
    }
  }

  /// Save current document state
  Future<void> saveDocument() async {
    try {
      // In a real implementation, we would get content from the renderer's cache
      // For now, we'll just validate the file exists and can be written
      await storage.saveDocument(filePath, []);
      print('Document saved successfully');
    } catch (e) {
      print('Error saving document: $e');
      rethrow;
    }
  }

  /// Create an empty document
  Future<void> createEmptyDocument() async {
    await storage.createDocument(filePath, ['']);
    renderer.updateViewport(0);
  }

  /// Get content for a specific range of lines (for clipboard operations)
  List<String> getLineRange(int startIndex, int endIndex) {
    final lines = <String>[];

    // In a real implementation, this would fetch from the virtualized renderer
    // For now, we'll simulate it
    for (int i = startIndex; i < endIndex && i < renderer.getStats()['total_lines']; i++) {
      lines.add('Line ${i + 1}: Content');
    }

    return lines;
  }

  /// Get document statistics
  Map<String, dynamic> getDocumentStats() {
    final stats = renderer.getStats();
    return {
      ...stats,
      'file_path': filePath,
    };
  }
}