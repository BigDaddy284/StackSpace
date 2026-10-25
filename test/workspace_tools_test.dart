import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/ai/workspace_tools.dart';
import 'package:stack_space/workspace/workspace.dart';
import 'support/temp.dart';

void main() {
  late Directory dir;
  late Workspace ws;
  late WorkspaceTools tools;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tools_test_');
    ws = Workspace(dir.path);
    await ws.init();
    tools = WorkspaceTools(ws);
    await ws.write('script.py', 'import os\n\ndef main():\n    print("hi")\n\nmain()');
  });

  tearDown(() async {
    ws.dispose();
    await deleteTemp(dir);
  });

  test('every tool has a definition the model can see', () {
    final names = tools.definitions.map((d) => d['function']['name']).toSet();
    expect(names, {
      'list_pages',
      'read_page',
      'search_pages',
      'create_page',
      'write_page',
      'replace_text',
      'edit_lines',
      'insert_lines',
      'rename_page',
      'delete_page',
    });
  });

  test('read_page numbers lines and pages long files', () async {
    final out = await tools.run('read_page', {'path': 'script.py'});
    expect(out.result, startsWith('1| import os\n2| \n3| def main():'));

    await ws.write('big.txt', List.generate(1000, (i) => 'line ${i + 1}').join('\n'));
    final part = await tools.run('read_page', {'path': 'big.txt', 'start_line': '500'});
    expect(part.result, startsWith('500| line 500'));
    expect(part.result, contains('Showing lines 500-899 of 1000'));
    expect(part.result, contains('start_line 900'));
  });

  test('replace_text needs a unique match', () async {
    final missing = await tools.run('replace_text', {'path': 'script.py', 'old_text': 'nope', 'new_text': 'x'});
    expect(missing.isError, isTrue);

    await ws.write('dup.txt', 'a\na\n');
    final dup = await tools.run('replace_text', {'path': 'dup.txt', 'old_text': 'a', 'new_text': 'b'});
    expect(dup.result, contains('matches 2 places'));
    final all =
        await tools.run('replace_text', {'path': 'dup.txt', 'old_text': 'a', 'new_text': 'b', 'replace_all': true});
    expect(all.isError, isFalse);
    expect(await ws.read('dup.txt'), 'b\nb\n');

    final ok =
        await tools.run('replace_text', {'path': 'script.py', 'old_text': 'print("hi")', 'new_text': 'print("hello")'});
    expect(ok.summary, 'Edited script.py (line 4)');
    expect(await ws.read('script.py'), contains('print("hello")'));
  });

  test('edit_lines and insert_lines', () async {
    await tools.run(
        'edit_lines', {'path': 'script.py', 'start_line': 3, 'end_line': 4, 'new_text': 'def main():\n    return 1'});
    expect(await ws.read('script.py'), 'import os\n\ndef main():\n    return 1\n\nmain()');
    await tools.run('insert_lines', {'path': 'script.py', 'after_line': 0, 'text': '#!/usr/bin/env python'});
    expect((await ws.read('script.py')).split('\n').first, '#!/usr/bin/env python');
    final bad = await tools.run('edit_lines', {'path': 'script.py', 'start_line': 50, 'end_line': 60, 'new_text': ''});
    expect(bad.isError, isTrue);
  });

  test('create_page refuses to overwrite and makes folders', () async {
    final exists = await tools.run('create_page', {'path': 'script.py', 'content': 'x'});
    expect(exists.isError, isTrue);
    final made = await tools.run('create_page', {'path': 'notes/new.md', 'content': '# New'});
    expect(made.isError, isFalse);
    expect(await ws.read('notes/new.md'), '# New');
  });

  test('delete asks first and respects a no', () async {
    var asked = 0;
    tools.confirm = (title, message) async {
      asked++;
      return false;
    };
    final declined = await tools.run('delete_page', {'path': 'script.py'});
    expect(asked, 1);
    expect(declined.isError, isTrue);
    expect(await ws.exists('script.py'), isTrue);

    tools.confirm = (title, message) async => true;
    final deleted = await tools.run('delete_page', {'path': 'script.py'});
    expect(deleted.isError, isFalse);
    expect(await ws.exists('script.py'), isFalse);
  });

  test('every kind of AI edit can be undone', () async {
    final before = await ws.read('script.py');

    final edit = await tools.run('write_page', {'path': 'script.py', 'content': 'gone'});
    await tools.revert(edit.edit!);
    expect(await ws.read('script.py'), before);

    final created = await tools.run('create_page', {'path': 'tmp.md', 'content': 'x'});
    await tools.revert(created.edit!);
    expect(await ws.exists('tmp.md'), isFalse);

    final renamed = await tools.run('rename_page', {'path': 'script.py', 'new_path': 'src/app.py'});
    await tools.revert(renamed.edit!);
    expect(await ws.read('script.py'), before);

    tools.confirmDeletes = false;
    final deleted = await tools.run('delete_page', {'path': 'script.py'});
    await tools.revert(deleted.edit!);
    expect(await ws.read('script.py'), before);
  });

  test('search finds lines across pages', () async {
    await ws.write('notes/a.md', 'Buy milk\nCall MOM');
    final out = await tools.run('search_pages', {'query': 'mom'});
    expect(out.result, 'notes/a.md:2: Call MOM');
  });

  test('bad arguments come back as errors the model can read', () async {
    final out = await tools.run('edit_lines', {'path': 'script.py'});
    expect(out.isError, isTrue);
    expect(out.result, contains('start_line'));
    final escape = await tools.run('read_page', {'path': '../../etc/passwd'});
    expect(escape.result, contains('outside the workspace'));
  });
}
