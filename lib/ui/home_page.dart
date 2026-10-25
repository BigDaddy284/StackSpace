import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/chat_controller.dart';
import '../ai/workspace_tools.dart';
import '../app/settings.dart';
import '../editor/page_editor_controller.dart';
import '../workspace/workspace.dart';
import 'chat/chat_dock.dart';
import 'dialogs.dart';
import 'editor_pane.dart';
import 'settings_dialog.dart';
import 'sidebar.dart';

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
  bool _ready = false;

  AppSettings get settings => widget.settings;

  @override
  void initState() {
    super.initState();
    _openWorkspace(settings.workspacePath);
  }

  Future<void> _openWorkspace(String path) async {
    final workspace = Workspace(path);
    await workspace.init();
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
    });
    final first = workspace.pages.firstOrNull;
    if (first != null) await editor.open(first.path);
    await chat.connect();
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

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true): _toggleDock,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _editor.flush,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newPage,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 260,
                child: Sidebar(
                  workspace: _workspace,
                  editor: _editor,
                  onNewPage: _newPage,
                  onOpenSettings: _openSettings,
                  settings: settings,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: ListenableBuilder(
                  listenable: _chat,
                  builder: (context, _) => ChatDockLayout(
                    mode: _dock,
                    height: settings.dockHeight,
                    onHeightChanged: (h) => settings.dockHeight = h,
                    onModeChanged: (mode) => setState(() => _dock = mode),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
