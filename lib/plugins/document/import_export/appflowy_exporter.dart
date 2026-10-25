import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart' as archive;
import 'package:path/path.dart' as path;
import 'package:windows_app/lib/plugins/document/storage/virtualized_document_manager.dart';

/// AppFlowy backup exporter for creating export files compatible with AppFlowy
class AppFlowyExporter {
  /// Export documents to AppFlowy backup format
  static Future<String> exportToBackup(
    List<String> documentPaths,
    String exportDirectory,
    String backupName
  ) async {
    try {
      print('Starting AppFlowy backup export...');

      // Create export directory if it doesn't exist
      final exportDir = Directory(exportDirectory);
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }

      // Create temporary directory for backup structure
      final tempDir = Directory.systemTemp.createTempSync('appflowy_export_');

      try {
        // Create standard AppFlowy backup structure
        final documentsDir = Directory('${tempDir.path}/documents');
        await documentsDir.create(recursive: true);

        final workspaceDir = Directory('${tempDir.path}/workspace');
        await workspaceDir.create(recursive: true);

        // Process each document
        for (int i = 0; i < documentPaths.length; i++) {
          final sourcePath = documentPaths[i];
          final file = File(sourcePath);

          if (await file.exists()) {
            print('Processing document: $sourcePath');

            // Read document content
            final content = await file.readAsString();

            // Convert to AppFlowy format (simplified structure)
            final appFlowyContent = _convertToAppFlowyFormat(content, path.basename(sourcePath));

            // Save as JSON file in documents directory
            final fileName = 'document_${i + 1}.json';
            final targetPath = '${documentsDir.path}/$fileName';
            await File(targetPath).writeAsString(jsonEncode(appFlowyContent));
          }
        }

        // Create workspace metadata
        final workspaceJson = {
          'name': backupName,
          'created_at': DateTime.now().toIso8601String(),
          'version': '1.0',
          'documents': documentPaths.length,
        };

        await File('${workspaceDir.path}/workspace.json').writeAsString(jsonEncode(workspaceJson));

        // Create ZIP archive
        final backupPath = '${exportDir.path}/${backupName}_export.zip';
        await _createZipArchive(tempDir, backupPath);

        print('Successfully created AppFlowy backup: $backupPath');
        return backupPath;

      } finally {
        // Clean up temporary directory
        try {
          tempDir.deleteSync(recursive: true);
          print('Cleaned up temporary directory');
        } catch (e) {
          print('Warning: Could not clean up temporary directory: $e');
        }
      }

    } catch (e) {
      print('Error exporting to AppFlowy backup: $e');
      rethrow;
    }
  }

  /// Convert document content to AppFlowy format
  static Map<String, dynamic> _convertToAppFlowyFormat(String content, String fileName) {
    try {
      // Split content into lines for processing
      final lines = content.split('\n');

      // Create blocks structure (simplified AppFlowy format)
      final blocks = <Map<String, dynamic>>[];

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isNotEmpty) {
          blocks.add({
            'id': 'block_${i + 1}',
            'type': 'text',
            'text': line,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      }

      // Create document structure
      return {
        'id': 'doc_${DateTime.now().millisecondsSinceEpoch}',
        'name': fileName,
        'blocks': blocks,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'version': '1.0',
      };
    } catch (e) {
      print('Warning: Could not convert to AppFlowy format: $e');

      // Fallback to simple structure
      return {
        'id': 'doc_${DateTime.now().millisecondsSinceEpoch}',
        'name': fileName,
        'content': content,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'version': '1.0',
      };
    }
  }

  /// Create ZIP archive from directory
  static Future<void> _createZipArchive(Directory sourceDir, String zipPath) async {
    try {
      final archive = archive.Archive();

      // Walk through all files in the directory
      await _addDirectoryToArchive(sourceDir, sourceDir.path, archive);

      // Write archive to file
      final bytes = archive.toBytes();
      await File(zipPath).writeAsBytes(bytes);

    } catch (e) {
      print('Error creating ZIP archive: $e');
      rethrow;
    }
  }

  /// Recursively add directory contents to archive
  static Future<void> _addDirectoryToArchive(Directory dir, String basePath, archive.Archive archive) async {
    final files = dir.listSync(recursive: false);

    for (final file in files) {
      if (file is File) {
        final relativePath = path.relative(file.path, from: basePath);

        // Create archive file entry
        final entry = archive.ArchiveFile(
          relativePath,
          await file.readAsBytes(),
          modified: file.lastModifiedSync(),
        );

        archive.addFile(entry);
      } else if (file is Directory) {
        // Recursively add subdirectories
        await _addDirectoryToArchive(file, basePath, archive);
      }
    }
  }

  /// Export a single document to AppFlowy format
  static Future<String> exportDocument(String sourcePath, String exportDirectory) async {
    try {
      final file = File(sourcePath);
      if (!await file.exists()) {
        throw Exception('Source document not found: $sourcePath');
      }

      // Read content
      final content = await file.readAsString();

      // Convert to AppFlowy format
      final appFlowyContent = _convertToAppFlowyFormat(content, path.basename(sourcePath));

      // Create export directory if needed
      final exportDir = Directory(exportDirectory);
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }

      // Save as JSON file
      final fileName = '${path.basenameWithoutExtension(sourcePath)}_export.json';
      final targetPath = '${exportDir.path}/$fileName';

      await File(targetPath).writeAsString(jsonEncode(appFlowyContent));

      print('Successfully exported document: $targetPath');
      return targetPath;

    } catch (e) {
      print('Error exporting document: $e');
      rethrow;
    }
  }

  /// Validate if a file can be exported in AppFlowy format
  static Future<bool> canExportToAppFlowy(String filePath) async {
    try {
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      print('Error validating export file: $e');
      return false;
    }
  }

  /// Get export statistics
  static Map<String, dynamic> getExportStats(List<String> documentPaths) {
    try {
      int totalLines = 0;
      int totalSize = 0;

      for (final path in documentPaths) {
        final file = File(path);
        if (file.existsSync()) {
          totalSize += file.lengthSync();

          // Count lines
          final content = file.readAsStringSync();
          totalLines += content.split('\n').length;
        }
      }

      return {
        'document_count': documentPaths.length,
        'total_size_bytes': totalSize,
        'total_lines': totalLines,
        'average_size_per_document': documentPaths.isNotEmpty ? totalSize ~/ documentPaths.length : 0,
      };
    } catch (e) {
      print('Error getting export stats: $e');
      return {'error': e.toString()};
    }
  }
}