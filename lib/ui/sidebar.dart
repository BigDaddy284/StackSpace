import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/settings.dart';
import '../app/theme.dart';
import '../editor/page_editor_controller.dart';
import '../workspace/workspace.dart';
import 'dialogs.dart';
import 'widgets/controls.dart';

/// The left panel, laid out like Stills & Reels' "Edit picture" panel: a
/// title, a hint, then labelled sections.
class Sidebar extends StatefulWidget {
  const Sidebar({
    super.key,
    required this.workspace,
    required this.editor,
    required this.settings,
    required this.onNewPage,
  });

  final Workspace workspace;
  final PageEditorController editor;
  final AppSettings settings;
  final Future<void> Function([String folder]) onNewPage;

  @override
  State<Sidebar> createState() => SidebarState();
}

class SidebarState extends State<Sidebar> {
  /// Folded folders. Kept in the settings per workspace (Bug 3), so the
  /// state survives hiding the panel (which unmounts it) and a restart.
  late Set<String> _collapsed;
  StreamSubscription<WorkspaceChange>? _changes;

  /// Rows picked with Ctrl+click, Shift+click or a click on a folder. Empty
  /// means the open page is the selection, as it is after a plain click on
  /// a page.
  Set<String> _selection = {};

  /// Where a Shift+click range starts.
  String? _anchor;

  /// What Copy or Cut put aside for Paste; [_cut] makes Paste a move.
  List<String> clipboard = const [];
  bool _cut = false;

  /// The folder a drag would drop into ('' is the top of the workspace).
  String? _dropFolder;
  Timer? _springOpen;

  final _listFocus = FocusNode(debugLabel: 'Pages');
  String? _openPath;

  Workspace get ws => widget.workspace;

  @override
  void initState() {
    super.initState();
    _collapsed = widget.settings.collapsedFolders(ws.root);
    _changes = ws.changes.listen(_onWorkspaceChange);
    _openPath = widget.editor.path;
    widget.editor.addListener(_onEditorChange);
  }

  @override
  void didUpdateWidget(Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      _changes?.cancel();
      _collapsed = widget.settings.collapsedFolders(ws.root);
      _changes = ws.changes.listen(_onWorkspaceChange);
      _selection = {};
      clipboard = const [];
    }
    if (oldWidget.editor != widget.editor) {
      oldWidget.editor.removeListener(_onEditorChange);
      widget.editor.addListener(_onEditorChange);
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    _springOpen?.cancel();
    widget.editor.removeListener(_onEditorChange);
    _listFocus.dispose();
    super.dispose();
  }

  /// Opening another page (from the editor, Ctrl+N or the assistant) makes
  /// it the selection again.
  void _onEditorChange() {
    final path = widget.editor.path;
    if (path == _openPath) return;
    _openPath = path;
    if (_selection.isNotEmpty && mounted) setState(() => _selection = {});
  }

  /// A renamed or moved folder keeps its folded state under its new path; a
  /// deleted one leaves nothing behind. The selection and the clipboard
  /// follow the same way.
  void _onWorkspaceChange(WorkspaceChange change) {
    bool under(String path) => path == change.path || path.startsWith('${change.path}/');
    String follow(String path) => change.newPath! + path.substring(change.path.length);
    switch (change.kind) {
      case WorkspaceChangeKind.renamed:
        _selection = {for (final s in _selection) under(s) ? follow(s) : s};
        clipboard = [for (final c in clipboard) under(c) ? follow(c) : c];
        if (_anchor != null && under(_anchor!)) _anchor = follow(_anchor!);
      case WorkspaceChangeKind.deleted:
        _selection = {..._selection}..removeWhere(under);
        clipboard = [...clipboard]..removeWhere(under);
      case WorkspaceChangeKind.created || WorkspaceChangeKind.modified:
        return;
    }
    if (_collapsed.any(under)) {
      if (change.kind == WorkspaceChangeKind.renamed) {
        _collapsed = {for (final f in _collapsed) under(f) ? follow(f) : f};
      } else {
        _collapsed.removeWhere(under);
      }
      // The change arrives before the folder list is refreshed, so no pruning here.
      _saveCollapsed(prune: false);
    }
    if (mounted) setState(() {});
  }

  void _toggleFolder(String path, {required bool collapsed}) {
    setState(() => collapsed ? _collapsed.remove(path) : _collapsed.add(path));
    _saveCollapsed();
  }

  /// Writes the folded set, without folders that no longer exist.
  void _saveCollapsed({bool prune = true}) {
    if (prune && ws.entries.isNotEmpty) {
      final folders = {
        for (final e in ws.entries)
          if (e.isFolder) e.path
      };
      _collapsed.removeWhere((f) => !folders.contains(f));
    }
    widget.settings.setCollapsedFolders(ws.root, _collapsed);
  }

  /// Rows to show: pages, empty folders, and folders that hold a page
  /// somewhere below them (a folder holding nothing but pictures is hidden
  /// with its pictures); nothing under a collapsed folder.
  List<WorkspaceEntry> _visible(List<WorkspaceEntry> entries) {
    final hasPage = <String>{};
    final hasFile = <String>{};
    for (final e in entries) {
      if (e.isFolder) continue;
      final parts = e.path.split('/');
      for (var i = 1; i < parts.length; i++) {
        final folder = parts.sublist(0, i).join('/');
        hasFile.add(folder);
        if (!e.isBinary) hasPage.add(folder);
      }
    }
    return [
      for (final e in entries)
        if (!e.isBinary &&
            (!e.isFolder || hasPage.contains(e.path) || !hasFile.contains(e.path)) &&
            !_collapsed.any((folder) => e.path.startsWith('$folder/')))
          e,
    ];
  }

  static IconData _iconFor(WorkspaceEntry e, bool collapsed) {
    if (e.isFolder) return collapsed ? Icons.folder_outlined : Icons.folder_open_outlined;
    final ext = e.name.contains('.') ? e.name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'md' || 'markdown' || 'txt' => Icons.description_outlined,
      'json' || 'yaml' || 'yml' || 'toml' || 'xml' => Icons.data_object,
      _ => Icons.code,
    };
  }

  /// Whether a row shows as selected.
  bool _isSelected(WorkspaceEntry e) =>
      _selection.isEmpty ? !e.isFolder && widget.editor.path == e.path : _selection.contains(e.path);

  /// What an action on [e] acts on: the whole selection when [e] is part of
  /// it, otherwise [e] alone. Rows inside a picked folder go with the folder.
  List<String> targetsFor(WorkspaceEntry e) {
    if (!_selection.contains(e.path) || _selection.length < 2) return [e.path];
    return _outermost(_selection);
  }

  /// [paths] without those inside another one of them, in sidebar order.
  List<String> _outermost(Iterable<String> paths) {
    final set = paths.toSet();
    final order = {for (final (i, e) in ws.entries.indexed) e.path: i};
    return set.where((path) => !set.any((other) => path.startsWith('$other/'))).toList()
      ..sort((a, b) => (order[a] ?? 1 << 30).compareTo(order[b] ?? 1 << 30));
  }

  /// A click on a row: Ctrl adds or removes it, Shift picks the range from
  /// the last clicked row, and a plain click opens the page or folds the folder.
  void _click(WorkspaceEntry e, List<WorkspaceEntry> visible) {
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed) {
      setState(() {
        final open = widget.editor.path;
        final picked = _selection.isEmpty && open != null ? {open} : {..._selection};
        if (!picked.remove(e.path)) picked.add(e.path);
        _selection = picked;
        _anchor = e.path;
      });
      _listFocus.requestFocus();
      return;
    }
    if (keys.isShiftPressed) {
      final from = visible.indexWhere((v) => v.path == (_anchor ?? widget.editor.path));
      final to = visible.indexOf(e);
      if (from >= 0 && to >= 0) {
        final (lo, hi) = from <= to ? (from, to) : (to, from);
        setState(() => _selection = {for (final v in visible.sublist(lo, hi + 1)) v.path});
        _listFocus.requestFocus();
        return;
      }
    }
    _anchor = e.path;
    if (e.isFolder) {
      _selection = {e.path};
      _toggleFolder(e.path, collapsed: _collapsed.contains(e.path));
      _listFocus.requestFocus();
    } else {
      setState(() => _selection = {});
      widget.editor.open(e.path);
    }
  }

  Future<void> rename(String path) async {
    final name = await promptDialog(context, title: 'Rename', label: 'New path', initial: path, confirmLabel: 'Rename');
    if (name == null || name.trim().isEmpty || name.trim() == path) return;
    try {
      await ws.rename(path, name.trim());
    } on WorkspaceException catch (err) {
      if (mounted) showError(context, err.message);
    }
  }

  Future<void> delete(String path) => deleteAll([path]);

  /// Moves [paths] to the trash after asking once.
  Future<void> deleteAll(List<String> paths) async {
    if (paths.isEmpty) return;
    final String title;
    final String message;
    if (paths.length == 1) {
      final folder = await ws.isFolder(paths.single);
      title = 'Delete ${folder ? 'folder' : 'page'}?';
      message = '"${paths.single}" will be moved to the workspace trash (.trash folder).';
    } else {
      title = 'Delete ${paths.length} items?';
      message = '${paths.map((path) => '"$path"').join(', ')} will be moved to the workspace trash (.trash folder).';
    }
    if (!mounted) return;
    final ok = await confirmDialog(context, title: title, message: message, confirmLabel: 'Delete', destructive: true);
    if (!ok) return;
    await _each(paths, (path) => ws.delete(path), 'delete');
    if (mounted) setState(() => _selection = {});
  }

  /// Puts [paths] aside for Paste, which makes a copy of each.
  void copy(List<String> paths) => setState(() {
        clipboard = List.unmodifiable(paths);
        _cut = false;
      });

  /// Puts [paths] aside for Paste, which moves them. They show faded until then.
  void cut(List<String> paths) => setState(() {
        clipboard = List.unmodifiable(paths);
        _cut = true;
      });

  /// Pastes into [folder] ('' is the top of the workspace): a copy of each
  /// page or folder put aside, with all it holds (sub-pages, pictures), or,
  /// after Cut, the pages and folders themselves.
  Future<void> paste(String folder) async {
    final items = clipboard;
    if (items.isEmpty) return;
    final move = _cut;
    if (move) {
      await _move(items, folder);
      if (mounted) setState(() => clipboard = const []);
    } else {
      await _copy(items, folder);
    }
  }

  /// Makes a copy of each of [paths] next to it.
  Future<void> duplicate(List<String> paths) async {
    for (final path in paths) {
      await _copy([path], _parentOf(path));
    }
  }

  Future<void> _copy(List<String> paths, String folder) async {
    await _flushIfInside(paths);
    await _each(paths, (path) => ws.copy(path, folder), 'copy');
    _unfold(folder);
  }

  Future<void> _move(List<String> paths, String folder) async {
    await _flushIfInside(paths);
    await _each(paths, (path) => ws.move(path, folder), 'move');
    _unfold(folder);
  }

  /// Unsaved edits to the open page are written first, so a copy has them.
  Future<void> _flushIfInside(List<String> paths) async {
    final open = widget.editor.path;
    if (open != null && paths.any((path) => open == path || open.startsWith('$path/'))) {
      await widget.editor.flush();
    }
  }

  /// Runs [action] on each path; a problem with one is shown and the rest go on.
  Future<void> _each(List<String> paths, Future<Object?> Function(String) action, String verb) async {
    final problems = <String>[];
    for (final path in paths) {
      try {
        await action(path);
      } on WorkspaceException catch (err) {
        problems.add(err.message);
      } on FileSystemException catch (err) {
        problems.add('Could not $verb "$path": ${err.osError?.message ?? err.message}');
      }
    }
    if (problems.isNotEmpty && mounted) showError(context, problems.join('\n'));
  }

  /// Opens a folded folder so what was just put in it shows.
  void _unfold(String folder) {
    if (folder.isNotEmpty && _collapsed.contains(folder) && mounted) _toggleFolder(folder, collapsed: true);
  }

  /// Whether dropping [paths] into [folder] moves at least one of them:
  /// none may go inside itself, and something must not be there already.
  static bool canDrop(List<String> paths, String folder) =>
      paths.every((path) => folder != path && !folder.startsWith('$path/')) &&
      paths.any((path) => _parentOf(path) != folder);

  /// The folder holding [path] ('' at the top of the workspace).
  static String _parentOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }

  /// Drops dragged rows into [folder]: a move, or a copy with Ctrl held,
  /// as in File Explorer.
  Future<void> _drop(List<String> paths, String folder) async {
    _springOpen?.cancel();
    setState(() => _dropFolder = null);
    if (HardwareKeyboard.instance.isControlPressed) {
      await _copy(paths, folder);
    } else if (canDrop(paths, folder)) {
      await _move(paths, folder);
    }
  }

  void _dragOver(String? folder) {
    if (_dropFolder == folder) return;
    _springOpen?.cancel();
    setState(() => _dropFolder = folder);
    // Holding a drag over a folded folder opens it, so it can be dropped deeper.
    if (folder != null && folder.isNotEmpty && _collapsed.contains(folder)) {
      _springOpen = Timer(const Duration(milliseconds: 700), () {
        if (mounted && _dropFolder == folder) _toggleFolder(folder, collapsed: true);
      });
    }
  }

  void _dragLeave(String folder) {
    if (_dropFolder == folder) {
      _springOpen?.cancel();
      setState(() => _dropFolder = null);
    }
  }

  /// The folder a paste or drop on [e] lands in: the folder itself, or a page's folder.
  static String _folderOf(WorkspaceEntry e) => e.isFolder ? e.path : e.parent;

  /// Ctrl+C, Ctrl+X, Ctrl+V, Ctrl+D, F2 and Delete, acting on [e] (or the
  /// selection holding it).
  Map<ShortcutActivator, VoidCallback> _shortcuts(WorkspaceEntry? e) {
    List<String> targets() {
      if (e != null) return targetsFor(e);
      if (_selection.isNotEmpty) return _outermost(_selection);
      final open = widget.editor.path;
      return open == null ? const [] : [open];
    }

    String folder() {
      if (e != null) return _folderOf(e);
      final t = targets();
      if (t.length != 1) return '';
      final entry = ws.entries.where((x) => x.path == t.single).firstOrNull;
      return entry == null ? '' : _folderOf(entry);
    }

    return {
      const SingleActivator(LogicalKeyboardKey.f2): () {
        final t = targets();
        if (t.length == 1) rename(t.single);
      },
      const SingleActivator(LogicalKeyboardKey.delete): () => deleteAll(targets()),
      const SingleActivator(LogicalKeyboardKey.keyC, control: true): () => copy(targets()),
      const SingleActivator(LogicalKeyboardKey.keyX, control: true): () => cut(targets()),
      const SingleActivator(LogicalKeyboardKey.keyV, control: true): () => paste(folder()),
      const SingleActivator(LogicalKeyboardKey.keyD, control: true): () => duplicate(targets()),
      const SingleActivator(LogicalKeyboardKey.escape): () => setState(() => _selection = {}),
    };
  }

  /// Asks for a name and creates the folder (inside [parent] when given).
  /// A slash in the name makes nested folders. Problems are shown, never
  /// swallowed (Bug 4).
  Future<void> newFolder([String parent = '']) async {
    final initial = parent.isEmpty ? 'New folder' : '$parent/New folder';
    final name = await promptDialog(context, title: 'New folder', label: 'Name', initial: initial);
    if (name == null || name.trim().isEmpty) return;
    try {
      await ws.createFolder(name.trim());
    } on WorkspaceException catch (err) {
      if (mounted) showError(context, err.message);
    } on FileSystemException catch (err) {
      if (mounted) showError(context, 'Could not create "${name.trim()}": ${err.osError?.message ?? err.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    return ColoredBox(
      color: p.panel,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Tooltip(message: ws.root, child: PanelTitle(ws.name)),
            const SizedBox(height: 6),
            const HintText('Every text file in this folder is a page. Drag to move one (hold Ctrl to copy), '
                'or right-click for more.'),
            const SizedBox(height: 14),
            const SectionLabel('Pages'),
            const SizedBox(height: 6),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([ws, widget.editor]),
                builder: (context, _) {
                  final entries = _visible(ws.entries);
                  // The space around the rows is the top of the workspace: right-click
                  // it to paste or create there, drop on it to move out of folders.
                  return CallbackShortcuts(
                    bindings: _shortcuts(null),
                    child: Focus(
                      focusNode: _listFocus,
                      includeSemantics: false,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        excludeFromSemantics: true,
                        onSecondaryTapDown: (details) => _showMenu(null, details.globalPosition),
                        child: DragTarget<List<String>>(
                          onWillAcceptWithDetails: (d) {
                            _dragOver(canDrop(d.data, '') ? '' : null);
                            return true;
                          },
                          onLeave: (_) => _dragLeave(''),
                          onAcceptWithDetails: (d) => _drop(d.data, ''),
                          builder: (context, _, __) => DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: _dropFolder == '' ? p.accentA : Colors.transparent, width: 1.4),
                            ),
                            child: entries.isEmpty
                                ? const Align(
                                    alignment: Alignment.topLeft,
                                    child: Padding(
                                      padding: EdgeInsets.only(top: 4),
                                      child: HintText('No pages yet. Create one below, or ask the assistant to.'),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: entries.length,
                                    itemBuilder: (context, i) => _row(entries[i], entries),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            const SectionLabel('Create'),
            const SizedBox(height: 6),
            SsButton(
              icon: Icons.note_add_outlined,
              label: 'New page',
              tooltip: 'New page (Ctrl+N)',
              alignLeft: true,
              width: double.infinity,
              onPressed: () => widget.onNewPage(),
            ),
            const SizedBox(height: 8),
            SsButton(
              icon: Icons.create_new_folder_outlined,
              label: 'New folder',
              alignLeft: true,
              width: double.infinity,
              onPressed: newFolder,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(WorkspaceEntry e, List<WorkspaceEntry> visible) {
    final p = StackColors.of(context);
    final collapsed = _collapsed.contains(e.path);
    final selected = _isSelected(e);
    final open = !e.isFolder && widget.editor.path == e.path;
    final isCut = _cut && clipboard.any((c) => e.path == c || e.path.startsWith('$c/'));
    final folder = _folderOf(e);
    final targets = targetsFor(e);
    Widget row = SsRow(
      selected: selected,
      onTap: () => _click(e, visible),
      onSecondaryTapDown: (details) => _showMenu(e, details.globalPosition),
      child: Row(
        children: [
          SizedBox(width: 8.0 + e.depth * 14),
          Icon(_iconFor(e, collapsed), size: 17, color: selected ? p.text : p.subText),
          const SizedBox(width: 8),
          Expanded(
            child: ExcludeSemantics(
              child: Text(
                e.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.text, fontSize: StackType.button),
              ),
            ),
          ),
          if (open && widget.editor.dirty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Tooltip(
                message: 'Unsaved changes',
                child: Icon(Icons.circle, size: 7, color: p.accentA),
              ),
            ),
        ],
      ),
    );
    if (isCut) row = Opacity(opacity: 0.5, child: row);
    if (e.isFolder && _dropFolder == e.path) {
      row = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.accentA, width: 1.4),
        ),
        child: row,
      );
    }
    // Dropping on a folder puts the rows in it; dropping on a page puts them
    // beside it, in its folder (which is outlined while dragging over).
    final dropRow = row;
    row = DragTarget<List<String>>(
      onWillAcceptWithDetails: (d) {
        _dragOver(canDrop(d.data, folder) ? folder : null);
        return true;
      },
      onLeave: (_) => _dragLeave(folder),
      onAcceptWithDetails: (d) => _drop(d.data, folder),
      builder: (context, _, __) => dropRow,
    );
    final dragRow = row;
    row = Draggable<List<String>>(
      data: targets,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragChip(label: targets.length == 1 ? e.name : '${targets.length} items', icon: _iconFor(e, true)),
      childWhenDragging: Opacity(opacity: 0.5, child: dragRow),
      onDragEnd: (_) => _dragLeave(_dropFolder ?? ''),
      child: dragRow,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MergeSemantics(
        child: Semantics(
          label: open && widget.editor.dirty ? '${e.name}, unsaved changes' : e.name,
          button: true,
          selected: selected,
          expanded: e.isFolder ? !collapsed : null,
          hint: 'Ctrl+C copy, Ctrl+X cut, Ctrl+V paste, Ctrl+D duplicate, F2 rename, Delete, or right-click for more',
          child: CallbackShortcuts(bindings: _shortcuts(e), child: row),
        ),
      ),
    );
  }

  PopupMenuEntry<String> _item(String value, String label, {String? shortcut, bool enabled = true}) {
    final p = StackColors.of(context);
    return PopupMenuItem(
      value: value,
      enabled: enabled,
      child: Row(children: [
        Expanded(child: Text(label)),
        if (shortcut != null) ...[
          const SizedBox(width: 24),
          Text(shortcut, style: TextStyle(color: p.subText, fontSize: StackType.hint)),
        ],
      ]),
    );
  }

  /// The right-click menu of a row, or of the space around the rows when
  /// [e] is null (that one acts on the top of the workspace).
  Future<void> _showMenu(WorkspaceEntry? e, Offset position) async {
    final targets = e == null ? const <String>[] : targetsFor(e);
    final many = targets.length > 1;
    final what = many ? '${targets.length} items' : (e?.isFolder ?? false) ? 'folder' : 'page';
    final held = clipboard.length == 1 ? '"${clipboard.single.split('/').last}"' : '${clipboard.length} items';
    final pasteLabel = clipboard.isEmpty
        ? 'Paste'
        : e != null && e.isFolder
            ? 'Paste $held into this folder'
            : 'Paste $held here';
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        if (e == null || (e.isFolder && !many)) ...[
          _item('new', 'New page here'),
          _item('newFolder', 'New folder here'),
          const PopupMenuDivider(),
        ],
        if (e != null) ...[
          _item('cut', 'Cut $what', shortcut: 'Ctrl+X'),
          _item('copy', 'Copy $what', shortcut: 'Ctrl+C'),
        ],
        _item('paste', pasteLabel, shortcut: 'Ctrl+V', enabled: clipboard.isNotEmpty),
        if (e != null) ...[
          _item('duplicate', 'Duplicate', shortcut: 'Ctrl+D'),
          const PopupMenuDivider(),
          _item('rename', 'Rename / move', shortcut: 'F2', enabled: !many),
          _item('delete', many ? 'Delete $what' : 'Delete', shortcut: 'Delete'),
        ],
      ],
    );
    final folder = e == null ? '' : _folderOf(e);
    switch (choice) {
      case 'new':
        await widget.onNewPage(folder);
      case 'newFolder':
        await newFolder(folder);
      case 'cut':
        cut(targets);
      case 'copy':
        copy(targets);
      case 'paste':
        await paste(folder);
      case 'duplicate':
        await duplicate(targets);
      case 'rename':
        await rename(e!.path);
      case 'delete':
        await deleteAll(targets);
    }
  }
}

/// What follows the pointer while dragging rows.
class _DragChip extends StatelessWidget {
  const _DragChip({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.accentA, width: 1.2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: p.subText),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: p.text, fontSize: StackType.button)),
        ]),
      ),
    );
  }
}
