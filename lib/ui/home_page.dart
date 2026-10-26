import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import '../ai/chat_controller.dart';
import '../ai/workspace_tools.dart';
import '../app/settings.dart';
import '../app/startup_log.dart';
import '../app/theme.dart';
import '../editor/page_editor_controller.dart';
import '../import/appflowy_import.dart';
import '../workspace/workspace.dart';
import 'chat/chat_dock.dart';
import 'dialogs.dart';
import 'editor_pane.dart';
import 'settings_dialog.dart';
import 'sidebar.dart';
import 'widgets/controls.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.settings, this.chatFactory});

  final AppSettings settings;

  /// Lets tests swap in a fake Ollama.
  final ChatController Function(AppSettings settings, WorkspaceTools tools)? chatFactory;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Workspace _workspace;
  late WorkspaceTools _tools;
  late PageEditorController _editor;
  late ChatController _chat;
  DockMode _dock = DockMode.closed;
  bool _showSidebar = true;
  final _sidebarKey = GlobalKey<SidebarState>();
  bool _ready = false;

  AppSettings get settings => widget.settings;

  @override
  void initState() {
    super.initState();
    _openWorkspace(settings.workspacePath);
  }

  /// Why the workspace could not be opened; the page shows it with Retry.
  String? _startupError;

  Future<void> _openWorkspace(String path) async {
    StartupLog.log('opening workspace $path');
    final workspace = Workspace(path);
    try {
      await workspace.init();
    } catch (e) {
      StartupLog.log('workspace failed: $e');
      if (!mounted) return;
      setState(() => _startupError = 'The workspace folder "$path" could not be opened.\n$e');
      return;
    }
    StartupLog.log('workspace ready: ${workspace.entries.length} entries');
    final tools = WorkspaceTools(workspace, confirm: _confirm, confirmDeletes: settings.confirmDeletes);
    final editor = PageEditorController(workspace);
    final chat = widget.chatFactory?.call(settings, tools) ?? ChatController(settings: settings, tools: tools);
    chat.beforeSend = editor.flush;
    if (_ready) {
      await _editor.flush();
      _chat.dispose();
      _editor.dispose();
      _workspace.dispose();
    }
    if (!mounted) return;
    setState(() {
      _workspace = workspace;
      _tools = tools;
      _editor = editor;
      _chat = chat;
      _ready = true;
      _startupError = null;
    });
    final first = workspace.pages.firstOrNull;
    if (first != null) await editor.open(first.path);
    StartupLog.log('first page ${first?.path ?? '(none)'} open');
    await chat.connect();
    StartupLog.log('assistant ${chat.status.name}');
  }

  Future<bool> _confirm(String title, String message) async {
    if (!mounted) return false;
    return confirmDialog(context, title: title, message: message, confirmLabel: 'Delete', destructive: true);
  }

  void _toggleDock() => setState(() {
        _dock = _dock == DockMode.closed || _dock == DockMode.minimized ? DockMode.open : DockMode.closed;
      });

  Future<void> _newPage([String folder = '']) async {
    final name = await promptDialog(context,
        title: 'New page', label: 'Name', initial: folder.isEmpty ? 'Untitled.md' : '$folder/Untitled.md');
    if (name == null || name.trim().isEmpty) return;
    final path = name.contains('.') ? name.trim() : '${name.trim()}.md';
    try {
      await _workspace.write(path, '', mustNotExist: true);
      await _editor.open(path);
    } on WorkspaceException catch (e) {
      if (mounted) showError(context, e.message);
    }
  }

  Future<void> _openSettings() async {
    final changed = await showSettingsDialog(context, settings);
    if (!changed) return;
    _tools.confirmDeletes = settings.confirmDeletes;
    if (settings.workspacePath != _workspace.root) {
      await _openWorkspace(settings.workspacePath);
    } else {
      await _chat.connect();
    }
  }

  @override
  void dispose() {
    if (_ready) {
      _editor.flush();
      _chat.dispose();
      _editor.dispose();
      _workspace.dispose();
    }
    super.dispose();
  }

  Future<void> _importAppFlowy({required bool folder}) async {
    final String? source;
    if (folder) {
      source = await getDirectoryPath(confirmButtonText: 'Import');
    } else {
      final file = await openFile(acceptedTypeGroups: const [
        XTypeGroup(label: 'AppFlowy export', extensions: ['zip']),
      ]);
      source = file?.path;
    }
    if (source == null || !mounted) return;
    try {
      final result = (await AppFlowyImporter.fromPath(source)).convert();
      final name = p.basenameWithoutExtension(source).replaceAll(RegExp(r'_\d{4}-\d{2}-\d{2}_[\d-]+$'), '');
      final target = await AppFlowyImporter.writeInto(_workspace, name.isEmpty ? 'AppFlowy import' : name, result);
      await _editor.open(p.posix.join(target, result.pages.first.path));
      if (!mounted) return;
      final pages = '${result.pages.length} page${result.pages.length == 1 ? '' : 's'}';
      if (result.warnings.isEmpty) {
        showError(context, 'Imported $pages into "$target".');
      } else {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Imported $pages into "$target"'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                  child: Text('Some things need a look:\n\n${result.warnings.map((w) => '• $w').join('\n')}')),
            ),
            actions: [SsButton(label: 'OK', primary: true, onPressed: () => Navigator.pop(context))],
          ),
        );
      }
    } on FormatException catch (e) {
      if (mounted) showError(context, e.message);
    } on Exception catch (e) {
      if (mounted) showError(context, 'Could not import: $e');
    }
  }

  void _cycleTheme() {
    settings.themeMode = switch (settings.themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    setState(() {});
  }

  String get _themeTooltip => switch (settings.themeMode) {
        ThemeMode.system => 'Theme: follow Windows. Click for light',
        ThemeMode.light => 'Theme: light. Click for dark',
        ThemeMode.dark => 'Theme: dark. Click to follow Windows',
      };

  /// File > New folder works with the panel hidden too: it shows the panel
  /// (which owns the dialog) and asks on the next frame.
  void _newFolder() {
    if (_showSidebar) {
      _sidebarKey.currentState?.newFolder();
      return;
    }
    setState(() => _showSidebar = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sidebarKey.currentState?.newFolder());
  }

  void _showShortcuts() => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Keyboard shortcuts'),
          content: const Text('Ctrl+N  New page\nCtrl+S  Save now\nCtrl+J  Show or hide the assistant\n'
              'F2  Rename the selected page\nDelete  Delete the selected page\n'
              'Ctrl+B / I / E  Bold / italic / inline code\nCtrl+K  Link the selection (again: unlink)\n'
              'Ctrl+click  Open a link\n'
              'Drag or Shift+click across table cells  Select cells (Ctrl+C / X / V, Delete)\n'
              'Drag a table column border  Set its width (double-click: even columns)\n'
              'Enter  Send a message\nShift+Enter  New line in a message'),
          actions: [SsButton(label: 'Close', primary: true, onPressed: () => Navigator.pop(context))],
        ),
      );

  void _showAbout() => showAboutDialog(
        context: context,
        applicationName: 'StackSpace',
        applicationLegalese: 'A local notes and code workspace with an Ollama assistant.\n\n'
            'Built with Flutter (flutter.dev). View licenses lists every open-source package it uses.',
      );

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    final startupError = _startupError;
    if (startupError != null && !_ready) {
      // The workspace could not be opened: say so, with a way out (Bug 5).
      return Scaffold(
        backgroundColor: p.window,
        body: EmptyState(
          icon: Icons.folder_off_outlined,
          title: 'Workspace not available',
          detail: startupError,
          actions: [
            SsButton(label: 'Try again', primary: true, onPressed: () => _openWorkspace(settings.workspacePath)),
            SsButton(label: 'Settings…', onPressed: _openSettings),
          ],
        ),
      );
    }
    if (!_ready) {
      return Scaffold(
        backgroundColor: p.window,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: p.accentA)),
            const SizedBox(height: 14),
            Text('Opening ${settings.workspacePath}…', style: TextStyle(color: p.subText, fontSize: StackType.menu)),
          ]),
        ),
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true): _toggleDock,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _editor.flush,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newPage,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: p.window,
          body: ListenableBuilder(
            listenable: Listenable.merge([_chat, _editor]),
            builder: (context, _) => Column(
              children: [
                _topBar(p),
                Expanded(
                  child: Row(
                    children: [
                      if (_showSidebar) ...[
                        SizedBox(
                          width: 260,
                          child: Sidebar(
                              key: _sidebarKey,
                              workspace: _workspace,
                              editor: _editor,
                              settings: settings,
                              onNewPage: _newPage),
                        ),
                        Container(width: 1, color: p.barBorder),
                      ],
                      Expanded(
                        child: ChatDockLayout(
                          mode: _dock,
                          height: settings.dockHeight,
                          onHeightChanged: (h) => setState(() => settings.dockHeight = h),
                          content: EditorPane(controller: _editor, locked: _chat.busy, onNewPage: _newPage),
                          dock: ChatPanel(
                            chat: _chat,
                            editor: _editor,
                            mode: _dock,
                            onModeChanged: (mode) => setState(() => _dock = mode),
                            onOpenSettings: _openSettings,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ListenableBuilder(listenable: _editor.caretChanges, builder: (context, _) => _statusBar(p)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(StackPalette p) {
    final path = _editor.path;
    MenuItemButton item(String label, VoidCallback? onPressed, {IconData? icon, String? shortcut}) => MenuItemButton(
          leadingIcon: Icon(icon, size: 17),
          trailingIcon: shortcut == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: Text(shortcut, style: TextStyle(color: p.subText, fontSize: StackType.hint)),
                ),
          onPressed: onPressed,
          child: Text(label),
        );
    MenuItemButton themeItem(String label, ThemeMode mode) => MenuItemButton(
          leadingIcon: Icon(settings.themeMode == mode ? Icons.check : null, size: 17, color: p.accentA),
          onPressed: () => setState(() => settings.themeMode = mode),
          child: Text(label),
        );
    const barItem = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, 34)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8)))),
    );
    final menus = MenuBar(
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      children: [
        SubmenuButton(menuChildren: [
          item('New page', _newPage, icon: Icons.note_add_outlined, shortcut: 'Ctrl+N'),
          item('New folder', _newFolder, icon: Icons.create_new_folder_outlined),
          item('Save', path == null ? null : _editor.flush, icon: Icons.save_outlined, shortcut: 'Ctrl+S'),
          const Divider(height: 8),
          item('Import AppFlowy export (.zip)...', () => _importAppFlowy(folder: false), icon: Icons.archive_outlined),
          item('Import AppFlowy export folder...', () => _importAppFlowy(folder: true),
              icon: Icons.drive_folder_upload_outlined),
          const Divider(height: 8),
          item('Settings...', _openSettings, icon: Icons.settings_outlined),
        ], style: barItem, child: const Text('File')),
        SubmenuButton(menuChildren: [
          item('Rename page',
              path == null || _sidebarKey.currentState == null ? null : () => _sidebarKey.currentState!.rename(path),
              icon: Icons.drive_file_rename_outline, shortcut: 'F2'),
          item('Delete page',
              path == null || _sidebarKey.currentState == null ? null : () => _sidebarKey.currentState!.delete(path),
              icon: Icons.delete_outline, shortcut: 'Del'),
        ], style: barItem, child: const Text('Edit')),
        SubmenuButton(menuChildren: [
          item(_showSidebar ? 'Hide pages panel' : 'Show pages panel',
              () => setState(() => _showSidebar = !_showSidebar),
              icon: Icons.view_sidebar_outlined),
          item(_dock == DockMode.closed ? 'Show assistant' : 'Hide assistant', _toggleDock,
              icon: Icons.auto_awesome_outlined, shortcut: 'Ctrl+J'),
          const Divider(height: 8),
          themeItem('Follow Windows', ThemeMode.system),
          themeItem('Light', ThemeMode.light),
          themeItem('Dark', ThemeMode.dark),
        ], style: barItem, child: const Text('View')),
        SubmenuButton(menuChildren: [
          item('Keyboard shortcuts', _showShortcuts, icon: Icons.keyboard_outlined),
          item('About StackSpace', _showAbout, icon: Icons.info_outline),
        ], style: barItem, child: const Text('Help')),
      ],
    );
    final dockOpen = _dock != DockMode.closed;
    return Container(
      height: 60,
      decoration: BoxDecoration(color: p.bar, border: Border(bottom: BorderSide(color: p.barBorder))),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(children: [
            ShaderMask(
              shaderCallback: (r) => p.accentGradient.createShader(r),
              child: const Icon(Icons.layers_rounded, size: 22, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Text('StackSpace', style: StackType.display(15, p.text)),
            const SizedBox(width: 12),
            menus,
            const Spacer(),
            SsButton(
              compact: true,
              icon: switch (settings.themeMode) {
                ThemeMode.system => Icons.brightness_auto_outlined,
                ThemeMode.light => Icons.light_mode_outlined,
                ThemeMode.dark => Icons.dark_mode_outlined,
              },
              tooltip: _themeTooltip,
              width: 40,
              onPressed: _cycleTheme,
            ),
            SsButton(
                compact: true, icon: Icons.settings_outlined, tooltip: 'Settings', width: 40, onPressed: _openSettings),
          ]),
          ModePill(cells: [
            ModeCell(
              icon: Icons.description_outlined,
              label: 'Pages',
              selected: _showSidebar,
              tooltip: _showSidebar ? 'Hide the pages panel' : 'Show the pages panel',
              onTap: () => setState(() => _showSidebar = !_showSidebar),
            ),
            ModeCell(
              icon: Icons.auto_awesome_outlined,
              label: 'Assistant',
              selected: dockOpen,
              tooltip: dockOpen ? 'Hide the assistant (Ctrl+J)' : 'Open the assistant (Ctrl+J)',
              onTap: _toggleDock,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _statusBar(StackPalette p) {
    final path = _editor.path;
    final (line, column) = _editor.cursor;
    final sub = TextStyle(color: p.subText, fontSize: StackType.button);
    Widget divider() =>
        Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 14), color: p.barBorder);
    final status = switch (_chat.status) {
      OllamaStatus.connected => 'Ollama: ${_chat.model ?? 'no model'}',
      OllamaStatus.connecting => 'Ollama: connecting...',
      OllamaStatus.offline => 'Ollama: offline',
      OllamaStatus.unknown => 'Ollama: not connected',
    };
    return Container(
      height: 46,
      decoration: BoxDecoration(color: p.bar, border: Border(top: BorderSide(color: p.barBorder))),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(children: [
        Expanded(
          child: Text(
            path == null ? _workspace.root : (_editor.isLarge ? path : '$path   ·   Ln $line, Col $column'),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.text, fontSize: StackType.menu),
          ),
        ),
        if (path != null) ...[
          Text(_editor.error != null ? 'Not saved' : (_editor.dirty ? 'Unsaved changes' : 'Saved'), style: sub),
          divider(),
        ],
        Text(status, style: sub),
      ]),
    );
  }
}
