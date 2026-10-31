import 'package:flutter/gestures.dart' show DragStartBehavior;
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
class ChatDockLayout extends StatefulWidget {
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

  /// Called once, when a drag of the dock's top edge ends.
  final ValueChanged<double> onHeightChanged;
  final Widget content;
  final Widget dock;

  static const minHeight = 220.0;

  @override
  State<ChatDockLayout> createState() => _ChatDockLayoutState();
}

class _ChatDockLayoutState extends State<ChatDockLayout> {
  /// The height while the edge is dragged; only this widget rebuilds then.
  double? _dragHeight;
  double _startHeight = 0, _startY = 0;

  @override
  Widget build(BuildContext context) {
    final content = widget.content, dock = widget.dock;
    switch (widget.mode) {
      case DockMode.closed:
        return content;
      case DockMode.minimized:
        return Column(children: [Expanded(child: content), dock]);
      case DockMode.maximized:
        return dock;
      case DockMode.open:
        return LayoutBuilder(builder: (context, constraints) {
          final maxHeight = (constraints.maxHeight - 120).clamp(ChatDockLayout.minHeight, double.infinity);
          double clamp(double h) => h.clamp(ChatDockLayout.minHeight, maxHeight);
          final h = clamp(_dragHeight ?? widget.height);
          return Column(
            children: [
              Expanded(child: content),
              _ResizeHandle(
                onStart: (y) {
                  _startY = y;
                  _startHeight = h;
                },
                // Measured from where the drag started, so the edge stays under
                // the pointer, even after it passes a limit and comes back.
                onDrag: (y) => setState(() => _dragHeight = clamp(_startHeight - (y - _startY))),
                onEnd: () {
                  final height = _dragHeight;
                  setState(() => _dragHeight = null);
                  if (height != null) widget.onHeightChanged(height);
                },
              ),
              SizedBox(height: h, child: dock),
            ],
          );
        });
    }
  }
}

class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({required this.onStart, required this.onDrag, required this.onEnd});
  final ValueChanged<double> onStart;

  /// The pointer's position on the screen, top to bottom.
  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hot = true),
      onExit: (_) => setState(() => _hot = false),
      child: GestureDetector(
        key: const ValueKey('chat-dock-resize'),
        behavior: HitTestBehavior.opaque,
        // From where the button went down, not where the drag was recognised.
        dragStartBehavior: DragStartBehavior.down,
        onVerticalDragStart: (d) => widget.onStart(d.globalPosition.dy),
        onVerticalDragUpdate: (d) => widget.onDrag(d.globalPosition.dy),
        onVerticalDragEnd: (_) => widget.onEnd(),
        onVerticalDragCancel: widget.onEnd,
        child: Container(
          height: 7,
          color: p.panel,
          alignment: Alignment.center,
          child: Container(height: _hot ? 2 : 1, color: _hot ? p.accentA : p.barBorder),
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
