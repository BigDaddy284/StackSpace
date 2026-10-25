import 'dart:io';

/// Deletes a temporary folder of a test. On Windows a file an autosave is
/// still writing cannot be deleted for a moment, so this retries, and a
/// folder that will not go is left for the system to clean up.
Future<void> deleteTemp(Directory dir) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
