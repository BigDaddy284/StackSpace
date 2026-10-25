import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stack_space/import/appflowy_import.dart';
import 'package:stack_space/workspace/workspace.dart';
import 'support/temp.dart';

String _ops(List<Map<String, dynamic>> ops) => jsonEncode(ops);

Map<String, dynamic> _block(String id, String ty, String parent,
        {Map<String, dynamic> data = const {}, bool text = true}) =>
    {
      'id': id,
      'ty': ty,
      'parent': parent,
      'children': id,
      'external_id': text ? id : null,
      'external_type': text ? 'text' : null,
      'data': data,
    };

/// A small export in the same shape as AppFlowy's workspace export.
Map<String, String> _export() {
  const ws = 'ws';
  final views = {
    'parent': {
      'view_id': 'parent',
      'name': 'Game: Scripts',
      'layout': 0,
      'parent_id': ws,
      'children': ['child'],
      'collab_object_id': 'parent',
      'created_at': 1
    },
    'child': {
      'view_id': 'child',
      'name': 'Camera Controller',
      'layout': 0,
      'parent_id': 'parent',
      'children': [],
      'collab_object_id': 'child',
      'created_at': 2
    },
    'board': {
      'view_id': 'board',
      'name': 'Tasks',
      'layout': 2,
      'parent_id': ws,
      'children': [],
      'collab_object_id': 'board',
      'created_at': 3
    },
  };
  final parentDoc = {
    'page_id': 'parent',
    'blocks': {
      'parent': _block('parent', 'page', ''),
      'h': _block('h', 'heading', 'parent', data: {'level': 2}),
      'b1': _block('b1', 'bulleted_list', 'parent'),
      'b2': _block('b2', 'bulleted_list', 'b1'),
      'n1': _block('n1', 'numbered_list', 'parent'),
      'n2': _block('n2', 'numbered_list', 'parent'),
      'c': _block('c', 'callout', 'parent', data: {'icon': '🎮'}),
      't': _block('t', 'simple_table', 'parent', text: false),
      'r1': {..._block('r1', 'simple_table_row', 't', text: false)},
      'r2': {..._block('r2', 'simple_table_row', 't', text: false)},
      'c11': _block('c11', 'simple_table_cell', 'r1', text: false),
      'c12': _block('c12', 'simple_table_cell', 'r1', text: false),
      'c21': _block('c21', 'simple_table_cell', 'r2', text: false),
      'c22': _block('c22', 'simple_table_cell', 'r2', text: false),
      'p11': _block('p11', 'paragraph', 'c11'),
      'p12': _block('p12', 'paragraph', 'c12'),
      'p21': _block('p21', 'paragraph', 'c21'),
      'p22': _block('p22', 'paragraph', 'c22'),
      'img': _block('img', 'image', 'parent', data: {'url': 'Camera%20Controller/Untitled.png'}, text: false),
    },
    'meta': {
      'children_map': {
        'parent': ['h', 'b1', 'n1', 'n2', 'c', 't', 'img'],
        'b1': ['b2'],
        't': ['r1', 'r2'],
        'r1': ['c11', 'c12'],
        'r2': ['c21', 'c22'],
        'c11': ['p11'],
        'c12': ['p12'],
        'c21': ['p21'],
        'c22': ['p22'],
      },
      'text_map': {
        'h': _ops([
          {'insert': 'Overview'}
        ]),
        'b1': _ops([
          {'insert': 'See '},
          {
            'insert': r'$',
            'attributes': {
              'mention': {'page_id': 'child', 'type': 'page'}
            }
          },
          {'insert': ' for '},
          {
            'insert': 'the rig',
            'attributes': {'bold': true}
          }
        ]),
        'b2': _ops([
          {'insert': 'nested '},
          {
            'insert': 'code()',
            'attributes': {'code': true}
          }
        ]),
        'n1': _ops([
          {'insert': 'one'}
        ]),
        'n2': _ops([
          {'insert': 'two'}
        ]),
        'c': _ops([
          {'insert': 'Keep notes together.'}
        ]),
        'p11': _ops([
          {'insert': 'Key'}
        ]),
        'p12': _ops([
          {'insert': 'Value'}
        ]),
        'p21': _ops([
          {'insert': 'Speed'}
        ]),
        'p22': _ops([
          {'insert': 'a | b'}
        ]),
      },
    },
  };
  final childDoc = {
    'page_id': 'child',
    'blocks': {
      'child': _block('child', 'page', ''),
      'h1': _block('h1', 'heading', 'child', data: {'level': 1}),
      'code': _block('code', 'code', 'child', data: {'language': 'c#'}),
      'link': _block('link', 'paragraph', 'child'),
    },
    'meta': {
      'children_map': {
        'child': ['h1', 'code', 'link']
      },
      'text_map': {
        'h1': _ops([
          {'insert': 'Camera Controller'}
        ]),
        'code': _ops([
          {'insert': 'public class Cam {\n  int x;\n}'}
        ]),
        'link': _ops([
          {
            'insert': 'repo',
            'attributes': {'href': 'https://example.com/r.git'}
          }
        ]),
      },
    },
  };
  return {
    'relation_map.json': jsonEncode({'workspace_id': ws, 'views': views}),
    'collab_jsons/documents/parent.json': jsonEncode(parentDoc),
    'collab_jsons/documents/child.json': jsonEncode(childDoc),
  };
}

void main() {
  test('converts the page tree, blocks and inline formatting to Markdown', () {
    final result = AppFlowyImporter(_export()).convert();
    final byPath = {for (final page in result.pages) page.path: page.markdown};
    expect(byPath.keys,
        unorderedEquals(['Game- Scripts/Game- Scripts.md', 'Game- Scripts/Camera Controller.md', 'Tasks.md']));

    expect(byPath['Game- Scripts/Game- Scripts.md'], '''# Game: Scripts

## Overview

- See [Camera Controller](Camera%20Controller.md) for **the rig**
  - nested `code()`
1. one
2. two
> 🎮 Keep notes together.

| Key | Value |
| --- | --- |
| Speed | a \\| b |

![Untitled.png](Camera%20Controller/Untitled.png)
''');
    // The page already starts with its title, so it isn't repeated.
    expect(byPath['Game- Scripts/Camera Controller.md'], '''# Camera Controller

```c#
public class Cam {
  int x;
}
```

[repo](https://example.com/r.git)
''');
    expect(result.warnings, contains(contains('"Tasks" is a board')));
    expect(result.warnings, contains(contains('Untitled.png')));
  });

  test('reads a zip, including one with everything under a top folder', () {
    final archive = Archive();
    for (final e in _export().entries) {
      final bytes = utf8.encode(e.value);
      archive.addFile(ArchiveFile('My Workspace/${e.key}', bytes.length, bytes));
    }
    final result = AppFlowyImporter.fromZipBytes(ZipEncoder().encode(archive)!).convert();
    expect(result.pages, hasLength(3));
  });

  test('copies Markdown exports as they are, and rejects other zips', () {
    final result = AppFlowyImporter({'Notes/a.md': '# A\n', 'x.png.json': '{}'}).convert();
    expect(result.pages.single.path, 'Notes/a.md');
    expect(() => AppFlowyImporter({'a.json': '{}'}).convert(), throwsFormatException);
  });

  test('writes into a new folder without overwriting anything', () async {
    final dir = await Directory.systemTemp.createTemp('af_import_');
    addTearDown(() => deleteTemp(dir));
    final ws = Workspace(dir.path);
    await ws.init();
    final result = AppFlowyImporter(_export()).convert();
    expect(await AppFlowyImporter.writeInto(ws, 'AppFlowy import', result), 'AppFlowy import');
    expect(await AppFlowyImporter.writeInto(ws, 'AppFlowy import', result), 'AppFlowy import (2)');
    expect(File(p.join(dir.path, 'AppFlowy import', 'Tasks.md')).existsSync(), isTrue);
    ws.dispose();
  });

  // Runs against a real export when STACKSPACE_AFZIP points at one, writing
  // the Markdown to STACKSPACE_AFOUT for a look.
  final real = Platform.environment['STACKSPACE_AFZIP'];
  test('converts a real AppFlowy export', () async {
    final importer = await AppFlowyImporter.fromPath(real!);
    final result = importer.convert();
    expect(result.pages, isNotEmpty);
    final out = Platform.environment['STACKSPACE_AFOUT'];
    if (out != null) {
      for (final page in result.pages) {
        final file = File(p.join(out, page.path));
        await file.parent.create(recursive: true);
        await file.writeAsString(page.markdown);
      }
      await File(p.join(out, '_warnings.txt')).writeAsString(result.warnings.join('\n'));
    }
  }, skip: real == null ? 'set STACKSPACE_AFZIP to an export to run' : false);
}
