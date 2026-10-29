import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stack_space/workspace/workspace.dart';
import 'support/temp.dart';

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
    await deleteTemp(dir);
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

  test('copy duplicates a page beside the original with a free name', () async {
    await ws.write('notes.md', 'n');
    expect(await ws.copy('notes.md', ''), 'notes copy.md');
    expect(await ws.copy('notes.md', ''), 'notes copy 2.md');
    expect(await ws.read('notes copy 2.md'), 'n');
    expect(await ws.copy('notes.md', 'folder'), 'folder/notes.md', reason: 'a free name is kept');
  });

  test('copy takes a folder with its sub-pages and pictures', () async {
    await ws.write('project/project.md', 'top');
    await ws.write('project/child/child.md', 'kid');
    await File(p.join(dir.path, 'project', 'shot.png')).writeAsBytes([1, 2, 3]);
    await ws.write('archive/keep.md', 'k');
    expect(await ws.copy('project', 'archive'), 'archive/project');
    expect(await ws.read('archive/project/project.md'), 'top');
    expect(await ws.read('archive/project/child/child.md'), 'kid');
    expect(File(p.join(dir.path, 'archive', 'project', 'shot.png')).readAsBytesSync(), [1, 2, 3]);
    expect(await ws.read('project/project.md'), 'top', reason: 'the original stays');

    // Into itself: the copy holds what the folder held, once.
    expect(await ws.copy('project', 'project'), 'project/project');
    expect(await ws.read('project/project/child/child.md'), 'kid');
    expect(await ws.exists('project/project/project'), isFalse);
  });

  test('move puts a page or folder in another folder and refuses itself', () async {
    await ws.write('a/one.md', '1');
    await ws.write('b/two.md', '2');
    expect(await ws.move('a/one.md', 'b'), 'b/one.md');
    expect(await ws.move('b', 'a'), 'a/b');
    expect(await ws.read('a/b/one.md'), '1');
    expect(await ws.move('a/b/two.md', ''), 'two.md', reason: 'out to the top');
    expect(await ws.move('two.md', ''), 'two.md', reason: 'already there: nothing happens');
    expect(() => ws.move('a', 'a/b'), throwsA(isA<WorkspaceException>()));
    await ws.write('two copy.md', 'x');
    expect(() => ws.move('two.md', 'two copy.md'), throwsA(isA<WorkspaceException>()), reason: 'not a folder');
  });
}
