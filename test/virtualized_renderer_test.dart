import 'package:flutter_test/flutter_test.dart';
import 'package:windows_app/lib/plugins/document/virtualized_editor/virtualized_renderer.dart';

void main() {
  group('VirtualizedRenderer', () {
    test('should initialize with correct parameters', () {
      final renderer = VirtualizedRenderer(
        totalLines: 1000,
        chunkSize: 50,
        maxCachedChunks: 3,
      );

      expect(renderer.getStats()['total_lines'], 1000);
      expect(renderer.getStats()['chunk_size'], 50);
      expect(renderer.getStats()['max_cached_chunks'], 3);
    });

    test('should handle viewport updates correctly', () {
      final renderer = VirtualizedRenderer(totalLines: 1000, chunkSize: 100);

      // Update viewport to middle of document
      renderer.updateViewport(500);

      expect(renderer.viewportStart, 450); // 500 - 50/2 = 450
      expect(renderer.viewportEnd, 550);   // 450 + 100 = 550
    });

    test('should load chunks on demand', () {
      final renderer = VirtualizedRenderer(totalLines: 1000, chunkSize: 100);

      // Access a line in the first chunk
      final content = renderer.getLineContent(50);

      expect(content, isNotNull);
      expect(content, contains('Line 51'));
    });

    test('should manage cache properly', () {
      final renderer = VirtualizedRenderer(
        totalLines: 1000,
        chunkSize: 50,
        maxCachedChunks: 2,
      );

      // Access multiple chunks to test cache management
      for (int i = 0; i < 10; i++) {
        renderer.getLineContent(i * 50);
      }

      // Should not exceed maximum cached chunks
      expect(renderer.getStats()['chunks_cached'], lessThanOrEqualTo(2));
    });
  });
}