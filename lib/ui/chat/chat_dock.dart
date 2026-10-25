import 'package:flutter/material.dart';

import '../../ai/chat_controller.dart';
import '../../app/theme.dart';
import '../../editor/page_editor_controller.dart';
import '../widgets/controls.dart';
import 'chat_messages.dart';
import 'composer.dart';

/// closed: hidden (open it from the top bar or Ctrl+J). minimized: just the
/// header bar. open: docked under the editor at a height the user can drag.
/// maximized: fills the editor area.
enum DockMode { closed, minimized, open, maximized }

/// Places the chat dock under [content] according to [mode].
class ChatDockLayout extends StatelessWidget {
  const ChatDockLayout({
    super.key,
    required this.mode,
    required this.height,
    required this.onHeightChanged,
    required this.content,
    required this.dock,
  });

  final DockMode mode;
  final double height;
  final ValueChanged<double> onHeightChanged;
  final Widget content;
  final Widget dock;

  static const minHeight = 220.0;

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case DockMode.closed:
        return content;
      case DockMode.minimized:
        return Column(children: [Expanded(child: content), dock]);
      case DockMode.maximized:
        return dock;
      case DockMode.open:
        return LayoutBuilder(builder: (context, constraints) {
          final maxHeight = (constraints.maxHeight - 120).clamp(minHeight, double.infinity);
          final h = height.clamp(minHeight, maxHeight);
          return Column(
            children: [
              Expanded(child: content),
              _ResizeHandle(onDrag: (dy) => onHeightChanged((h - dy).clamp(minHeight, maxHeight))),
              SizedBox(height: h, child: dock),
            ],
          );
        });
    }
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDrag});
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
        child: Container(
          height: 5,
          color: p.panel,
          alignment: Alignment.topCenter,
          child: Container(height: 1, color: p.barBorder),
        ),
      ),
    );
  }
}

class ChatPanel extends StatelessWidget {
  const ChatPanel({
    super.key,
    required this.chat,
    required this.editor,
    required this.mode,
    required this.onModeChanged,
    required this.onOpenSettings,
  });

  final ChatController chat;
  final PageEditorController editor;
  final DockMode mode;
  final ValueChanged<DockMode> onModeChanged;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    return Material(
      color: p.panel,
      child: Column(
        children: [
          if (mode == DockMode.minimized) Container(height: 1, color: p.barBorder),
          _Header(chat: chat, mode: mode, onModeChanged: onModeChanged),
          if (mode != DockMode.minimized) ...[
            Expanded(child: ChatMessages(chat: chat, onOpenSettings: onOpenSettings)),
            Composer(chat: chat, editor: editor),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.chat, required this.mode, required this.onModeChanged});

  final ChatController chat;
  final DockMode mode;
  final ValueChanged<DockMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    final (dotColor, statusText, statusWord) = switch (chat.status) {
      OllamaStatus.connected => (p.success, chat.model ?? 'No model', 'connected'),
      OllamaStatus.connecting => (p.warning, 'Connecting...', 'connecting'),
      OllamaStatus.offline => (p.error, 'Ollama offline', 'offline'),
      OllamaStatus.unknown => (p.subText, 'Not connected', 'not connected'),
    };
    final minimized = mode == DockMode.minimized;
    final maximized = mode == DockMode.maximized;
    final textStyle = TextStyle(color: p.text, fontSize: StackType.button);
    return GestureDetector(
      onTap: minimized ? () => onModeChanged(DockMode.open) : null,
      child: Container(
        height: 46,
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: Row(
          children: [
            ShaderMask(
              shaderCallback: (r) => p.accentGradient.createShader(r),
              child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Semantics(
              header: true,
              child: Text('Assistant', style: StackType.display(15, p.text)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Row(children: [
                Flexible(
                  child: Tooltip(
                    message: chat.statusMessage ??
                        (chat.status == OllamaStatus.connected
                            ? 'Connected to Ollama ${chat.ollamaVersion ?? ''} at ${chat.settings.ollamaUrl}'
                            : chat.settings.ollamaUrl),
                    child: Semantics(
                      liveRegion: true,
                      label: 'Ollama $statusWord',
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: p.control, borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.circle, size: 8, color: dotColor),
                          const SizedBox(width: 7),
                          Flexible(child: Text(statusText, style: textStyle, overflow: TextOverflow.ellipsis)),
                          if (chat.status == OllamaStatus.connected && chat.capabilities.thinking) ...[
                            Container(
                              width: 1,
                              height: 14,
                              margin: const EdgeInsets.symmetric(horizontal: 9),
                              color: p.pillSep,
                            ),
                            Flexible(
                              child: Text('Thinking: ${chat.thinkLevel.label}',
                                  style: textStyle, overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ]),
                      ),
                    ),
                  ),
                ),
                if (chat.busy) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: p.accentA,
                      semanticsLabel: 'Assistant is working',
                    ),
                  ),
                ],
              ]),
            ),
            if (!minimized)
              SsButton(
                compact: true,
                icon: Icons.add_comment_outlined,
                tooltip: 'New chat',
                width: 40,
                height: 34,
                onPressed: chat.items.isEmpty ? null : chat.newChat,
              ),
            SsButton(
              compact: true,
              icon: minimized ? Icons.expand_less : Icons.expand_more,
              tooltip: minimized ? 'Restore' : 'Minimize',
              width: 40,
              height: 34,
              iconSize: 20,
              onPressed: () => onModeChanged(minimized ? DockMode.open : DockMode.minimized),
            ),
            SsButton(
              compact: true,
              icon: maximized ? Icons.close_fullscreen : Icons.open_in_full,
              tooltip: maximized ? 'Restore size' : 'Maximize',
              width: 40,
              height: 34,
              iconSize: 16,
              onPressed: () => onModeChanged(maximized ? DockMode.open : DockMode.maximized),
            ),
            SsButton(
              compact: true,
              icon: Icons.close,
              tooltip: 'Close (Ctrl+J)',
              width: 40,
              height: 34,
              onPressed: () => onModeChanged(DockMode.closed),
            ),
          ],
        ),
      ),
    );
  }
}
