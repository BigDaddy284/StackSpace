import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ai/chat_controller.dart';
import '../../app/settings.dart';
import '../../app/theme.dart';
import '../../editor/page_editor_controller.dart';

/// The message box at the bottom of the chat: context chips for the open page
/// and selection, the text field, and the model / thinking pickers.
class Composer extends StatefulWidget {
  const Composer({super.key, required this.chat, required this.editor});

  final ChatController chat;
  final PageEditorController editor;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _includePage = true;
  bool _includeSelection = true;

  ChatController get chat => widget.chat;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    if (chat.busy || _text.text.trim().isEmpty) return;
    final full = widget.editor.chatContext;
    final context = ChatContext(
      pagePath: _includePage || (_includeSelection && full.hasSelection) ? full.pagePath : null,
      pageText: _includePage ? full.pageText : null,
      selection: _includeSelection ? full.selection : null,
      selectionStartLine: full.selectionStartLine,
      selectionEndLine: full.selectionEndLine,
    );
    chat.send(_text.text, context: context);
    _text.clear();
    setState(() {
      _includePage = true;
      _includeSelection = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canSend = !chat.busy && _text.text.trim().isNotEmpty && chat.model != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: GradientBorder(
            radius: 18,
            active: _focus.hasFocus,
            glow: _focus.hasFocus,
            child: Container(
              color: StackColors.of(context).raised,
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListenableBuilder(listenable: widget.editor, builder: (context, _) => _contextChips(theme)),
                  CallbackShortcuts(
                    bindings: {const SingleActivator(LogicalKeyboardKey.enter): _send},
                    child: Focus(
                      onFocusChange: (_) => setState(() {}),
                      child: TextField(
                        key: const Key('composer'),
                        controller: _text,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          hintText: 'Ask about this page, or tell me what to create, edit or delete...',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _ModelPicker(chat: chat),
                      const SizedBox(width: 4),
                      _ThinkingPicker(chat: chat),
                      if (chat.model != null && chat.status == OllamaStatus.connected && !chat.capabilities.tools)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Tooltip(
                            message: "This model can't call tools, so it can answer questions but not change pages.",
                            child:
                                Text('No tools', style: theme.textTheme.labelSmall?.copyWith(color: scheme.tertiary)),
                          ),
                        ),
                      const Spacer(),
                      if (chat.lastPromptTokens != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Tooltip(
                            message: 'Tokens used by the last request, out of the context length set in Settings.',
                            child: Text(
                              '${_k(chat.lastPromptTokens!)} / ${_k(chat.settings.contextLength)}',
                              style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
                            ),
                          ),
                        ),
                      chat.busy
                          ? IconButton.filled(
                              tooltip: 'Stop', onPressed: chat.stop, icon: const Icon(Icons.stop, size: 18))
                          : IconButton.filled(
                              tooltip: 'Send (Enter)',
                              onPressed: canSend ? _send : null,
                              icon: const Icon(Icons.arrow_upward, size: 18),
                            ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _k(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  Widget _contextChips(ThemeData theme) {
    final ctx = widget.editor.chatContext;
    final chips = <Widget>[
      if (ctx.pagePath != null && _includePage)
        _ContextChip(
          icon: Icons.description_outlined,
          label: ctx.pagePath!,
          tooltip: 'The assistant sees this page. Click x to leave it out of the next message.',
          onRemove: () => setState(() => _includePage = false),
        ),
      if (ctx.hasSelection && _includeSelection)
        _ContextChip(
          icon: Icons.text_snippet_outlined,
          label: ctx.selectionStartLine == ctx.selectionEndLine
              ? 'Selection: line ${ctx.selectionStartLine}'
              : 'Selection: lines ${ctx.selectionStartLine}-${ctx.selectionEndLine}',
          tooltip: 'Selected text in the editor. "This" in your message refers to it.',
          onRemove: () => setState(() => _includeSelection = false),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Wrap(spacing: 6, runSpacing: 4, children: chips),
    );
  }
}

class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.icon, required this.label, required this.tooltip, required this.onRemove});
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(label, style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis),
          ),
          Semantics(
            button: true,
            label: 'Remove $label from context',
            excludeSemantics: true,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(width: 24, height: 24, child: Icon(Icons.close, size: 13)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(label, style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis),
        ),
        Icon(Icons.arrow_drop_down, size: 18, color: theme.colorScheme.onSurfaceVariant),
      ]),
    );
  }
}

class _ModelPicker extends StatelessWidget {
  const _ModelPicker({required this.chat});
  final ChatController chat;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Choose a model',
      onSelected: (value) => value == '\u0000refresh' ? chat.connect() : chat.selectModel(value),
      itemBuilder: (context) => [
        for (final m in chat.models)
          CheckedPopupMenuItem(
            value: m.name,
            checked: m.name == chat.model,
            child: Text([m.name, if (m.parameterSize != null) m.parameterSize].join('  ·  ')),
          ),
        if (chat.models.isNotEmpty) const PopupMenuDivider(),
        const PopupMenuItem(value: '\u0000refresh', child: Text('Refresh models')),
      ],
      child: _PickerButton(icon: Icons.memory, label: chat.model ?? 'No model'),
    );
  }
}

class _ThinkingPicker extends StatelessWidget {
  const _ThinkingPicker({required this.chat});
  final ChatController chat;

  @override
  Widget build(BuildContext context) {
    final supported = chat.capabilities.thinking;
    if (!supported) {
      return Tooltip(
        message: "This model doesn't support thinking.",
        child: Opacity(
          opacity: 0.5,
          child: _PickerButton(icon: Icons.psychology_outlined, label: 'Thinking: n/a'),
        ),
      );
    }
    return PopupMenuButton<ThinkLevel>(
      tooltip: chat.supportsThinkLevels
          ? 'How much the model thinks before answering'
          : 'This model only has thinking on or off; Low, Medium and High all turn it on.',
      onSelected: chat.setThinkLevel,
      itemBuilder: (context) => [
        for (final level in ThinkLevel.values)
          CheckedPopupMenuItem(value: level, checked: level == chat.thinkLevel, child: Text(level.label)),
      ],
      child: _PickerButton(icon: Icons.psychology_outlined, label: 'Thinking: ${chat.thinkLevel.label}'),
    );
  }
}
