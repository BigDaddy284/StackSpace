import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ai/chat_controller.dart';
import '../../app/theme.dart';
import '../widgets/controls.dart';

const _maxWidth = 780.0;

TextStyle _mono(StackPalette p, double size) =>
    TextStyle(fontFamily: 'Cascadia Mono', fontFamilyFallback: StackType.mono, fontSize: size, color: p.text);

class ChatMessages extends StatelessWidget {
  const ChatMessages({super.key, required this.chat, required this.onOpenSettings});

  final ChatController chat;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (chat.items.isEmpty) {
      final offline = chat.status == OllamaStatus.offline;
      return EmptyState(
        icon: offline ? Icons.cloud_off_outlined : Icons.auto_awesome,
        title: offline ? "Can't reach Ollama" : 'Ask about this page',
        detail: offline
            ? (chat.statusMessage ?? 'Start Ollama, then try again.')
            : chat.statusMessage ??
                'Ask a question, or ask me to create, edit, rename or delete pages.\n'
                    'Select text in the editor to point me at a specific snippet.',
        actions: [
          if (offline) ...[
            SsButton(icon: Icons.refresh, label: 'Retry', primary: true, onPressed: chat.connect),
            SsButton(icon: Icons.settings_outlined, label: 'Settings', onPressed: onOpenSettings),
          ],
        ],
      );
    }
    final items = chat.items.reversed.toList();
    // reverse: true keeps the list pinned to the newest message while it streams.
    // One SelectionArea lets you select and copy across the whole conversation.
    return SelectionArea(
      child: ListView.builder(
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
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.item});
  final UserItem item;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
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
                child: Text(item.contextLabels.join('  ·  '), style: TextStyle(color: p.subText, fontSize: 12)),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: p.control, borderRadius: BorderRadius.circular(12)),
              child: Text(item.text, style: TextStyle(color: p.text, fontSize: StackType.menu)),
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
    final p = StackColors.of(context);
    final thinkingNow = item.streaming && item.content.isEmpty;
    final hasThinking = item.thinking.isNotEmpty;
    final label = thinkingNow
        ? 'Thinking...'
        : item.thoughtFor != null
            ? 'Thought for ${_seconds(item.thoughtFor!)}'
            : 'Thoughts';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasThinking || thinkingNow)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SsButton(
              compact: true,
              height: 30,
              icon: Icons.psychology_outlined,
              iconSize: 16,
              label: label,
              fontSize: 12.7,
              semanticLabel: hasThinking ? '$label. ${_showThinking ? 'Hide' : 'Show'} thoughts' : label,
              trailing: hasThinking
                  ? Icon(_showThinking ? Icons.expand_less : Icons.expand_more, size: 16, color: p.subText)
                  : null,
              onPressed: hasThinking ? () => setState(() => _showThinking = !_showThinking) : null,
            ),
          ),
        if (_showThinking && hasThinking)
          Container(
            margin: const EdgeInsets.only(bottom: 6, left: 10),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: p.pillSep, width: 2))),
            child: Text(item.thinking.toString().trim(), style: TextStyle(color: p.subText, fontSize: 12.7)),
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
    final p = StackColors.of(context);
    final style = TextStyle(color: p.text, fontSize: StackType.menu, height: 1.45);
    final parts = <Widget>[];
    var last = 0;
    for (final m in _fence.allMatches(text)) {
      final before = text.substring(last, m.start).trim();
      if (before.isNotEmpty) parts.add(Text(before, style: style));
      parts.add(_CodeBlock(language: m.group(1) ?? '', code: (m.group(2) ?? '').trimRight()));
      last = m.end;
    }
    final rest = text.substring(last).trim();
    if (rest.isNotEmpty) parts.add(Text(rest, style: style));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final part in parts) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: part),
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
    final p = StackColors.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: p.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.barBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 4, top: 2),
            child: Row(children: [
              Text((language.isEmpty ? 'code' : language).toUpperCase(),
                  style: TextStyle(color: p.subText, fontSize: StackType.section, fontWeight: FontWeight.w700)),
              const Spacer(),
              SsButton(
                compact: true,
                icon: Icons.copy,
                iconSize: 15,
                tooltip: 'Copy code',
                width: 32,
                height: 30,
                onPressed: () => Clipboard.setData(ClipboardData(text: code)),
              ),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: Text(code, style: _mono(p, 13))),
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
    final p = StackColors.of(context);
    final icon = switch (item.status) {
      ToolStatus.running =>
        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: p.accentA)),
      ToolStatus.done => Icon(_iconFor(item.name), size: 16, color: p.text),
      ToolStatus.failed => Icon(Icons.error_outline, size: 16, color: p.error),
    };
    final edit = item.edit;
    final summary = item.status == ToolStatus.running ? 'Running ${item.name}...' : item.summary;
    return Container(
      decoration: BoxDecoration(color: p.control, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SsRow(
            height: 38,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 6),
              child: Row(children: [
                icon,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    summary,
                    style: TextStyle(
                      color: p.text,
                      fontSize: StackType.button,
                      decoration: edit?.reverted == true ? TextDecoration.lineThrough : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (edit != null)
                  edit.reverted
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text('Undone', style: TextStyle(color: p.subText, fontSize: 12.7)),
                        )
                      : SsButton(
                          icon: Icons.undo,
                          iconSize: 15,
                          label: 'Undo',
                          height: 28,
                          fontSize: 12.7,
                          semanticLabel: 'Undo: $summary',
                          onPressed: widget.onUndo,
                        ),
                const SizedBox(width: 4),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 16, color: p.subText),
              ]),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(
                '${item.name}(${item.arguments.entries.map((e) => '${e.key}: ${_short(e.value)}').join(', ')})\n\n${_short(item.result, 1500)}',
                style: _mono(p, 12),
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
    final p = StackColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: p.control,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: p.error, width: 3)),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, size: 16, color: p.error),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: TextStyle(color: p.text, fontSize: StackType.button))),
      ]),
    );
  }
}
