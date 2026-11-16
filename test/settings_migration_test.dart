import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stack_space/app/settings.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('migrate_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('settings from the old stack_space folder are copied into the StackSpace folder', () {
    final old = Directory(p.join(root.path, 'stack_space'))..createSync();
    File(p.join(old.path, 'shared_preferences.json')).writeAsStringSync('{"flutter.workspacePath":"D:/notes"}');
    File(p.join(old.path, 'startup.log')).writeAsStringSync('old log');
    final current = Directory(p.join(root.path, 'StackSpace'))..createSync();
    File(p.join(current.path, 'native.log')).writeAsStringSync('new log');

    expect(migrateOldSupportFolder(old, current), isTrue);
    expect(File(p.join(current.path, 'shared_preferences.json')).readAsStringSync(), contains('D:/notes'));
    expect(File(p.join(current.path, 'native.log')).readAsStringSync(), 'new log', reason: 'existing files are kept');
    expect(File(p.join(old.path, 'shared_preferences.json')).existsSync(), isTrue,
        reason: 'the old folder is left alone');
  });

  test('nothing is copied once the new folder has its own settings', () {
    final old = Directory(p.join(root.path, 'stack_space'))..createSync();
    File(p.join(old.path, 'shared_preferences.json')).writeAsStringSync('old');
    final current = Directory(p.join(root.path, 'StackSpace'))..createSync();
    File(p.join(current.path, 'shared_preferences.json')).writeAsStringSync('new');

    expect(migrateOldSupportFolder(old, current), isFalse);
    expect(File(p.join(current.path, 'shared_preferences.json')).readAsStringSync(), 'new');
  });

  test('no old folder: nothing happens', () {
    final current = Directory(p.join(root.path, 'StackSpace'));
    expect(migrateOldSupportFolder(Directory(p.join(root.path, 'stack_space')), current), isFalse);
    expect(current.existsSync(), isFalse);
  });
}
