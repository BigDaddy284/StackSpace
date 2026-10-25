import 'dart:math' as math;

import '../workspace/workspace.dart';

/// Asks the user to approve something the AI wants to do. Returns false to refuse.
typedef ConfirmAction = Future<bool> Function(String title, String message);

enum AiEditKind { created, modified, deleted, renamed }

/// A change the AI made, with enough information to undo it.
class AiEdit {
  AiEdit({required this.kind, required this.path, this.newPath, this.before, this.trashPath});

  final AiEditKind kind;
  final String path;
  final String? newPath;

  /// Page text before the change, for [AiEditKind.modified].
  final String? before;

  /// Where a deleted page went, for [AiEditKind.deleted].
  final String? trashPath;
  bool reverted = false;
}

class ToolOutcome {
  const ToolOutcome({required this.result, required this.summary, this.isError = false, this.edit});

  /// Text sent back to the model.
  final String result;

  /// One line shown in the chat, e.g. "Edited notes.md (lines 4-9)".
  final String summary;
  final bool isError;
  final AiEdit? edit;
}

/// The tools the local model can call to work on pages in the workspace.
class WorkspaceTools {
  WorkspaceTools(this.workspace, {this.confirm, this.confirmDeletes = true});

  final Workspace workspace;
  ConfirmAction? confirm;
  bool confirmDeletes;

  static const maxReadLines = 400;
  static const maxReadChars = 40000;
  static const maxSearchHits = 50;
  static const _maxSearchFileBytes = 2 * 1024 * 1024;

  static Map<String, dynamic> _fn(String name, String description, Map<String, dynamic> properties,
          List<String> required) =>
      {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': {'type': 'object', 'properties': properties, 'required': required},
        },
      };

  static const _path = {'type': 'string', 'description': 'Page path relative to the workspace, e.g. "notes/todo.md".'};

  List<Map<String, dynamic>> get definitions => [
        _fn('list_pages', 'List pages and folders in the workspace.', {
          'folder': {'type': 'string', 'description': 'Only list inside this folder. Omit for everything.'},
        }, []),
        _fn(
            'read_page',
            'Read a page. Lines come back numbered like "12| text"; the number and "| " are not part of the text. '
                'Long pages are returned in parts; use start_line to read further.',
            {
              'path': _path,
              'start_line': {'type': 'integer', 'description': 'First line to read (1-based). Default 1.'},
              'end_line': {'type': 'integer', 'description': 'Last line to read, inclusive.'},
            },
            ['path']),
        _fn('search_pages', 'Find lines containing some text (case-insensitive) across all pages.', {
          'query': {'type': 'string', 'description': 'Text to look for.'},
        }, ['query']),
        _fn('create_page', 'Create a new page. Fails if it already exists. Missing folders are created.', {
          'path': _path,
          'content': {'type': 'string', 'description': 'Full text of the new page.'},
        }, ['path', 'content']),
        _fn('write_page', 'Replace the whole text of an existing page. Prefer replace_text or edit_lines for small changes.', {
          'path': _path,
          'content': {'type': 'string', 'description': 'New full text of the page.'},
        }, ['path', 'content']),
        _fn(
            'replace_text',
            'Replace an exact piece of text in a page. old_text must match exactly once unless replace_all is true.',
            {
              'path': _path,
              'old_text': {'type': 'string', 'description': 'Exact text to find, including whitespace.'},
              'new_text': {'type': 'string', 'description': 'Text to put in its place.'},
              'replace_all': {'type': 'boolean', 'description': 'Replace every match. Default false.'},
            },
            ['path', 'old_text', 'new_text']),
        _fn('edit_lines', 'Replace lines start_line..end_line (inclusive, 1-based) of a page with new_text. Use an empty new_text to delete the lines.', {
          'path': _path,
          'start_line': {'type': 'integer'},
          'end_line': {'type': 'integer'},
          'new_text': {'type': 'string'},
        }, ['path', 'start_line', 'end_line', 'new_text']),
        _fn('insert_lines', 'Insert text after a line of a page. Use after_line 0 to insert at the top.', {
          'path': _path,
          'after_line': {'type': 'integer'},
          'text': {'type': 'string'},
        }, ['path', 'after_line', 'text']),
        _fn('rename_page', 'Rename or move a page or folder.', {
          'path': _path,
          'new_path': {'type': 'string', 'description': 'New path relative to the workspace.'},
        }, ['path', 'new_path']),
        _fn('delete_page', 'Delete a page or folder. It is moved to the workspace trash, and the user may be asked to approve.', {
          'path': _path,
        }, ['path']),
      ];

  Future<ToolOutcome> run(String name, Map<String, dynamic> args) async {
    try {
      switch (name) {
        case 'list_pages':
          return await _list(args);
        case 'read_page':
          return await _read(args);
        case 'search_pages':
          return await _search(args);
        case 'create_page':
          return await _create(args);
        case 'write_page':
          return await _writeAll(args);
        case 'replace_text':
          return await _replace(args);
        case 'edit_lines':
          return await _editLines(args);
        case 'insert_lines':
          return await _insertLines(args);
        case 'rename_page':
          return await _rename(args);
        case 'delete_page':
          return await _delete(args);
        default:
          return _error('Unknown tool "$name".', 'Unknown tool $name');
      }
    } on WorkspaceException catch (e) {
      return _error(e.message, '${_label(name)} failed: ${e.message}');
    } on _ArgumentProblem catch (e) {
      return _error(e.message, '${_label(name)} failed: ${e.message}');
    }
  }

  Future<void> revert(AiEdit edit) async {
    if (edit.reverted) return;
    switch (edit.kind) {
      case AiEditKind.created:
        await workspace.delete(edit.path);
      case AiEditKind.modified:
        await workspace.write(edit.path, edit.before ?? '');
      case AiEditKind.deleted:
        await workspace.restore(edit.trashPath!, edit.path);
      case AiEditKind.renamed:
        await workspace.rename(edit.newPath!, edit.path);
    }
    edit.reverted = true;
  }

  static String _label(String tool) => switch (tool) {
        'list_pages' => 'List pages',
        'read_page' => 'Read',
        'search_pages' => 'Search',
        'create_page' => 'Create',
        'write_page' || 'replace_text' || 'edit_lines' || 'insert_lines' => 'Edit',
        'rename_page' => 'Rename',
        'delete_page' => 'Delete',
        _ => tool,
      };

  ToolOutcome _error(String message, String summary) =>
      ToolOutcome(result: 'Error: $message', summary: summary, isError: true);

  Future<ToolOutcome> _list(Map<String, dynamic> args) async {
    await workspace.refresh();
    final folder = _optString(args, 'folder');
    final prefix = folder == null || folder.isEmpty ? '' : '${workspace.normalize(folder)}/';
    final entries = workspace.entries.where((e) => e.path.startsWith(prefix)).toList();
    if (entries.isEmpty) {
      return ToolOutcome(result: 'No pages${prefix.isEmpty ? '' : ' in "$folder"'}.', summary: 'Listed pages');
    }
    final lines = [
      for (final e in entries) e.isFolder ? '${e.path}/' : '${e.path} (${e.size} bytes)',
    ];
    return ToolOutcome(result: lines.join('\n'), summary: 'Listed ${entries.length} items');
  }

  Future<ToolOutcome> _read(Map<String, dynamic> args) async {
    final path = workspace.normalize(_string(args, 'path'));
    final text = await workspace.read(path);
    final lines = text.split('\n');
    final total = lines.length;
    final start = math.max(1, _optInt(args, 'start_line') ?? 1);
    if (start > total) {
      return _error('"$path" has only $total lines.', 'Read $path failed');
    }
    var end = math.min(total, _optInt(args, 'end_line') ?? total);
    end = math.min(end, start + maxReadLines - 1);
    final width = '$end'.length;
    final buffer = StringBuffer();
    var last = start - 1;
    for (var i = start; i <= end; i++) {
      final line = '${'$i'.padLeft(width)}| ${lines[i - 1]}\n';
      if (buffer.length + line.length > maxReadChars && i > start) break;
      buffer.write(line);
      last = i;
    }
    var result = buffer.toString();
    if (last < total) {
      result += '\n[Showing lines $start-$last of $total. Call read_page with start_line ${last + 1} for more.]';
    }
    final range = start == 1 && last == total ? '' : ' (lines $start-$last)';
    return ToolOutcome(result: result, summary: 'Read $path$range');
  }

  Future<ToolOutcome> _search(Map<String, dynamic> args) async {
    final query = _string(args, 'query');
    final needle = query.toLowerCase();
    await workspace.refresh();
    final hits = <String>[];
    var truncated = false;
    for (final page in workspace.pages) {
      if (page.size > _maxSearchFileBytes) continue;
      final String text;
      try {
        text = await workspace.read(page.path);
      } on WorkspaceException {
        continue;
      }
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].toLowerCase().contains(needle)) continue;
        if (hits.length == maxSearchHits) {
          truncated = true;
          break;
        }
        final line = lines[i].length > 200 ? '${lines[i].substring(0, 200)}...' : lines[i];
        hits.add('${page.path}:${i + 1}: $line');
      }
      if (truncated) break;
    }
    if (hits.isEmpty) return ToolOutcome(result: 'No matches for "$query".', summary: 'Searched for "$query"');
    final more = truncated ? '\n[Stopped at $maxSearchHits matches.]' : '';
    return ToolOutcome(result: hits.join('\n') + more, summary: 'Searched for "$query" (${hits.length} matches)');
  }

  Future<ToolOutcome> _create(Map<String, dynamic> args) async {
    final path = workspace.normalize(_string(args, 'path'));
    final content = _string(args, 'content', allowEmpty: true);
    await workspace.write(path, content, source: ChangeSource.ai, mustNotExist: true);
    final lines = content.isEmpty ? 0 : content.split('\n').length;
    return ToolOutcome(
      result: 'Created "$path" ($lines lines).',
      summary: 'Created $path',
      edit: AiEdit(kind: AiEditKind.created, path: path),
    );
  }

  Future<ToolOutcome> _writeAll(Map<String, dynamic> args) async {
    final path = workspace.normalize(_string(args, 'path'));
    final content = _string(args, 'content', allowEmpty: true);
    final before = await workspace.read(path);
    await workspace.write(path, content, source: ChangeSource.ai);
    return ToolOutcome(
      result: 'Rewrote "$path".',
      summary: 'Rewrote $path',
      edit: AiEdit(kind: AiEditKind.modified, path: path, before: before),
    );
  }

  Future<ToolOutcome> _replace(Map<String, dynamic> args) async {
    final path = workspace.normalize(_string(args, 'path'));
    final oldText = _string(args, 'old_text');
    final newText = _string(args, 'new_text', allowEmpty: true);
    final all = args['replace_all'] == true;
    final before = await workspace.read(path);
    final count = oldText.allMatches(before).length;
    if (count == 0) {
      return _error('old_text was not found in "$path". Read the page again and copy the text exactly.',
          'Edit $path failed: text not found');
    }
    if (count > 1 && !all) {
      return _error('old_text matches $count places in "$path". Include more surrounding text, or set replace_all.',
          'Edit $path failed: text matched $count places');
    }
    final after = all ? before.replaceAll(oldText, newText) : before.replaceFirst(oldText, newText);
    await workspace.write(path, after, source: ChangeSource.ai);
    final line = before.substring(0, before.indexOf(oldText)).split('\n').length;
    return ToolOutcome(
      result: 'Replaced $count occurrence${count == 1 ? '' : 's'} in "$path".',
      summary: count == 1 ? 'Edited $path (line $line)' : 'Edited $path ($count places)',
      edit: AiEdit(kind: AiEditKind.modified, path: path, before: before),
    );
  }

  Future<ToolOutcome> _editLines(Map<String, dynamic> args) async {
    final path = workspace.normalize(_string(args, 'path'));
    final start = _int(args, 'start_line');
    final end = _int(args, 'end_line');
    final newText = _string(args, 'new_text', allowEmpty: true);
    final before = await workspace.read(path);
    final lines = before.split('\n');
    if (start < 1 || end < start || end > lines.length) {
      return _error('Lines $start-$end are out of range; "$path" has ${lines.length} lines.',
          'Edit $path failed: lines out of range');
    }
    final replacement = newText.isEmpty ? <String>[] : newText.split('\n');
    lines.replaceRange(start - 1, end, replacement);
    await workspace.write(path, lines.join('\n'), source: ChangeSource.ai);
    return ToolOutcome(
      result: 'Replaced lines $start-$end of "$path" with ${replacement.length} lines.',
      summary: start == end ? 'Edited $path (line $start)' : 'Edited $path (lines $start-$end)',
      edit: AiEdit(kind: AiEditKind.modified, path: path, before: before),
    );
  }

  Future<ToolOutcome> _insertLines(Map<String, dynamic> args) async {
    final path = workspace.normalize(_string(args, 'path'));
    final after = _int(args, 'after_line');
    final text = _string(args, 'text', allowEmpty: true);
    final before = await workspace.read(path);
    final lines = before.split('\n');
    if (after < 0 || after > lines.length) {
      return _error('after_line $after is out of range; "$path" has ${lines.length} lines.',
          'Edit $path failed: line out of range');
    }
    final inserted = text.split('\n');
    lines.insertAll(after, inserted);
    await workspace.write(path, lines.join('\n'), source: ChangeSource.ai);
    return ToolOutcome(
      result: 'Inserted ${inserted.length} lines after line $after of "$path".',
      summary: 'Inserted ${inserted.length} lines into $path',
      edit: AiEdit(kind: AiEditKind.modified, path: path, before: before),
    );
  }

  Future<ToolOutcome> _rename(Map<String, dynamic> args) async {
    final path = workspace.normalize(_string(args, 'path'));
    final newPath = workspace.normalize(_string(args, 'new_path'));
    await workspace.rename(path, newPath, source: ChangeSource.ai);
    return ToolOutcome(
      result: 'Renamed "$path" to "$newPath".',
      summary: 'Renamed $path to $newPath',
      edit: AiEdit(kind: AiEditKind.renamed, path: path, newPath: newPath),
    );
  }

  Future<ToolOutcome> _delete(Map<String, dynamic> args) async {
    final path = workspace.normalize(_string(args, 'path'));
    if (!await workspace.exists(path)) {
      return _error('"$path" does not exist.', 'Delete $path failed: not found');
    }
    final ask = confirm;
    if (confirmDeletes && ask != null) {
      final folder = await workspace.isFolder(path);
      final ok = await ask('Delete ${folder ? 'folder' : 'page'}?',
          'The assistant wants to delete "$path". It will be moved to the workspace trash.');
      if (!ok) {
        return _error('The user declined to delete "$path". Do not try again unless they ask.',
            'Delete $path declined');
      }
    }
    final trash = await workspace.delete(path, source: ChangeSource.ai);
    return ToolOutcome(
      result: 'Deleted "$path" (moved to trash).',
      summary: 'Deleted $path',
      edit: AiEdit(kind: AiEditKind.deleted, path: path, trashPath: trash),
    );
  }

  static String _string(Map<String, dynamic> args, String key, {bool allowEmpty = false}) {
    final value = args[key];
    if (value is! String || (!allowEmpty && value.isEmpty)) {
      if (value == null && allowEmpty) return '';
      throw _ArgumentProblem('"$key" is required and must be text.');
    }
    return value;
  }

  static String? _optString(Map<String, dynamic> args, String key) {
    final value = args[key];
    return value is String ? value : null;
  }

  static int _int(Map<String, dynamic> args, String key) {
    final value = _optInt(args, key);
    if (value == null) throw _ArgumentProblem('"$key" is required and must be a whole number.');
    return value;
  }

  /// Small models often send numbers as strings, so accept both.
  static int? _optInt(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}

class _ArgumentProblem implements Exception {
  _ArgumentProblem(this.message);
  final String message;
}
