import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ai/chat_controller.dart';
import '../editor_pane.dart' show monoFont, monoFallback;

const _maxWidth = 780.0;

class ChatMessages extends StatelessWidget {
  const ChatMessages({super.key, required this.chat, required this.onOpenSettings});

  final ChatController chat;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (chat.items.isEmpty) return _EmptyState(chat: chat, onOpenSettings: onOpenSettings);
    final items = chat.items.reversed.toList();
    // reverse: true keeps the list pinned to the newest message while it streams.
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: items.length,
      itemBuilder: (context, i) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 10),
            child: switch (items[i]) {
              UserItem item => _UserBubble(item: item),
              AssistantItem item => _AssistantMessage(item: item),
              ToolItem item => _ToolCard(item: item, onUndo: () => chat.revert(item)),
              ErrorItem item => _ErrorBox(message: item.message),
            },
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.chat, required this.onOpenSettings});
  final ChatController chat;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offline = chat.status == OllamaStatus.offline;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(offline ? Icons.cloud_off_outlined : Icons.auto_awesome_outlined,
                  size: 30, color: theme.colorScheme.primary),
              const SizedBox(height: 10),
              Text(
                offline
                    ? (chat.statusMessage ?? "Can't reach Ollama.")
                    : chat.statusMessage ??
                        'Ask about the open page, or ask me to create, edit, rename or delete pages. '
                            'Select text in the editor to point me at a specific snippet.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (offline) ...[
                const SizedBox(height: 12),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  FilledButton.tonal(onPressed: chat.connect, child: const Text('Retry')),
                  const SizedBox(width: 8),
                  TextButton(onPressed: onOpenSettings, child: const Text('Settings')),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.item});
  final UserItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (item.contextLabels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final label in item.contextLabels)
                      Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SelectableText(item.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantMessage extends StatefulWidget {
  const _AssistantMessage({required this.item});
  final AssistantItem item;

  @override
  State<_AssistantMessage> createState() => _AssistantMessageState();
}

class _AssistantMessageState extends State<_AssistantMessage> {
  bool _showThinking = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final thinkingNow = item.streaming && item.content.isEmpty;
    final hasThinking = item.thinking.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasThinking || thinkingNow)
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: hasThinking ? () => setState(() => _showThinking = !_showThinking) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.psychology_outlined, size: 16, color: muted),
                const SizedBox(width: 6),
                Text(
                  thinkingNow
                      ? 'Thinking...'
                      : item.thoughtFor != null
                          ? 'Thought for ${_seconds(item.thoughtFor!)}'
                          : 'Thoughts',
                  style: theme.textTheme.labelMedium?.copyWith(color: muted),
                ),
                if (hasThinking) Icon(_showThinking ? Icons.expand_less : Icons.expand_more, size: 16, color: muted),
              ]),
            ),
          ),
        if (_showThinking && hasThinking)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant, width: 2))),
            child: SelectableText(item.thinking.toString().trim(),
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ),
        if (item.content.isNotEmpty) MessageBody(text: item.content.toString()),
      ],
    );
  }

  static String _seconds(Duration d) => d.inSeconds < 1 ? 'less than a second' : '${d.inSeconds}s';
}

/// Renders a reply, showing ``` fenced blocks as code with a copy button.
class MessageBody extends StatelessWidget {
  const MessageBody({super.key, required this.text});
  final String text;

  static final _fence = RegExp(r'```([\w+-]*)\n?([\s\S]*?)(?:```|$)');

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];
    var last = 0;
    for (final m in _fence.allMatches(text)) {
      final before = text.substring(last, m.start).trim();
      if (before.isNotEmpty) parts.add(SelectableText(before));
      parts.add(_CodeBlock(language: m.group(1) ?? '', code: (m.group(2) ?? '').trimRight()));
      last = m.end;
    }
    final rest = text.substring(last).trim();
    if (rest.isNotEmpty) parts.add(SelectableText(rest));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in parts) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: p),
      ],
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.language, required this.code});
  final String language;
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(children: [
              Text(language.isEmpty ? 'code' : language, style: theme.textTheme.labelSmall),
              const Spacer(),
              IconButton(
                tooltip: 'Copy',
                iconSize: 15,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy),
                onPressed: () => Clipboard.setData(ClipboardData(text: code)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SelectableText(code,
                style: const TextStyle(fontFamily: monoFont, fontFamilyFallback: monoFallback, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatefulWidget {
  const _ToolCard({required this.item, required this.onUndo});
  final ToolItem item;
  final VoidCallback onUndo;

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final icon = switch (item.status) {
      ToolStatus.running => const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      ToolStatus.done => Icon(_iconFor(item.name), size: 16, color: scheme.primary),
      ToolStatus.failed => Icon(Icons.error_outline, size: 16, color: scheme.error),
    };
    final edit = item.edit;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                icon,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.status == ToolStatus.running ? 'Running ${item.name}...' : item.summary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      decoration: edit?.reverted == true ? TextDecoration.lineThrough : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (edit != null)
                  edit.reverted
                      ? Text('Undone', style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline))
                      : TextButton.icon(
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: widget.onUndo,
                          icon: const Icon(Icons.undo, size: 15),
                          label: const Text('Undo'),
                        ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 16, color: scheme.outline),
              ]),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: SelectableText(
                '${item.name}(${item.arguments.entries.map((e) => '${e.key}: ${_short(e.value)}').join(', ')})\n\n${_short(item.result, 1500)}',
                style: const TextStyle(fontFamily: monoFont, fontFamilyFallback: monoFallback, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  static String _short(Object? value, [int max = 120]) {
    final s = value.toString();
    return s.length > max ? '${s.substring(0, max)}...' : s;
  }

  static IconData _iconFor(String tool) => switch (tool) {
        'read_page' || 'list_pages' => Icons.visibility_outlined,
        'search_pages' => Icons.search,
        'create_page' => Icons.note_add_outlined,
        'delete_page' => Icons.delete_outline,
        'rename_page' => Icons.drive_file_rename_outline,
        _ => Icons.edit_outlined,
      };
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(Icons.error_outline, size: 16, color: scheme.onErrorContainer),
        const SizedBox(width: 8),
        Expanded(child: SelectableText(message, style: TextStyle(color: scheme.onErrorContainer))),
      ]),
    );
  }
}
