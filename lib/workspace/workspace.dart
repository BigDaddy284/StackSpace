import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Thrown for anything the user or the AI asked the workspace to do that it
/// can't, such as reading a missing page or escaping the workspace folder.
class WorkspaceException implements Exception {
  WorkspaceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One file or folder in the workspace. [path] is relative to the workspace
/// root and always uses forward slashes, on Windows too.
class WorkspaceEntry {
  const WorkspaceEntry({
    required this.path,
    required this.isFolder,
    this.size = 0,
    this.modified,
  });

  final String path;
  final bool isFolder;
  final int size;
  final DateTime? modified;

  /// Pictures, archives and other files that are not text: they are kept in
  /// the folder (pages reference them) but are not pages.
  bool get isBinary => !isFolder && binaryExtensions.contains(p.extension(path).toLowerCase());

  static const binaryExtensions = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.ico', '.svg', '.tif', '.tiff', '.heic', //
    '.pdf', '.zip', '.7z', '.rar', '.gz', '.tar', '.exe', '.dll', '.msi', //
    '.mp3', '.wav', '.ogg', '.m4a', '.mp4', '.mov', '.avi', '.mkv', '.webm', //
    '.ttf', '.otf', '.woff', '.woff2', '.db', '.sqlite',
  };

  String get name => p.posix.basename(path);
  int get depth => '/'.allMatches(path).length;
  String get parent => p.posix.dirname(path) == '.' ? '' : p.posix.dirname(path);
}

enum WorkspaceChangeKind { created, modified, deleted, renamed }

/// Who made a change. The editor uses this to decide whether to reload a page
/// it has open.
enum ChangeSource { user, ai }

class WorkspaceChange {
  const WorkspaceChange(this.kind, this.path, this.source, {this.newPath});
  final WorkspaceChangeKind kind;
  final String path;
  final String? newPath;
  final ChangeSource source;
}

/// A workspace is a plain folder on disk. Every text file in it is a page, and
/// sub-folders group pages. Deleted pages are moved to `.trash` instead of being
/// removed, so nothing the AI deletes is lost.
class Workspace extends ChangeNotifier {
  Workspace(String root) : root = p.normalize(p.absolute(root));

  final String root;
  static const trashFolder = '.trash';

  final _changes = StreamController<WorkspaceChange>.broadcast();
  Stream<WorkspaceChange> get changes => _changes.stream;

  List<WorkspaceEntry> _entries = const [];
  List<WorkspaceEntry> get entries => _entries;

  /// Line ending each page had when it was read, so saving keeps CRLF files CRLF.
  final Map<String, String> _lineEndings = {};

  String get name => p.basename(root);

  Future<void> init() async {
    await Directory(root).create(recursive: true);
    await refresh();
  }

  Future<void> refresh() async {
    final dir = Directory(root);
    final found = <WorkspaceEntry>[];
    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        final rel = toRelative(entity.path);
        if (rel.split('/').any((part) => part.startsWith('.'))) continue;
        if (entity is Directory) {
          found.add(WorkspaceEntry(path: rel, isFolder: true));
        } else if (entity is File) {
          final stat = await entity.stat();
          found.add(WorkspaceEntry(
            path: rel,
            isFolder: false,
            size: stat.size,
            modified: stat.modified,
          ));
        }
      }
    }
    found.sort(_compareEntries);
    _entries = found;
    notifyListeners();
  }

  /// Folders before files at each level, then case-insensitive by name.
  static int _compareEntries(WorkspaceEntry a, WorkspaceEntry b) {
    final aParts = a.path.split('/');
    final bParts = b.path.split('/');
    for (var i = 0; i < aParts.length && i < bParts.length; i++) {
      if (aParts[i] == bParts[i]) continue;
      final aIsFolder = i < aParts.length - 1 || a.isFolder;
      final bIsFolder = i < bParts.length - 1 || b.isFolder;
      if (aIsFolder != bIsFolder) return aIsFolder ? -1 : 1;
      return aParts[i].toLowerCase().compareTo(bParts[i].toLowerCase());
    }
    return aParts.length.compareTo(bParts.length);
  }

  /// The text files: what the sidebar shows, the assistant searches and the
  /// editor opens first. Pictures and other binary files are left out.
  List<WorkspaceEntry> get pages => _entries.where((e) => !e.isFolder && !e.isBinary).toList();

  /// Turns a workspace-relative path into an absolute one, rejecting anything
  /// that would land outside the workspace folder.
  String resolve(String relativePath) {
    var cleaned = relativePath.trim().replaceAll('\\', '/');
    while (cleaned.startsWith('./')) {
      cleaned = cleaned.substring(2);
    }
    if (cleaned.isEmpty) throw WorkspaceException('A path is required.');
    if (p.isAbsolute(cleaned) || cleaned.startsWith('/') || RegExp(r'^[a-zA-Z]:').hasMatch(cleaned)) {
      throw WorkspaceException('Use a path relative to the workspace, not "$relativePath".');
    }
    final absolute = p.normalize(p.join(root, cleaned));
    if (!p.isWithin(root, absolute)) {
      throw WorkspaceException('"$relativePath" is outside the workspace.');
    }
    return absolute;
  }

  String toRelative(String absolutePath) => p.relative(absolutePath, from: root).replaceAll('\\', '/');

  /// Normalises a relative path to the form used in [entries].
  String normalize(String relativePath) => toRelative(resolve(relativePath));

  Future<bool> exists(String relativePath) async {
    final path = resolve(relativePath);
    return await File(path).exists() || await Directory(path).exists();
  }

  Future<bool> isFolder(String relativePath) => Directory(resolve(relativePath)).exists();

  /// Reads a page as text with `\n` line endings.
  Future<String> read(String relativePath) async {
    final rel = normalize(relativePath);
    final file = File(resolve(rel));
    if (!await file.exists()) {
      if (await Directory(file.path).exists()) {
        throw WorkspaceException('"$rel" is a folder, not a page.');
      }
      throw WorkspaceException('Page "$rel" does not exist.');
    }
    final String raw;
    try {
      raw = await file.readAsString();
    } on FileSystemException catch (e) {
      // dart:io reports undecodable bytes as a FileSystemException with no OS error.
      if (e.osError == null) throw WorkspaceException('"$rel" is not a text file.');
      rethrow;
    } on FormatException {
      throw WorkspaceException('"$rel" is not a text file.');
    }
    if (raw.contains('\r\n')) {
      _lineEndings[rel] = '\r\n';
      return raw.replaceAll('\r\n', '\n');
    }
    _lineEndings[rel] = '\n';
    return raw;
  }

  /// Writes a page, creating parent folders. With [mustNotExist] it refuses to
  /// overwrite an existing page.
  Future<void> write(
    String relativePath,
    String content, {
    ChangeSource source = ChangeSource.user,
    bool mustNotExist = false,
  }) async {
    final rel = normalize(relativePath);
    final file = File(resolve(rel));
    if (await Directory(file.path).exists()) {
      throw WorkspaceException('"$rel" is a folder, not a page.');
    }
    final existed = await file.exists();
    if (mustNotExist && existed) {
      throw WorkspaceException('Page "$rel" already exists.');
    }
    await file.parent.create(recursive: true);
    final eol = _lineEndings[rel] ?? '\n';
    final text = eol == '\n' ? content : content.replaceAll('\n', eol);
    await file.writeAsString(text, encoding: utf8, flush: true);
    _lineEndings[rel] = eol;
    _emit(WorkspaceChange(existed ? WorkspaceChangeKind.modified : WorkspaceChangeKind.created, rel, source));
    if (!existed) await refresh();
  }

  Future<void> createFolder(String relativePath, {ChangeSource source = ChangeSource.user}) async {
    final rel = normalize(relativePath);
    if (rel.isEmpty || rel == '.') throw WorkspaceException('Give the folder a name.');
    if (await exists(rel)) throw WorkspaceException('"$rel" already exists.');
    await Directory(resolve(rel)).create(recursive: true);
    _emit(WorkspaceChange(WorkspaceChangeKind.created, rel, source));
    await refresh();
  }

  /// Moves a page or folder into `.trash/<timestamp>/` and returns where it went
  /// (relative to the workspace), so it can be restored.
  Future<String> delete(String relativePath, {ChangeSource source = ChangeSource.user}) async {
    final rel = normalize(relativePath);
    final from = resolve(rel);
    final isDir = await Directory(from).exists();
    if (!isDir && !await File(from).exists()) {
      throw WorkspaceException('"$rel" does not exist.');
    }
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final trashRel = '$trashFolder/$stamp/$rel';
    final to = p.join(root, trashRel);
    await Directory(p.dirname(to)).create(recursive: true);
    if (isDir) {
      await Directory(from).rename(to);
    } else {
      await File(from).rename(to);
    }
    _lineEndings.remove(rel);
    _emit(WorkspaceChange(WorkspaceChangeKind.deleted, rel, source));
    await refresh();
    return trashRel;
  }

  /// Moves something out of the trash back to [relativePath].
  Future<void> restore(String trashPath, String relativePath, {ChangeSource source = ChangeSource.user}) async {
    final from = p.normalize(p.join(root, trashPath));
    final to = resolve(relativePath);
    if (await File(to).exists() || await Directory(to).exists()) {
      throw WorkspaceException('Cannot restore: "$relativePath" already exists.');
    }
    await Directory(p.dirname(to)).create(recursive: true);
    if (await Directory(from).exists()) {
      await Directory(from).rename(to);
    } else {
      await File(from).rename(to);
    }
    _emit(WorkspaceChange(WorkspaceChangeKind.created, normalize(relativePath), source));
    await refresh();
  }

  Future<void> rename(String fromPath, String toPath, {ChangeSource source = ChangeSource.user}) async {
    final fromRel = normalize(fromPath);
    final toRel = normalize(toPath);
    final from = resolve(fromRel);
    final to = resolve(toRel);
    if (await File(to).exists() || await Directory(to).exists()) {
      throw WorkspaceException('"$toRel" already exists.');
    }
    await Directory(p.dirname(to)).create(recursive: true);
    if (await Directory(from).exists()) {
      await Directory(from).rename(to);
    } else if (await File(from).exists()) {
      await File(from).rename(to);
    } else {
      throw WorkspaceException('"$fromRel" does not exist.');
    }
    final eol = _lineEndings.remove(fromRel);
    if (eol != null) _lineEndings[toRel] = eol;
    _emit(WorkspaceChange(WorkspaceChangeKind.renamed, fromRel, source, newPath: toRel));
    await refresh();
  }

  /// Copies a page, or a folder with everything in it (sub-pages, pictures),
  /// into [intoFolder] ('' is the top of the workspace) and returns the
  /// copy's path. A name that is taken gets " copy", then " copy 2" and so
  /// on, so pasting next to the original makes a duplicate.
  Future<String> copy(String fromPath, String intoFolder, {ChangeSource source = ChangeSource.user}) async {
    final fromRel = normalize(fromPath);
    final from = resolve(fromRel);
    final intoRel = intoFolder.trim().isEmpty ? '' : normalize(intoFolder);
    final into = intoRel.isEmpty ? root : resolve(intoRel);
    final isDir = await Directory(from).exists();
    if (!isDir && !await File(from).exists()) {
      throw WorkspaceException('"$fromRel" does not exist.');
    }
    if (intoRel.isNotEmpty && await File(into).exists()) {
      throw WorkspaceException('"$intoRel" is a page, not a folder.');
    }

    final name = p.posix.basename(fromRel);
    final ext = isDir ? '' : p.posix.extension(name);
    final stem = name.substring(0, name.length - ext.length);
    var to = p.join(into, name);
    for (var n = 1; await File(to).exists() || await Directory(to).exists(); n++) {
      to = p.join(into, '$stem copy${n == 1 ? '' : ' $n'}$ext');
    }

    if (isDir) {
      // List first, so a folder pasted into itself copies what it held, once.
      final contents = await Directory(from).list(recursive: true, followLinks: false).toList();
      await Directory(to).create(recursive: true);
      for (final entity in contents) {
        final target = p.join(to, p.relative(entity.path, from: from));
        if (entity is Directory) {
          await Directory(target).create(recursive: true);
        } else if (entity is File) {
          await Directory(p.dirname(target)).create(recursive: true);
          await entity.copy(target);
        }
      }
    } else {
      await Directory(into).create(recursive: true);
      await File(from).copy(to);
    }
    final toRel = toRelative(to);
    _emit(WorkspaceChange(WorkspaceChangeKind.created, toRel, source));
    await refresh();
    return toRel;
  }

  /// Moves a page or folder into [intoFolder] ('' is the top of the
  /// workspace), keeping its name, and returns its new path. Moving it to
  /// where it already is does nothing; a folder cannot go inside itself.
  Future<String> move(String fromPath, String intoFolder, {ChangeSource source = ChangeSource.user}) async {
    final fromRel = normalize(fromPath);
    final intoRel = intoFolder.trim().isEmpty ? '' : normalize(intoFolder);
    if (intoRel == fromRel || intoRel.startsWith('$fromRel/')) {
      throw WorkspaceException('"$fromRel" cannot be moved inside itself.');
    }
    if (intoRel.isNotEmpty && await File(resolve(intoRel)).exists()) {
      throw WorkspaceException('"$intoRel" is a page, not a folder.');
    }
    final name = p.posix.basename(fromRel);
    final toRel = intoRel.isEmpty ? name : '$intoRel/$name';
    if (toRel == fromRel) return fromRel;
    await rename(fromRel, toRel, source: source);
    return toRel;
  }

  void _emit(WorkspaceChange change) {
    if (!_changes.isClosed) _changes.add(change);
  }

  @override
  void dispose() {
    _changes.close();
    super.dispose();
  }
}
