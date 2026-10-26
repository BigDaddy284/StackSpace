import 'dart:async';

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

  Workspace get ws => widget.workspace;

  @override
  void initState() {
    super.initState();
    _collapsed = widget.settings.collapsedFolders(ws.root);
    _changes = ws.changes.listen(_onWorkspaceChange);
  }

  @override
  void didUpdateWidget(Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      _changes?.cancel();
      _collapsed = widget.settings.collapsedFolders(ws.root);
      _changes = ws.changes.listen(_onWorkspaceChange);
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  /// A renamed or moved folder keeps its folded state under its new path; a
  /// deleted one leaves nothing behind.
  void _onWorkspaceChange(WorkspaceChange change) {
    bool under(String folder) => folder == change.path || folder.startsWith('${change.path}/');
    if (!_collapsed.any(under)) return;
    switch (change.kind) {
      case WorkspaceChangeKind.renamed:
        final to = change.newPath!;
        _collapsed = {
          for (final f in _collapsed) under(f) ? to + f.substring(change.path.length) : f,
        };
      case WorkspaceChangeKind.deleted:
        _collapsed.removeWhere(under);
      case WorkspaceChangeKind.created || WorkspaceChangeKind.modified:
        return;
    }
    // The change arrives before the folder list is refreshed, so no pruning here.
    _saveCollapsed(prune: false);
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

  /// Rows to show: pages, and folders that hold a page somewhere below them
  /// (a folder of pictures only is hidden with its pictures); nothing under
  /// a collapsed folder.
  List<WorkspaceEntry> _visible(List<WorkspaceEntry> entries) {
    final hasPage = <String>{};
    for (final e in entries) {
      if (e.isFolder || e.isBinary) continue;
      final parts = e.path.split('/');
      for (var i = 1; i < parts.length; i++) {
        hasPage.add(parts.sublist(0, i).join('/'));
      }
    }
    return [
      for (final e in entries)
        if (!e.isBinary &&
            (!e.isFolder || hasPage.contains(e.path)) &&
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

  Future<void> rename(String path) async {
    final name = await promptDialog(context, title: 'Rename', label: 'New path', initial: path, confirmLabel: 'Rename');
    if (name == null || name.trim().isEmpty || name.trim() == path) return;
    try {
      await ws.rename(path, name.trim());
    } on WorkspaceException catch (err) {
      if (mounted) showError(context, err.message);
    }
  }

  Future<void> delete(String path) async {
    final folder = await ws.isFolder(path);
    if (!mounted) return;
    final ok = await confirmDialog(context,
        title: 'Delete ${folder ? 'folder' : 'page'}?',
        message: '"$path" will be moved to the workspace trash (.trash folder).',
        confirmLabel: 'Delete',
        destructive: true);
    if (ok) await ws.delete(path);
  }

  Future<void> newFolder() async {
    final name = await promptDialog(context, title: 'New folder', label: 'Name', initial: 'New folder');
    if (name == null || name.trim().isEmpty) return;
    try {
      await ws.createFolder(name.trim());
    } on WorkspaceException catch (err) {
      if (mounted) showError(context, err.message);
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
            const HintText('Every text file in this folder is a page. Right-click a page, or press F2 or Delete, '
                'to rename or remove it.'),
            const SizedBox(height: 14),
            const SectionLabel('Pages'),
            const SizedBox(height: 6),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([ws, widget.editor]),
                builder: (context, _) {
                  final entries = _visible(ws.entries);
                  if (entries.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: HintText('No pages yet. Create one below, or ask the assistant to.'),
                    );
                  }
                  return ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, i) => _row(entries[i]),
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

  Widget _row(WorkspaceEntry e) {
    final p = StackColors.of(context);
    final collapsed = _collapsed.contains(e.path);
    final selected = !e.isFolder && widget.editor.path == e.path;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MergeSemantics(
        child: Semantics(
          label: selected && widget.editor.dirty ? '${e.name}, unsaved changes' : e.name,
          button: true,
          selected: selected,
          expanded: e.isFolder ? !collapsed : null,
          hint: 'F2 to rename, Delete to delete, or right-click for more',
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.f2): () => rename(e.path),
              const SingleActivator(LogicalKeyboardKey.delete): () => delete(e.path),
            },
            child: SsRow(
              selected: selected,
              onTap: () {
                if (e.isFolder) {
                  _toggleFolder(e.path, collapsed: collapsed);
                } else {
                  widget.editor.open(e.path);
                }
              },
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
                  if (selected && widget.editor.dirty)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Tooltip(
                        message: 'Unsaved changes',
                        child: Icon(Icons.circle, size: 7, color: p.accentA),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(WorkspaceEntry e, Offset position) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        if (e.isFolder) const PopupMenuItem(value: 'new', child: Text('New page here')),
        const PopupMenuItem(value: 'rename', child: Text('Rename / move')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    switch (choice) {
      case 'new':
        await widget.onNewPage(e.path);
      case 'rename':
        await rename(e.path);
      case 'delete':
        await delete(e.path);
    }
  }
}
