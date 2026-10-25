import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ai/chat_controller.dart';
import '../../app/settings.dart';
import '../../app/theme.dart';
import '../../editor/page_editor_controller.dart';
import '../widgets/controls.dart';

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
    final p = StackColors.of(context);
    final canSend = !chat.busy && _text.text.trim().isNotEmpty && chat.model != null;
    final small = TextStyle(color: p.subText, fontSize: 12.7);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: PillBox(
            radius: 18,
            glow: _focus.hasFocus,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListenableBuilder(listenable: widget.editor, builder: (context, _) => _contextChips()),
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
                        style: TextStyle(color: p.text, fontSize: StackType.menu),
                        decoration: InputDecoration(
                          hintText: 'Ask about this page, or tell me what to create, edit or delete...',
                          hintStyle: TextStyle(color: p.subText, fontSize: StackType.menu),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Row(children: [
                          Flexible(child: _ModelPicker(chat: chat)),
                          const SizedBox(width: 4),
                          Flexible(child: _ThinkingPicker(chat: chat)),
                          if (chat.model != null && chat.status == OllamaStatus.connected && !chat.capabilities.tools)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Tooltip(
                                message:
                                    "This model can't call tools, so it can answer questions but not change pages.",
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.warning_amber_rounded, size: 14, color: p.warning),
                                  const SizedBox(width: 4),
                                  Text('No tools', style: small),
                                ]),
                              ),
                            ),
                        ]),
                      ),
                      if (chat.lastPromptTokens != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Tooltip(
                            message: 'Tokens used by the last request, out of the context length set in Settings.',
                            child: Text('${_k(chat.lastPromptTokens!)} / ${_k(chat.settings.contextLength)}',
                                style: small),
                          ),
                        ),
                      chat.busy
                          ? SsButton(
                              primary: true,
                              icon: Icons.stop,
                              tooltip: 'Stop',
                              radius: 18,
                              onPressed: chat.stop,
                            )
                          : SsButton(
                              primary: true,
                              icon: Icons.arrow_upward,
                              tooltip: 'Send (Enter)',
                              radius: 18,
                              onPressed: canSend ? _send : null,
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

  Widget _contextChips() {
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
    final p = StackColors.of(context);
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(color: p.control, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: p.subText),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(label, style: TextStyle(color: p.text, fontSize: 12.7), overflow: TextOverflow.ellipsis),
          ),
          SsButton(
            compact: true,
            icon: Icons.close,
            iconSize: 13,
            height: 24,
            width: 24,
            radius: 6,
            semanticLabel: 'Remove $label from context',
            onPressed: onRemove,
          ),
        ]),
      ),
    );
  }
}

/// A compact Stills & Reels button that opens a menu below it.
class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.items,
    required this.onSelected,
    this.extra = const [],
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final List<(T value, String text, bool checked)> items;
  final ValueChanged<T>? onSelected;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    return MenuAnchor(
      menuChildren: [
        for (final (value, text, checked) in items)
          MenuItemButton(
            leadingIcon: Icon(checked ? Icons.check : null, size: 16, color: p.accentA),
            onPressed: () => onSelected?.call(value),
            child: Text(text),
          ),
        ...extra,
      ],
      builder: (context, controller, _) => SsButton(
        compact: true,
        height: 32,
        icon: icon,
        iconSize: 15,
        label: label,
        tooltip: tooltip,
        semanticLabel: '$tooltip: $label',
        fontSize: 12.7,
        trailing: Icon(Icons.arrow_drop_down, size: 18, color: onSelected == null ? p.muted : p.subText),
        onPressed: onSelected == null ? null : () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

class _ModelPicker extends StatelessWidget {
  const _ModelPicker({required this.chat});
  final ChatController chat;

  @override
  Widget build(BuildContext context) {
    return _Picker<String>(
      icon: Icons.memory,
      label: chat.model ?? 'No model',
      tooltip: 'Choose a model',
      items: [
        for (final m in chat.models)
          (m.name, [m.name, if (m.parameterSize != null) m.parameterSize].join('  ·  '), m.name == chat.model),
      ],
      onSelected: chat.selectModel,
      extra: [
        if (chat.models.isNotEmpty) const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.refresh, size: 16),
          onPressed: chat.connect,
          child: const Text('Refresh models'),
        ),
      ],
    );
  }
}

class _ThinkingPicker extends StatelessWidget {
  const _ThinkingPicker({required this.chat});
  final ChatController chat;

  @override
  Widget build(BuildContext context) {
    final supported = chat.capabilities.thinking;
    return _Picker<ThinkLevel>(
      icon: Icons.psychology_outlined,
      label: supported ? 'Thinking: ${chat.thinkLevel.label}' : 'Thinking: n/a',
      tooltip: !supported
          ? "This model doesn't support thinking"
          : chat.supportsThinkLevels
              ? 'How much the model thinks before answering'
              : 'This model only has thinking on or off; Low, Medium and High all turn it on',
      items: [for (final level in ThinkLevel.values) (level, level.label, level == chat.thinkLevel)],
      onSelected: supported ? chat.setThinkLevel : null,
    );
  }
}
