import 'dart:convert';

import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/perl.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/languages/powershell.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/r.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

/// A language a code space can be set to. [id] is what the Markdown fence
/// carries (`\`\`\`python`); [aliases] are other fence names and search words.
class CodeLanguage {
  const CodeLanguage(this.id, this.label, this.mode, {this.aliases = const [], this.detectable = true});

  final String id;
  final String label;
  final Mode mode;
  final List<String> aliases;

  /// Whether auto-detection may pick this language.
  final bool detectable;

  bool matches(String query) {
    final q = query.toLowerCase().trim();
    return q.isEmpty || label.toLowerCase().contains(q) || id.contains(q) || aliases.any((a) => a.contains(q));
  }
}

final List<CodeLanguage> codeLanguages = [
  CodeLanguage('text', 'Plain text', langPlaintext, aliases: ['plain', 'plaintext', 'txt', 'none'], detectable: false),
  CodeLanguage('javascript', 'JavaScript', langJavascript, aliases: ['js', 'jsx', 'node']),
  CodeLanguage('typescript', 'TypeScript', langTypescript, aliases: ['ts', 'tsx']),
  CodeLanguage('python', 'Python', langPython, aliases: ['py', 'py3']),
  CodeLanguage('json', 'JSON', langJson),
  CodeLanguage('html', 'HTML', langXml, aliases: ['xml', 'htm', 'svg', 'xaml']),
  CodeLanguage('css', 'CSS', langCss),
  CodeLanguage('scss', 'SCSS', langScss, aliases: ['sass']),
  CodeLanguage('sql', 'SQL', langSql, aliases: ['mysql', 'postgres', 'sqlite']),
  CodeLanguage('bash', 'Bash / Shell', langBash, aliases: ['sh', 'shell', 'zsh', 'console', 'terminal']),
  CodeLanguage('powershell', 'PowerShell', langPowershell, aliases: ['ps', 'ps1', 'pwsh']),
  CodeLanguage('csharp', 'C#', langCsharp, aliases: ['c#', 'cs', 'unity', 'dotnet']),
  CodeLanguage('cpp', 'C++', langCpp, aliases: ['c++', 'cc', 'hpp', 'unreal']),
  CodeLanguage('c', 'C', langC, aliases: ['h']),
  CodeLanguage('java', 'Java', langJava),
  CodeLanguage('kotlin', 'Kotlin', langKotlin, aliases: ['kt']),
  CodeLanguage('go', 'Go', langGo, aliases: ['golang']),
  CodeLanguage('rust', 'Rust', langRust, aliases: ['rs']),
  CodeLanguage('php', 'PHP', langPhp),
  CodeLanguage('ruby', 'Ruby', langRuby, aliases: ['rb']),
  CodeLanguage('swift', 'Swift', langSwift),
  CodeLanguage('dart', 'Dart', langDart, aliases: ['flutter']),
  CodeLanguage('lua', 'Lua', langLua, aliases: ['love2d', 'roblox']),
  CodeLanguage('yaml', 'YAML', langYaml, aliases: ['yml']),
  CodeLanguage('markdown', 'Markdown', langMarkdown, aliases: ['md']),
  CodeLanguage('ini', 'INI / TOML', langIni, aliases: ['toml', 'cfg', 'conf'], detectable: false),
  CodeLanguage('dockerfile', 'Dockerfile', langDockerfile, aliases: ['docker']),
  CodeLanguage('makefile', 'Makefile', langMakefile, aliases: ['make']),
  CodeLanguage('perl', 'Perl', langPerl, aliases: ['pl']),
  CodeLanguage('r', 'R', langR, detectable: false),
];

final Map<String, CodeLanguage> _byName = {
  for (final l in codeLanguages) ...{l.id: l, for (final a in l.aliases) a: l},
  'xml': codeLanguages.firstWhere((l) => l.id == 'html'),
  'plaintext': codeLanguages.first,
};

/// The language for a fence name such as `js`, `c#` or `python`, or null.
CodeLanguage? languageFor(String? fenceName) {
  if (fenceName == null) return null;
  return _byName[fenceName.toLowerCase().trim()];
}

/// The language a file extension usually means (`.py` → python).
CodeLanguage? languageForExtension(String extension) {
  final ext = extension.toLowerCase().replaceFirst('.', '');
  return const {
        'ps1': 'powershell',
        'psm1': 'powershell',
        'cs': 'csharp',
        'js': 'javascript',
        'mjs': 'javascript',
        'ts': 'typescript',
        'py': 'python',
        'rb': 'ruby',
        'rs': 'rust',
        'kt': 'kotlin',
        'yml': 'yaml',
        'md': 'markdown',
        'htm': 'html',
        'xml': 'html',
        'sh': 'bash',
        'txt': 'text',
        'toml': 'ini',
        'cfg': 'ini',
        'h': 'c',
        'hpp': 'cpp',
        'cc': 'cpp',
      }
      .map((k, v) => MapEntry(k, languageFor(v)))[ext] ??
      languageFor(ext);
}

List<CodeLanguage> filterLanguages(String query) => [for (final l in codeLanguages) if (l.matches(query)) l];

Highlight? _detector;

/// Clear signs of a language, checked before the general detector because
/// the latter's scores are close together for short snippets.
final List<(RegExp, String)> _signatures = [
  (RegExp(r'^#!.*\b(bash|sh|zsh)\b', multiLine: true), 'bash'),
  (RegExp(r'^#!.*\bpython', multiLine: true), 'python'),
  (RegExp(r'^#!.*\bnode\b', multiLine: true), 'javascript'),
  (RegExp(r'<\?php'), 'php'),
  (RegExp(r'<!DOCTYPE html|<html\b|<div\b|<body\b', caseSensitive: false), 'html'),
  (RegExp(r'^\s*using (UnityEngine|System)\b.*;', multiLine: true), 'csharp'),
  (RegExp(r'\b(MonoBehaviour|Console\.WriteLine|namespace \w+\s*[{;])'), 'csharp'),
  (RegExp(r'(^|\n)\s*(param\s*\(|Write-Host|Get-ChildItem|\$_\.|\$\w+\s*=\s*Get-)'), 'powershell'),
  (RegExp(r'^\s*def \w+\(.*\):\s*$', multiLine: true), 'python'),
  (RegExp(r'^\s*(import \w+|from \w+ import )', multiLine: true), 'python'),
  (RegExp(r'\bfn main\(\)|\blet mut\b|\bimpl\b.*\bfor\b'), 'rust'),
  (RegExp(r'^package \w+\s*$.*\bfunc\b', multiLine: true, dotAll: true), 'go'),
  (RegExp(r'#include\s*<.*>.*\b(std::|class |template\s*<)', dotAll: true), 'cpp'),
  (RegExp(r'#include\s*<.*>'), 'c'),
  (RegExp(r'\b(SELECT|INSERT INTO|UPDATE|DELETE FROM|CREATE TABLE)\b.*\b(FROM|VALUES|SET|WHERE)\b', caseSensitive: false, dotAll: true), 'sql'),
  (RegExp(r'\blocal function\b|\bipairs\(|\bfunction\b.*\n.*\bend\b', dotAll: true), 'lua'),
  (RegExp(r'^\s*(public |private )?(static )?(void|int|String) \w+\(.*\)\s*\{', multiLine: true), 'java'),
  (RegExp(r'^FROM \S+\n', multiLine: true), 'dockerfile'),
  (RegExp(r'^\s*(interface|type) \w+\s*[{=]|: (string|number|boolean)\b', multiLine: true), 'typescript'),
  (RegExp(r'\b(const|let|var) \w+\s*=|\bfunction \w*\(|=>\s*\{|console\.log'), 'javascript'),
  (RegExp(r'^\s*[.#]?[\w-]+\s*\{\s*\n\s*[\w-]+\s*:', multiLine: true), 'css'),
  (RegExp(r'^\s*import .* from .*dart|\bWidget build\(BuildContext', multiLine: true), 'dart'),
];

bool _looksLikeJson(String sample) {
  final t = sample.trim();
  if (!(t.startsWith('{') || t.startsWith('['))) return false;
  try {
    jsonDecode(t);
    return true;
  } on FormatException {
    // Partially typed JSON: still JSON-like if it has "key": pairs.
    return RegExp(r'"[^"\n]+"\s*:').hasMatch(t) && !t.contains(RegExp(r'\b(function|const|let|var)\b'));
  }
}

/// Guesses the language of [code], or null when nothing stands out. Only the
/// first few thousand characters are looked at, so pasting a long script is
/// cheap.
CodeLanguage? detectLanguage(String code) {
  final sample = code.length > 4000 ? code.substring(0, 4000) : code;
  if (sample.trim().length < 12) return null;
  if (_looksLikeJson(sample)) return languageFor('json');
  for (final (pattern, id) in _signatures) {
    if (pattern.hasMatch(sample)) return languageFor(id);
  }
  final detector = _detector ??= Highlight()
    ..registerLanguages({for (final l in codeLanguages) if (l.detectable) l.id: l.mode});
  final result = detector.highlightAuto(sample);
  final id = result.language;
  if (id == null || result.relevance < 5) return null;
  return languageFor(id);
}
