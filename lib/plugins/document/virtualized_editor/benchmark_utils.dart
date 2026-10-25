import 'dart:math' as math;
import 'virtualized_renderer.dart';

/// Utility class for benchmarking virtualized document rendering performance
class BenchmarkUtils {
  /// Run performance benchmark on virtualized renderer
  static Map<String, dynamic> runPerformanceBenchmark({
    required int documentSize,
    required int chunkSize,
    int iterations = 100,
  }) {
    final results = <String, dynamic>{};

    // Create renderer with specified parameters
    final renderer = VirtualizedRenderer(
      totalLines: documentSize,
      chunkSize: chunkSize,
    );

    // Test 1: Initial viewport loading time
    final loadStart = DateTime.now();
    renderer.updateViewport(0);
    final loadEnd = DateTime.now();
    results['initial_load_time_ms'] = loadEnd.difference(loadStart).inMilliseconds;

    // Test 2: Random access performance
    final random = math.Random();
    final accessTimes = <int>[];

    for (int i = 0; i < iterations; i++) {
      final lineIndex = random.nextInt(documentSize);
      final start = DateTime.now();
      final content = renderer.getLineContent(lineIndex);
      final end = DateTime.now();

      if (content != null) {
        accessTimes.add(end.difference(start).inMilliseconds);
      }
    }

    if (accessTimes.isNotEmpty) {
      results['avg_access_time_ms'] = accessTimes.reduce((a, b) => a + b) / accessTimes.length;
      results['max_access_time_ms'] = accessTimes.reduce(math.max);
      results['min_access_time_ms'] = accessTimes.reduce(math.min);
    }

    // Test 3: Memory usage estimation
    final stats = renderer.getStats();
    results['total_lines'] = stats['total_lines'];
    results['chunks_cached'] = stats['chunks_cached'];
    results['viewport_start'] = stats['viewport_start'];
    results['viewport_end'] = stats['viewport_end'];

    // Test 4: Scroll performance
    final scrollTimes = <int>[];
    final scrollIterations = math.min(10, documentSize ~/ chunkSize);

    for (int i = 0; i < scrollIterations; i++) {
      final startIndex = i * chunkSize;
      final start = DateTime.now();
      renderer.updateViewport(startIndex);
      final end = DateTime.now();

      scrollTimes.add(end.difference(start).inMilliseconds);
    }

    if (scrollTimes.isNotEmpty) {
      results['avg_scroll_time_ms'] = scrollTimes.reduce((a, b) => a + b) / scrollTimes.length;
    }

    return results;
  }

  /// Compare performance between virtualized and traditional rendering
  static void compareRenderingApproaches({
    required int documentSize,
  }) {
    print('=== Performance Comparison ===');
    print('Document size: $documentSize lines');

    // Test with different chunk sizes
    final chunkSizes = [50, 100, 200, 500];

    for (final chunkSize in chunkSizes) {
      print('\n--- Chunk Size: $chunkSize ---');

      final results = runPerformanceBenchmark(
        documentSize: documentSize,
        chunkSize: chunkSize,
        iterations: 100,
      );

      print('Initial load time: ${results['initial_load_time_ms']}ms');
      print('Average access time: ${results['avg_access_time_ms'].toStringAsFixed(2)}ms');
      print('Chunks cached: ${results['chunks_cached']}');
      print('Average scroll time: ${results['avg_scroll_time_ms'].toStringAsFixed(2)}ms');
    }
  }

  /// Generate test document content
  static List<String> generateTestDocument(int lineCount) {
    final lines = <String>[];

    for (int i = 0; i < lineCount; i++) {
      lines.add(
        'Line ${i + 1}: This is sample content for testing virtualized rendering performance with large documents containing many lines of text.'
      );
    }

    return lines;
  }
}