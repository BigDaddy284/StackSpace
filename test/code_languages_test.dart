import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/editor/blocks.dart';
import 'package:stack_space/editor/code_languages.dart';

void main() {
  test('fence names and aliases map to languages', () {
    expect(languageFor('c#')!.id, 'csharp');
    expect(languageFor('JS')!.id, 'javascript');
    expect(languageFor('ps1')!.id, 'powershell');
    expect(languageFor('xml')!.id, 'html');
    expect(languageFor('text')!.id, 'text');
    expect(languageFor('nope'), isNull);
    expect(languageForExtension('.py')!.id, 'python');
    expect(languageForExtension('.cs')!.id, 'csharp');
    expect(languageForExtension('.json')!.id, 'json');
    expect(languageForExtension('.weird'), isNull);
    expect(filterLanguages('pow').single.id, 'powershell');
    expect(filterLanguages('sh').map((l) => l.id), containsAll(['bash', 'powershell']));
  });

  test('caption is kept on the fence line and round-trips', () {
    const md = '```python Download helper\nprint(1)\n```\n\n```text Just a note\nx\n```\n\n```\ny\n```\n';
    final blocks = parseMarkdown(md);
    expect(blocks[0].language, 'python');
    expect(blocks[0].caption, 'Download helper');
    expect(blocks[1].language, 'text');
    expect(blocks[1].caption, 'Just a note');
    expect(blocks[2].caption, '');
    expect(writeMarkdown(blocks), md);
    final captioned = blocks[2].copyWith(caption: 'Later');
    expect(blockToMarkdown(captioned), '```text Later\ny\n```');
  });

  const samples = {
    'python':
        'import os\n\ndef greet(name):\n    print(f"hi {name}")\n\nif __name__ == "__main__":\n    greet("bob")\n',
    'javascript': 'const x = require("fs");\nfunction add(a, b) {\n  return a + b;\n}\nconsole.log(add(1, 2));\n',
    'json': '{\n  "name": "stack",\n  "version": 2,\n  "tags": ["a", "b"],\n  "nested": {"ok": true}\n}\n',
    'csharp':
        'using UnityEngine;\n\npublic class Player : MonoBehaviour {\n    [SerializeField] private float speed = 5f;\n    void Update() {\n        transform.Translate(Vector3.forward * speed * Time.deltaTime);\n    }\n}\n',
    'html':
        '<!DOCTYPE html>\n<html>\n<head><title>Hi</title></head>\n<body><div class="x"><p>Hello</p></div></body>\n</html>\n',
    'sql': 'SELECT id, name FROM users WHERE age > 21 ORDER BY name;\nINSERT INTO users (name) VALUES ("x");\n',
    'bash': '#!/bin/bash\nfor f in *.txt; do\n  echo "\$f"\n  cp "\$f" /tmp/\ndone\n',
    'css':
        '.card {\n  display: flex;\n  margin: 0 auto;\n  color: #fff;\n}\n@media (max-width: 600px) { .card { display: none; } }\n',
    'powershell':
        'param([string]\$Name)\nGet-ChildItem -Path C:\\\\ | Where-Object { \$_.Length -gt 100 }\nWrite-Host "Hello \$Name"\n',
    'lua': 'local function update(dt)\n  for i, v in ipairs(items) do\n    v.x = v.x + dt\n  end\nend\n',
  };

  for (final entry in samples.entries) {
    test('detects ${entry.key}', () {
      expect(detectLanguage(entry.value)?.id, entry.key);
    });
  }

  test('does not guess for prose or tiny snippets', () {
    expect(detectLanguage('hello'), isNull);
    expect(detectLanguage('Just a short note about the weekend plans and shopping.'), isNull);
  });
}
