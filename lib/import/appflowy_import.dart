import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../workspace/workspace.dart';

/// One page converted to Markdown, at a path relative to the import folder.
class ImportedPage {
  ImportedPage(this.path, this.markdown);
  final String path;
  final String markdown;
}

class ImportResult {
  ImportResult(this.pages, this.warnings);
  final List<ImportedPage> pages;
  final List<String> warnings;
}

/// Converts an AppFlowy workspace export into Markdown pages.
///
/// Reads AppFlowy's workspace export (`relation_map.json` plus
/// `collab_jsons/documents/<id>.json`): pages keep their tree, a page with
/// sub-pages becomes a folder holding `<name>.md` and its children, and page
/// mentions become relative links. Exports that are already Markdown or text
/// files are copied as they are.
class AppFlowyImporter {
  AppFlowyImporter(Map<String, String> files) : _files = files;

  /// Text files of the export, keyed by their path inside it (with `/`).
  final Map<String, String> _files;

  static const _textExtensions = {'.md', '.markdown', '.txt'};

  static AppFlowyImporter fromZipBytes(List<int> bytes) {
    final files = <String, String>{};
    for (final entry in ZipDecoder().decodeBytes(bytes)) {
      if (!entry.isFile) continue;
      final name = entry.name.replaceAll('\\', '/');
      if (!name.endsWith('.json') && !_textExtensions.contains(p.extension(name).toLowerCase())) continue;
      files[name] = utf8.decode(entry.content as List<int>, allowMalformed: true);
    }
    return AppFlowyImporter(_stripCommonRoot(files));
  }

  static Future<AppFlowyImporter> fromPath(String path) async {
    if (await FileSystemEntity.isFile(path)) return fromZipBytes(await File(path).readAsBytes());
    final files = <String, String>{};
    await for (final entity in Directory(path).list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: path).replaceAll('\\', '/');
      if (!rel.endsWith('.json') && !_textExtensions.contains(p.extension(rel).toLowerCase())) continue;
      files[rel] = await entity.readAsString();
    }
    return AppFlowyImporter(_stripCommonRoot(files));
  }

  /// Zips made by zipping a folder put everything under one top folder.
  static Map<String, String> _stripCommonRoot(Map<String, String> files) {
    if (files.isEmpty || files.containsKey('relation_map.json')) return files;
    final firsts = files.keys.map((k) => k.contains('/') ? k.substring(0, k.indexOf('/')) : null).toSet();
    if (firsts.length != 1 || firsts.first == null) return files;
    final prefix = '${firsts.first}/';
    return {for (final e in files.entries) e.key.substring(prefix.length): e.value};
  }

  ImportResult convert() {
    final relation = _files['relation_map.json'];
    if (relation != null) return _convertWorkspace(jsonDecode(relation) as Map<String, dynamic>);
    final pages = [
      for (final e in _files.entries)
        if (_textExtensions.contains(p.extension(e.key).toLowerCase())) ImportedPage(e.key, e.value),
    ];
    if (pages.isEmpty) {
      throw const FormatException(
          'This is not an AppFlowy export: there is no relation_map.json and no Markdown files.');
    }
    return ImportResult(pages, []);
  }

  ImportResult _convertWorkspace(Map<String, dynamic> relation) {
    final warnings = <String>[];
    final views = (relation['views'] as Map<String, dynamic>).cast<String, Map<String, dynamic>>();
    final rootId = relation['workspace_id'] as String?;

    // Lay out the tree first so mentions can link to any page.
    final paths = <String, String>{};
    final used = <String>{};
    String unique(String folder, String name, String ext) {
      var candidate = p.posix.join(folder, '$name$ext');
      for (var i = 2; used.contains(candidate.toLowerCase()); i++) {
        candidate = p.posix.join(folder, '$name ($i)$ext');
      }
      used.add(candidate.toLowerCase());
      return candidate;
    }

    List<String> childrenOf(String? parent) {
      final ordered = <String>[];
      final listed = parent == null ? null : views[parent]?['children'] as List?;
      for (final id in listed ?? const []) {
        if (views.containsKey(id)) ordered.add(id as String);
      }
      // Views that name this parent but aren't in its children list, in creation order.
      final extra = views.values.where((v) => v['parent_id'] == parent && !ordered.contains(v['view_id'])).toList()
        ..sort((a, b) => ((a['created_at'] ?? 0) as num).compareTo((b['created_at'] ?? 0) as num));
      return [...ordered, for (final v in extra) v['view_id'] as String];
    }

    void place(String id, String folder) {
      final view = views[id]!;
      final name = _safeName(view['name'] as String? ?? '');
      final kids = childrenOf(id);
      if (kids.isEmpty) {
        paths[id] = unique(folder, name, '.md');
      } else {
        final sub = unique(folder, name, '');
        paths[id] = p.posix.join(sub, '$name.md');
        used.add(paths[id]!.toLowerCase());
        for (final kid in kids) {
          place(kid, sub);
        }
      }
    }

    final roots = views.values.where((v) => v['parent_id'] == rootId || !views.containsKey(v['parent_id'])).toList()
      ..sort((a, b) => ((a['created_at'] ?? 0) as num).compareTo((b['created_at'] ?? 0) as num));
    for (final v in roots) {
      place(v['view_id'] as String, '');
    }

    final pages = <ImportedPage>[];
    for (final MapEntry(key: id, value: path) in paths.entries) {
      final view = views[id]!;
      final title = view['name'] as String? ?? 'Untitled';
      final objectId = view['collab_object_id'] as String? ?? id;
      final layout = view['layout'] ?? 0;
      final json = _files['collab_jsons/documents/$objectId.json'];
      if (layout != 0) {
        warnings.add(
            '"$title" is a ${_layoutName(layout)}, which StackSpace can\'t show; it was imported as an empty page.');
        pages.add(ImportedPage(path, '# $title\n'));
      } else if (json == null) {
        warnings.add('"$title" has no content in the export; it was imported as an empty page.');
        pages.add(ImportedPage(path, '# $title\n'));
      } else {
        final doc = _DocumentConverter(
          jsonDecode(json) as Map<String, dynamic>,
          title: title,
          linkTo: (pageId) {
            final target = paths[pageId];
            if (target == null) return null;
            final rel = p.posix.relative(target, from: p.posix.dirname(path));
            return (views[pageId]!['name'] as String? ?? 'page', rel.split('/').map(Uri.encodeComponent).join('/'));
          },
          warn: (w) => warnings.add('"$title": $w'),
        );
        pages.add(ImportedPage(path, doc.convert()));
      }
    }
    return ImportResult(pages, warnings);
  }

  static String _layoutName(Object layout) => switch (layout) {
        1 => 'grid',
        2 => 'board',
        3 => 'calendar',
        4 => 'chat',
        _ => 'database view',
      };

  /// Windows can't use these characters in file names.
  static String _safeName(String name) {
    var s = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '-').trim();
    s = s.replaceAll(RegExp(r'[. ]+$'), '');
    if (s.isEmpty) s = 'Untitled';
    if (RegExp(r'^(con|prn|aux|nul|com\d|lpt\d)$', caseSensitive: false).hasMatch(s)) s = '$s-page';
    return s.length > 120 ? s.substring(0, 120).trim() : s;
  }

  /// Writes the converted pages into [folder] inside [workspace], picking a new
  /// folder name if it already exists. Returns the folder used.
  static Future<String> writeInto(Workspace workspace, String folder, ImportResult result) async {
    var target = folder;
    for (var i = 2; await workspace.exists(target); i++) {
      target = '$folder ($i)';
    }
    await workspace.createFolder(target);
    for (final page in result.pages) {
      await workspace.write(p.posix.join(target, page.path), page.markdown, mustNotExist: true);
    }
    return target;
  }
}

/// Turns one AppFlowy document (blocks + children_map + text_map) into Markdown.
class _DocumentConverter {
  _DocumentConverter(this.doc, {required this.title, required this.linkTo, required this.warn});

  final Map<String, dynamic> doc;
  final String title;
  final (String, String)? Function(String pageId) linkTo;
  final void Function(String) warn;

  late final blocks = (doc['blocks'] as Map<String, dynamic>).cast<String, Map<String, dynamic>>();
  late final childrenMap = ((doc['meta'] as Map?)?['children_map'] as Map? ?? {}).cast<String, dynamic>();
  late final textMap = ((doc['meta'] as Map?)?['text_map'] as Map? ?? {}).cast<String, dynamic>();
  final _unknown = <String>{};

  String convert() {
    final pageId = doc['page_id'] as String?;
    final root = blocks[pageId] ?? blocks.values.firstWhere((b) => b['ty'] == 'page', orElse: () => {});
    final out = StringBuffer();
    final body = _blocks(_kids(root), 0).trimRight();
    // Most AppFlowy pages start with their own title as a heading; don't add a second one.
    if (!RegExp('^# ${RegExp.escape(title)}\\s*(\n|\$)').hasMatch(body)) out.write('# $title\n\n');
    out.write(body);
    out.write('\n');
    return out.toString();
  }

  List<Map<String, dynamic>> _kids(Map<String, dynamic> block) {
    final key = block['children'] as String? ?? '';
    final ids = (childrenMap[key] as List?) ?? const [];
    return [
      for (final id in ids)
        if (blocks[id] != null) blocks[id]!,
    ];
  }

  String _text(Map<String, dynamic> block) {
    if (block['external_type'] != 'text') return '';
    final raw = textMap[block['external_id']];
    if (raw is! String || raw.isEmpty) return '';
    final ops = jsonDecode(raw) as List;
    final out = StringBuffer();
    for (final op in ops.cast<Map<String, dynamic>>()) {
      final insert = op['insert'];
      if (insert is! String) continue;
      out.write(_inline(insert, (op['attributes'] as Map?)?.cast<String, dynamic>() ?? const {}));
    }
    return out.toString();
  }

  String _inline(String text, Map<String, dynamic> a) {
    final mention = a['mention'];
    if (mention is Map) {
      final pageId = mention['page_id'] as String?;
      if (pageId != null) {
        final link = linkTo(pageId);
        if (link != null) return '[${link.$1}](${link.$2})';
        warn('a link to a page that is not in the export was dropped');
        return '';
      }
      final date = mention['date'];
      if (date != null) return '$date';
      return text == '\$' ? '' : text;
    }
    if (text.isEmpty || text.trim().isEmpty) return text;
    // Keep surrounding spaces outside the markers, or Markdown won't format them.
    final lead = text.substring(0, text.length - text.trimLeft().length);
    final trail = text.substring(text.trimRight().length);
    var s = text.trim();
    if (a['code'] == true) s = s.contains('`') ? '`` $s ``' : '`$s`';
    if (a['strikethrough'] == true) s = '~~$s~~';
    if (a['italic'] == true) s = '_${s}_';
    if (a['bold'] == true) s = '**$s**';
    if (a['href'] is String) s = '[$s](${a['href']})';
    return '$lead$s$trail';
  }

  String _blocks(List<Map<String, dynamic>> list, int depth) {
    final out = StringBuffer();
    var number = 0;
    for (final block in list) {
      final type = block['ty'] as String? ?? '';
      number = type == 'numbered_list' ? number + 1 : 0;
      final md = _block(block, depth, number);
      if (md == null) continue;
      out.write(md);
      // List items sit together; everything else gets a blank line after it.
      final listy = type.endsWith('_list');
      out.write(listy ? '\n' : '\n\n');
    }
    return out.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  String? _block(Map<String, dynamic> block, int depth, int number) {
    final type = block['ty'] as String? ?? '';
    final data = (block['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final indent = '  ' * depth;
    final text = _text(block);
    final kids = _kids(block);
    String nested() => kids.isEmpty ? '' : '\n${_blocks(kids, depth + 1).trimRight()}';
    switch (type) {
      case 'heading':
        final level = ((data['level'] as num?) ?? 1).clamp(1, 6).toInt();
        return '${'#' * level} $text${nested()}';
      case 'paragraph':
        return '$indent$text${nested()}';
      case 'bulleted_list':
        return '$indent- $text${nested()}';
      case 'numbered_list':
        final n = (data['number'] as num?)?.toInt() ?? number;
        return '$indent$n. $text${nested()}';
      case 'todo_list':
        return '$indent- [${data['checked'] == true ? 'x' : ' '}] $text${nested()}';
      case 'quote':
        return '$indent> $text${nested()}';
      case 'callout':
        final icon = data['icon'] is String && (data['icon'] as String).isNotEmpty ? '${data['icon']} ' : '';
        return '$indent> $icon$text${nested()}';
      case 'toggle_list':
        return '$indent- $text${nested()}';
      case 'divider':
        return '---';
      case 'code':
        final raw = textMap[block['external_id']];
        final code = raw is String && raw.isNotEmpty
            ? (jsonDecode(raw) as List).map((op) => op is Map && op['insert'] is String ? op['insert'] : '').join()
            : '';
        final fence = code.contains('```') ? '````' : '```';
        return '$fence${data['language'] ?? ''}\n$code\n$fence';
      case 'math_equation':
        return '\$\$\n${data['formula'] ?? ''}\n\$\$';
      case 'image':
        final url = Uri.decodeFull('${data['url'] ?? ''}');
        final local = !url.startsWith('http');
        if (local) warn('image "$url" is not in the export, so it shows as a link');
        return '$indent![${p.basename(url)}](${url.replaceAll(' ', '%20')})';
      case 'simple_table':
        return _table(block);
      case 'page':
        return _blocks(kids, depth).trimRight();
      default:
        if (_unknown.add(type)) warn('"$type" blocks were imported as plain text');
        return '$indent$text${nested()}';
    }
  }

  String _table(Map<String, dynamic> table) {
    final rows = [
      for (final row in _kids(table))
        [
          for (final cell in _kids(row))
            _kids(cell).map(_text).where((t) => t.isNotEmpty).join(' ').replaceAll('|', r'\|').replaceAll('\n', ' '),
        ],
    ];
    if (rows.isEmpty) return '';
    final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    String line(List<String> cells) => '| ${[...cells, for (var i = cells.length; i < width; i++) ''].join(' | ')} |';
    return [
      line(rows.first),
      '|${List.filled(width, ' --- ').join('|')}|',
      for (final row in rows.skip(1)) line(row),
    ].join('\n');
  }
}
