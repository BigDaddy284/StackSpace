import 'package:flutter_test/flutter_test.dart';
import 'package:windows_app/lib/plugins/document/virtualized_editor/benchmark_utils.dart';
import 'package:windows_app/lib/plugins/document/virtualized_editor/virtualized_renderer.dart';

void main() {
  group('Benchmark Tests', () {
    test('should run basic benchmark without errors', () {
      // Test with a medium-sized document
      final results = BenchmarkUtils.runPerformanceBenchmark(
        documentSize: 1000,
        chunkSize: 100,
        iterations: 50,
      );

      expect(results['total_lines'], 1000);
      expect(results['chunks_cached'], isNotNull);
      expect(results['initial_load_time_ms'], isNotNull);
      expect(results['avg_access_time_ms'], isNotNull);
    });

    test('should handle large document sizes', () {
      // Test with a larger document
      final results = BenchmarkUtils.runPerformanceBenchmark(
        documentSize: 10000,
        chunkSize: 200,
        iterations: 20,
      );

      expect(results['total_lines'], 10000);
      expect(results['chunks_cached'], isNotNull);
    });

    test('should maintain performance with many chunks', () {
      // Test with many small chunks to stress the cache system
      final results = BenchmarkUtils.runPerformanceBenchmark(
        documentSize: 5000,
        chunkSize: 50,
        iterations: 30,
      );

      expect(results['total_lines'], 5000);
      expect(results['chunks_cached'], isNotNull);
    });
  });

  group('VirtualizedRenderer Performance', () {
    test('should handle viewport updates efficiently', () {
      final renderer = VirtualizedRenderer(totalLines: 10000, chunkSize: 100);

      // Update viewport multiple times
      for (int i = 0; i < 10; i++) {
        renderer.updateViewport(i * 1000);
      }

      final stats = renderer.getStats();
      expect(stats['total_lines'], 10000);
      expect(stats['chunks_cached'], isNotNull);
    });

    test('should maintain memory efficiency', () {
      final renderer = VirtualizedRenderer(
        totalLines: 5000,
        chunkSize: 50,
        maxCachedChunks: 3,
      );

      // Access many different chunks to test cache management
      for (int i = 0; i < 20; i++) {
        renderer.getLineContent(i * 100);
      }

      final stats = renderer.getStats();
      // Should not exceed maximum cached chunks
      expect(stats['chunks_cached'], lessThanOrEqualTo(3));
    });
  });
}