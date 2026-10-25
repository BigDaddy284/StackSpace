import 'dart:io';
import 'package:stack_space/plugins/document/import_export/appflowy_importer.dart';
import 'package:stack_space/plugins/document/import_export/appflowy_exporter.dart';

/// Example demonstrating how to use the AppFlowy import/export functionality
class ImportExportExample {
  static Future<void> runExample() async {
    print('=== AppFlowy Import/Export Example ===\n');

    try {
      // Create a temporary directory for our example
      final tempDir = Directory.systemTemp.createTempSync('import_export_example_');

      print('1. Creating sample documents...');

      // Create some sample text files to work with
      final doc1Path = '${tempDir.path}/sample_document_1.txt';
      final doc2Path = '${tempDir.path}/sample_document_2.txt';

      await File(doc1Path).writeAsString(
        'Line 1: This is the first sample document\n'
        'Line 2: With multiple lines of content\n'
        'Line 3: Testing import/export functionality\n'
        'Line 4: Virtualized rendering system example'
      );

      await File(doc2Path).writeAsString(
        'Line 1: Second sample document\n'
        'Line 2: Contains different content\n'
        'Line 3: For demonstration purposes\n'
        'Line 4: Shows how import/export works'
      );

      print('   - Created sample documents');

      print('\n2. Testing import functionality...');

      // Show that we can validate backup files (even if we don't have a real one)
      final isValid = await AppFlowyImporter.isValidAppFlowyBackup('/non/existent/file.zip');
      print('   - Backup validation works: $isValid');

      // Show metadata retrieval (would work with real backups)
      try {
        final metadata = await AppFlowyImporter.getBackupMetadata('/non/existent/file.zip');
        print('   - Metadata retrieval works: ${metadata.containsKey("file_name") ? "Yes" : "No"}');
      } catch (e) {
        print('   - Metadata retrieval: Error (expected for non-existent file)');
      }

      print('\n3. Testing export functionality...');

      // Export our sample documents
      final exportDir = '${tempDir.path}/export';
      final backupPath = await AppFlowyExporter.exportToBackup(
        [doc1Path, doc2Path],
        exportDir,
        'sample_backup'
      );

      print('   - Created backup: $backupPath');

      // Export individual document
      final docExportPath = await AppFlowyExporter.exportDocument(doc1Path, exportDir);
      print('   - Exported individual document: $docExportPath');

      print('\n4. Testing document conversion...');

      // Show that we can convert documents to AppFlowy format
      final content = await File(doc1Path).readAsString();
      final converted = AppFlowyImporter._convertAppFlowyJsonToText(content);
      print('   - Converted document content length: ${converted.length}');

      print('\n5. Export statistics...');

      // Show export statistics
      final stats = AppFlowyExporter.getExportStats([doc1Path, doc2Path]);
      print('   - Document count: ${stats['document_count']}');
      print('   - Total size: ${stats['total_size_bytes']} bytes');
      print('   - Total lines: ${stats['total_lines']}');

      print('\n=== Example Complete ===');

    } catch (e) {
      print('Error in example: $e');
    } finally {
      // Clean up temporary directory
      try {
        Directory.systemTemp.listSync(recursive: true)
            .where((f) => f.path.contains('import_export_example_'))
            .forEach((f) {
          if (f is Directory) {
            f.deleteSync(recursive: true);
          } else if (f is File) {
            f.deleteSync();
          }
        });
        print('\nCleaned up temporary files');
      } catch (e) {
        print('Could not clean up temporary files: $e');
      }
    }
  }
}