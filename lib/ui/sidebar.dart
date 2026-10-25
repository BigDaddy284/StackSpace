import 'package:flutter/material.dart';

import '../editor/page_editor_controller.dart';
import '../workspace/workspace.dart';
import 'dialogs.dart';

/// The page tree on the left.
class Sidebar extends StatefulWidget {
  const Sidebar({
    super.key,
    required this.workspace,
    required this.editor,
    required this.onNewPage,
    required this.onOpenSettings,
  });

  final Workspace workspace;
  final PageEditorController editor;
  final Future<void> Function([String folder]) onNewPage;
  final VoidCallback onOpenSettings;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final Set<String> _collapsed = {};

  Workspace get ws => widget.workspace;

  List<WorkspaceEntry> _visible(List<WorkspaceEntry> entries) => [
        for (final e in entries)
          if (!_collapsed.any((folder) => e.path.startsWith('$folder/'))) e,
      ];

  static IconData _iconFor(WorkspaceEntry e, bool collapsed) {
    if (e.isFolder) return collapsed ? Icons.folder_outlined : Icons.folder_open_outlined;
    final ext = e.name.contains('.') ? e.name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'md' || 'markdown' || 'txt' => Icons.description_outlined,
      'json' || 'yaml' || 'yml' || 'toml' || 'xml' => Icons.data_object,
      _ => Icons.code,
    };
  }

  Future<void> _rename(WorkspaceEntry e) async {
    final name = await promptDialog(context, title: 'Rename', label: 'New path', initial: e.path, confirmLabel: 'Rename');
    if (name == null || name.trim().isEmpty || name.trim() == e.path) return;
    try {
      await ws.rename(e.path, name.trim());
    } on WorkspaceException catch (err) {
      if (mounted) showError(context, err.message);
    }
  }

  Future<void> _delete(WorkspaceEntry e) async {
    final ok = await confirmDialog(context,
        title: 'Delete ${e.isFolder ? 'folder' : 'page'}?',
        message: '"${e.path}" will be moved to the workspace trash (.trash folder).',
        confirmLabel: 'Delete',
        destructive: true);
    if (ok) await ws.delete(e.path);
  }

  Future<void> _newFolder() async {
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: Row(
              children: [
                Icon(Icons.layers_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: ws.root,
                    child: Text(ws.name, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                  ),
                ),
                IconButton(
                  tooltip: 'New page (Ctrl+N)',
                  icon: const Icon(Icons.note_add_outlined, size: 20),
                  onPressed: () => widget.onNewPage(),
                ),
                IconButton(
                  tooltip: 'New folder',
                  icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                  onPressed: _newFolder,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([ws, widget.editor]),
              builder: (context, _) {
                final entries = _visible(ws.entries);
                if (entries.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No pages yet. Create one, or ask the assistant to.',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _row(entries[i]),
                );
              },
            ),
          ),
          const Divider(),
          ListTile(
            dense: true,
            leading: const Icon(Icons.settings_outlined, size: 20),
            title: const Text('Settings'),
            onTap: widget.onOpenSettings,
          ),
        ],
      ),
    );
  }

  Widget _row(WorkspaceEntry e) {
    final scheme = Theme.of(context).colorScheme;
    final collapsed = _collapsed.contains(e.path);
    final selected = !e.isFolder && widget.editor.path == e.path;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            if (e.isFolder) {
              setState(() => collapsed ? _collapsed.remove(e.path) : _collapsed.add(e.path));
            } else {
              widget.editor.open(e.path);
            }
          },
          onSecondaryTapDown: (details) => _showMenu(e, details.globalPosition),
          child: SizedBox(
            height: 30,
            child: Row(
              children: [
                SizedBox(width: 8.0 + e.depth * 14),
                Icon(_iconFor(e, collapsed), size: 17, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(e.name, overflow: TextOverflow.ellipsis)),
                if (selected && widget.editor.dirty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.circle, size: 7, color: scheme.primary),
                  ),
              ],
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
        await _rename(e);
      case 'delete':
        await _delete(e);
    }
  }
}
