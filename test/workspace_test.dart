import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stack_space/workspace/workspace.dart';

void main() {
  late Directory dir;
  late Workspace ws;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ws_test_');
    ws = Workspace(dir.path);
    await ws.init();
  });

  tearDown(() async {
    ws.dispose();
    await dir.delete(recursive: true);
  });

  test('rejects paths outside the workspace', () {
    expect(() => ws.resolve('../evil.txt'), throwsA(isA<WorkspaceException>()));
    expect(() => ws.resolve('a/../../evil.txt'), throwsA(isA<WorkspaceException>()));
    expect(() => ws.resolve('/etc/passwd'), throwsA(isA<WorkspaceException>()));
    expect(() => ws.resolve(r'C:\Windows\win.ini'), throwsA(isA<WorkspaceException>()));
    expect(ws.normalize(r'notes\todo.md'), 'notes/todo.md');
    expect(ws.normalize('./a/./b.md'), 'a/b.md');
  });

  test('writes, lists folders first, and hides dot folders', () async {
    await ws.write('b.md', 'b');
    await ws.write('a/inner.md', 'x');
    await ws.write('.hidden/secret.md', 's');
    expect(ws.entries.map((e) => e.path), ['a', 'a/inner.md', 'b.md']);
  });

  test('pictures and other binary files are listed but are not pages', () async {
    await ws.write('notes.md', 'n');
    await File('${dir.path}/photo.PNG').writeAsBytes([1, 2, 3]);
    await Directory('${dir.path}/images').create();
    await File('${dir.path}/images/a.jpg').writeAsBytes([1]);
    await ws.refresh();
    expect(ws.entries.map((e) => e.path), ['images', 'images/a.jpg', 'notes.md', 'photo.PNG']);
    expect(ws.entries.where((e) => e.isBinary).map((e) => e.path), ['images/a.jpg', 'photo.PNG']);
    expect(ws.pages.map((e) => e.path), ['notes.md']);
  });

  test('keeps CRLF line endings when saving', () async {
    final file = File(p.join(dir.path, 'win.txt'));
    await file.writeAsString('one\r\ntwo\r\n');
    expect(await ws.read('win.txt'), 'one\ntwo\n');
    await ws.write('win.txt', 'one\ntwo\nthree\n');
    expect(await file.readAsString(), 'one\r\ntwo\r\nthree\r\n');
  });

  test('delete moves to trash and restore brings it back', () async {
    await ws.write('page.md', 'hello');
    final trash = await ws.delete('page.md');
    expect(await ws.exists('page.md'), isFalse);
    expect(File(p.join(dir.path, trash)).existsSync(), isTrue);
    expect(ws.entries, isEmpty);
    await ws.restore(trash, 'page.md');
    expect(await ws.read('page.md'), 'hello');
  });

  test('mustNotExist refuses to overwrite', () async {
    await ws.write('page.md', 'one');
    expect(() => ws.write('page.md', 'two', mustNotExist: true), throwsA(isA<WorkspaceException>()));
  });

  test('rename emits a change and moves the file', () async {
    await ws.write('old.md', 'x');
    final changes = <WorkspaceChange>[];
    final sub = ws.changes.listen(changes.add);
    await ws.rename('old.md', 'folder/new.md', source: ChangeSource.ai);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(await ws.read('folder/new.md'), 'x');
    expect(changes.single.kind, WorkspaceChangeKind.renamed);
    expect(changes.single.newPath, 'folder/new.md');
    expect(changes.single.source, ChangeSource.ai);
  });

  test('reading binary data reports it is not text', () async {
    await File(p.join(dir.path, 'img.bin')).writeAsBytes([0xff, 0xfe, 0xfd, 0x00, 0xc3]);
    expect(() => ws.read('img.bin'), throwsA(isA<WorkspaceException>()));
  });
}
