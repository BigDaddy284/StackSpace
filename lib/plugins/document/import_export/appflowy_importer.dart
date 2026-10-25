import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart' as archive;
import 'package:path/path.dart' as path;
import 'package:windows_app/lib/plugins/document/storage/document_storage.dart';
import 'package:windows_app/lib/plugins/document/storage/virtualized_document_manager.dart';
import 'package:windows_app/lib/plugins/document/virtualized_editor/virtualized_renderer.dart';

/// AppFlowy backup importer for converting AppFlowy exports to virtualized documents
class AppFlowyImporter {
  /// Import an AppFlowy backup ZIP file
  static Future<void> importBackup(String zipFilePath, String targetDirectory) async {
    try {
      print('Starting AppFlowy backup import from: $zipFilePath');

      // Validate input file
      final file = File(zipFilePath);
      if (!await file.exists()) {
        throw Exception('Backup file not found: $zipFilePath');
      }

      // Extract ZIP archive to temporary directory
      final tempDir = Directory.systemTemp.createTempSync('appflowy_import_');

      try {
        // Read and extract the ZIP file using archive library
        final bytes = await file.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);

        for (final zipEntry in archive) {
          if (zipEntry.isFile) {
            final entryPath = path.join(tempDir.path, zipEntry.name);

            // Create parent directories if needed
            final parentDir = Directory(path.dirname(entryPath));
            if (!await parentDir.exists()) {
              await parentDir.create(recursive: true);
            }

            // Write file content
            final data = zipEntry.content as List<int>;
            final outputFile = File(entryPath);
            await outputFile.writeAsBytes(data);
          }
        }

        print('Successfully extracted backup to: ${tempDir.path}');

        // Process the extracted files
        await _processExtractedBackup(tempDir, targetDirectory);

      } finally {
        // Clean up temporary directory
        try {
          tempDir.deleteSync(recursive: true);
          print('Cleaned up temporary directory');
        } catch (e) {
          print('Warning: Could not clean up temporary directory: $e');
        }
      }

      print('AppFlowy backup import completed successfully');

    } catch (e) {
      print('Error importing AppFlowy backup: $e');
      rethrow;
    }
  }

  /// Process the extracted backup files
  static Future<void> _processExtractedBackup(Directory tempDir, String targetDirectory) async {
    try {
      print('Processing extracted backup files...');

      // Create target directory if it doesn't exist
      final targetDir = Directory(targetDirectory);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      // Look for document files in the backup structure
      final documentsDir = Directory('${tempDir.path}/documents');

      if (await documentsDir.exists()) {
        print('Found documents directory, processing individual documents...');

        // Process each document file found
        await _processDocumentsDirectory(documentsDir, targetDirectory);
      } else {
        print('No documents directory found, checking root of backup...');
        // Process files directly in the temp directory
        await _processRootBackup(tempDir, targetDirectory);
      }

    } catch (e) {
      print('Error processing extracted backup: $e');
      rethrow;
    }
  }

  /// Process documents directory structure
  static Future<void> _processDocumentsDirectory(Directory documentsDir, String targetDirectory) async {
    try {
      final files = documentsDir.listSync(recursive: true);

      for (final file in files) {
        if (file is File && file.path.endsWith('.json')) {
          print('Processing JSON document: ${file.path}');

          // Parse the AppFlowy document structure
          final content = await file.readAsString();
          final jsonData = jsonDecode(content);

          // Convert to text format for virtualized rendering
          final textContent = _convertAppFlowyJsonToText(jsonData);

          // Save as text file in target directory
          final fileName = path.basenameWithoutExtension(file.path) + '.txt';
          final targetPath = path.join(targetDirectory, fileName);

          await File(targetPath).writeAsString(textContent);
          print('Saved converted document: $targetPath');
        }
      }

    } catch (e) {
      print('Error processing documents directory: $e');
      rethrow;
    }
  }

  /// Process root backup files directly
  static Future<void> _processRootBackup(Directory tempDir, String targetDirectory) async {
    try {
      final files = tempDir.listSync(recursive: true);

      for (final file in files) {
        if (file is File && !file.path.contains('Thumbs.db')) {
          print('Processing backup file: ${file.path}');

          // Handle different file types
          final extension = path.extension(file.path).toLowerCase();

          if (extension == '.json') {
            // Process JSON documents
            final content = await file.readAsString();
            try {
              final jsonData = jsonDecode(content);
              final textContent = _convertAppFlowyJsonToText(jsonData);

              final fileName = path.basenameWithoutExtension(file.path) + '.txt';
              final targetPath = path.join(targetDirectory, fileName);

              await File(targetPath).writeAsString(textContent);
              print('Saved converted JSON document: $targetPath');
            } catch (e) {
              print('Warning: Could not parse JSON file: $e');
              // If JSON parsing fails, treat as plain text
              final targetPath = path.join(targetDirectory, '${path.basename(file.path)}.txt');
              await file.copy(targetPath);
            }
          } else if (extension == '.txt' || extension == '.md') {
            // Copy text files directly
            final fileName = path.basename(file.path);
            final targetPath = path.join(targetDirectory, fileName);
            await file.copy(targetPath);
            print('Copied text document: $targetPath');
          } else {
            // For other files, copy them as-is
            final fileName = path.basename(file.path);
            final targetPath = path.join(targetDirectory, fileName);
            await file.copy(targetPath);
            print('Copied file: $targetPath');
          }
        }
      }

    } catch (e) {
      print('Error processing root backup: $e');
      rethrow;
    }
  }

  /// Convert AppFlowy JSON structure to text format
  static String _convertAppFlowyJsonToText(dynamic jsonData) {
    try {
      final StringBuffer buffer = StringBuffer();

      // Handle different AppFlowy document structures
      if (jsonData is Map<String, dynamic>) {
        // If it's a document with content
        if (jsonData.containsKey('blocks')) {
          final blocks = jsonData['blocks'] as List<dynamic>;
          for (final block in blocks) {
            if (block is Map<String, dynamic> && block.containsKey('text')) {
              buffer.writeln(block['text']);
            } else if (block is String) {
              buffer.writeln(block);
            }
          }
        } else if (jsonData.containsKey('content')) {
          // Handle different content structures
          final content = jsonData['content'];
          if (content is List<dynamic>) {
            for (final item in content) {
              if (item is Map<String, dynamic> && item.containsKey('text')) {
                buffer.writeln(item['text']);
              } else if (item is String) {
                buffer.writeln(item);
              }
            }
          } else if (content is String) {
            buffer.writeln(content);
          }
        } else {
          // Generic approach - serialize the whole object
          buffer.writeln(jsonEncode(jsonData));
        }
      } else if (jsonData is List<dynamic>) {
        for (final item in jsonData) {
          if (item is Map<String, dynamic> && item.containsKey('text')) {
            buffer.writeln(item['text']);
          } else if (item is String) {
            buffer.writeln(item);
          }
        }
      } else if (jsonData is String) {
        buffer.writeln(jsonData);
      }

      return buffer.toString();
    } catch (e) {
      print('Warning: Could not convert AppFlowy JSON to text: $e');
      // Return raw content as fallback
      return jsonData.toString();
    }
  }

  /// Import a single document from AppFlowy format
  static Future<void> importDocument(String sourcePath, String targetPath) async {
    try {
      final file = File(sourcePath);
      if (!await file.exists()) {
        throw Exception('Source document not found: $sourcePath');
      }

      // Read the content
      final content = await file.readAsString();

      // Determine file type and process accordingly
      final extension = path.extension(sourcePath).toLowerCase();

      if (extension == '.json') {
        // Process JSON content from AppFlowy
        final jsonData = jsonDecode(content);
        final textContent = _convertAppFlowyJsonToText(jsonData);
        await File(targetPath).writeAsString(textContent);
      } else {
        // For text files, copy directly
        await file.copy(targetPath);
      }

      print('Successfully imported document: $targetPath');

    } catch (e) {
      print('Error importing document: $e');
      rethrow;
    }
  }

  /// Validate if a file is an AppFlowy backup
  static Future<bool> isValidAppFlowyBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      // Check file extension
      final extension = path.extension(filePath).toLowerCase();
      if (extension != '.zip') {
        return false;
      }

      // Try to read as ZIP and check for AppFlowy structure
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Look for typical AppFlowy backup files
      bool hasAppFlowyStructure = false;

      for (final zipEntry in archive) {
        if (zipEntry.name.contains('documents') ||
            zipEntry.name.contains('workspace') ||
            zipEntry.name.contains('blocks')) {
          hasAppFlowyStructure = true;
          break;
        }
      }

      return hasAppFlowyStructure;
    } catch (e) {
      print('Error validating AppFlowy backup: $e');
      return false;
    }
  }

  /// Get backup metadata
  static Future<Map<String, dynamic>> getBackupMetadata(String zipFilePath) async {
    try {
      final file = File(zipFilePath);
      if (!await file.exists()) {
        throw Exception('Backup file not found: $zipFilePath');
      }

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final metadata = <String, dynamic>{
        'file_name': path.basename(zipFilePath),
        'file_size': await file.length(),
        'entry_count': archive.length,
        'entries': [],
      };

      for (final zipEntry in archive) {
        final entryInfo = {
          'name': zipEntry.name,
          'size': zipEntry.uncompressedSize,
          'is_file': zipEntry.isFile,
        };
        metadata['entries'].add(entryInfo);
      }

      return metadata;
    } catch (e) {
      print('Error getting backup metadata: $e');
      return {'error': e.toString()};
    }
  }
}