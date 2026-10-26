import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A small log of what happened while the app started (Bug 5), so an odd
/// launch can be explained afterwards. Lines go to `startup.log` in the app's
/// support folder (`%APPDATA%\com.stackspace\stack_space` on Windows) and to
/// the debug console; the file keeps the last few hundred lines.
class StartupLog {
  StartupLog._();

  static final _start = DateTime.now();
  static final _buffer = <String>[];
  static File? _file;
  static Future<void>? _opening;
  static const keepLines = 400;

  /// Where the log is written, once known.
  static String? get path => _file?.path;

  /// Writes one line with the time since the process started.
  static void log(String message) {
    final ms = DateTime.now().difference(_start).inMilliseconds;
    final line = '${DateTime.now().toIso8601String()} +${ms}ms $message';
    debugPrint('[startup] $line');
    _buffer.add(line);
    _flush();
  }

  /// Starts a fresh section for this launch; call once before anything else.
  static Future<void> open() {
    return _opening ??= () async {
      try {
        final dir = await getApplicationSupportDirectory();
        final file = File(p.join(dir.path, 'startup.log'));
        await file.parent.create(recursive: true);
        _trim(file);
        _file = file;
        _buffer.insert(
            0,
            '---- launch ${_start.toIso8601String()} ${Platform.operatingSystem} '
            '${Platform.operatingSystemVersion} pid $pid ----');
      } catch (e) {
        debugPrint('[startup] no log file: $e');
      }
      _flush();
    }();
  }

  @visibleForTesting
  static void trimForTest(File file) => _trim(file);

  static void _trim(File file) {
    try {
      if (!file.existsSync()) return;
      final lines = file.readAsLinesSync();
      if (lines.length > keepLines) {
        file.writeAsStringSync('${lines.sublist(lines.length - keepLines).join('\n')}\n');
      }
    } catch (_) {}
  }

  static void _flush() {
    final file = _file;
    if (file == null || _buffer.isEmpty) return;
    final text = '${_buffer.join('\n')}\n';
    _buffer.clear();
    try {
      file.writeAsStringSync(text, mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('[startup] could not write the log: $e');
    }
  }

  /// Routes uncaught errors into the log, keeping the default handling.
  static void captureErrors() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      log('Flutter error: ${details.exceptionAsString()}\n${details.stack}');
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      log('Uncaught error: $error\n$stack');
      return false;
    };
  }
}
