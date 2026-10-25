import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/editor/page_editor_controller.dart';

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

/// Lets a pending autosave finish: real time for the disk, then a frame so
/// the editor sees the write complete. A slow disk (Windows CI) can still be
/// writing when a test reads the file back right after settling.
Future<void> waitSaved(WidgetTester tester, PageEditorController editor) async {
  for (var i = 0; i < 40 && editor.dirty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
}
