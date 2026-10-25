import 'package:flutter/material.dart';

import '../../ai/chat_controller.dart';
import '../../app/theme.dart';
import '../../editor/page_editor_controller.dart';
import 'chat_messages.dart';
import 'composer.dart';

/// closed: only the "Assistant" button shows. minimized: just the header bar.
/// open: docked under the editor at a height the user can drag. maximized:
/// fills the editor area.
enum DockMode { closed, minimized, open, maximized }

/// Places the chat dock under [content] according to [mode].
class ChatDockLayout extends StatelessWidget {
  const ChatDockLayout({
    super.key,
    required this.mode,
    required this.height,
    required this.onHeightChanged,
    required this.onModeChanged,
    required this.content,
    required this.dock,
  });

  final DockMode mode;
  final double height;
  final ValueChanged<double> onHeightChanged;
  final ValueChanged<DockMode> onModeChanged;
  final Widget content;
  final Widget dock;

  static const minHeight = 220.0;

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case DockMode.closed:
        return Stack(
          children: [
            Positioned.fill(child: content),
            Positioned(
              right: 20,
              bottom: 36,
              child: Tooltip(
                message: 'Open the assistant (Ctrl+J)',
                child: _AssistantButton(onPressed: () => onModeChanged(DockMode.open)),
              ),
            ),
          ],
        );
      case DockMode.minimized:
        return Column(children: [Expanded(child: content), const Divider(), dock]);
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
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
        child: SizedBox(
          height: 7,
          child: Center(child: Container(height: 1, color: Theme.of(context).dividerTheme.color)),
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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      child: Column(
        children: [
          _Header(chat: chat, mode: mode, onModeChanged: onModeChanged),
          if (mode != DockMode.minimized) ...[
            const Divider(),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = StackColors.of(context);
    final (dotColor, statusText) = switch (chat.status) {
      OllamaStatus.connected => (p.success, chat.model ?? 'No model'),
      OllamaStatus.connecting => (p.warning, 'Connecting...'),
      OllamaStatus.offline => (scheme.error, 'Ollama offline'),
      OllamaStatus.unknown => (scheme.outline, 'Not connected'),
    };
    final minimized = mode == DockMode.minimized;
    final maximized = mode == DockMode.maximized;
    return InkWell(
      onTap: minimized ? () => onModeChanged(DockMode.open) : null,
      child: SizedBox(
        height: 42,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 6),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: p.accentText),
              const SizedBox(width: 8),
              Semantics(header: true, child: Text('Assistant', style: theme.textTheme.titleSmall)),
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
                        label: 'Ollama ${switch (chat.status) {
                          OllamaStatus.connected => 'connected',
                          OllamaStatus.connecting => 'connecting',
                          OllamaStatus.offline => 'offline',
                          OllamaStatus.unknown => 'not connected',
                        }}',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.circle, size: 8, color: dotColor),
                            const SizedBox(width: 6),
                            Flexible(
                                child: Text(statusText,
                                    style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis)),
                            if (chat.status == OllamaStatus.connected && chat.capabilities.thinking) ...[
                              Text('  ·  ', style: theme.textTheme.labelMedium?.copyWith(color: scheme.outline)),
                              Flexible(
                                child: Text('Thinking: ${chat.thinkLevel.label}',
                                    style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  ),
                  if (chat.busy) ...[
                    const SizedBox(width: 10),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Assistant is working'),
                    ),
                  ],
                ]),
              ),
              if (!minimized)
                IconButton(
                  tooltip: 'New chat',
                  icon: const Icon(Icons.add_comment_outlined, size: 19),
                  onPressed: chat.items.isEmpty ? null : chat.newChat,
                ),
              IconButton(
                tooltip: minimized ? 'Restore' : 'Minimize',
                icon: Icon(minimized ? Icons.expand_less : Icons.expand_more, size: 21),
                onPressed: () => onModeChanged(minimized ? DockMode.open : DockMode.minimized),
              ),
              IconButton(
                tooltip: maximized ? 'Restore size' : 'Maximize',
                icon: Icon(maximized ? Icons.close_fullscreen : Icons.open_in_full, size: 17),
                onPressed: () => onModeChanged(maximized ? DockMode.open : DockMode.maximized),
              ),
              IconButton(
                tooltip: 'Close (Ctrl+J)',
                icon: const Icon(Icons.close, size: 19),
                onPressed: () => onModeChanged(DockMode.closed),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The floating "Assistant" pill, styled like the mode switcher in Stills & Reels.
class _AssistantButton extends StatelessWidget {
  const _AssistantButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    return Semantics(
      button: true,
      label: 'Open assistant',
      excludeSemantics: true,
      child: GradientBorder(
        glow: true,
        child: Material(
          color: p.raised,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.auto_awesome, size: 18, color: p.accentText),
                const SizedBox(width: 8),
                Text('Assistant', style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
