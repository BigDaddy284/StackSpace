import 'package:flutter/material.dart';

import 'blocks.dart';
import 'page_document.dart';

/// Where a slash command puts the caret when it is done.
typedef SlashResult = Caret;

/// One entry of the slash menu.
class SlashCommand {
  const SlashCommand({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.category,
    this.aliases = const [],
    required this.apply,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final String category;

  /// Other words that find this command, such as "h1" for Heading 1.
  final List<String> aliases;

  /// Runs on the block at [index] after the `/query` text has been removed.
  final SlashResult Function(PageDocument doc, int index) apply;

  bool matches(String query) => score(query) > 0;

  /// 3 = label starts with the query, 2 = an alias starts with it,
  /// 1 = label or an alias contains it, 0 = no match.
  int score(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return 3;
    final label = this.label.toLowerCase();
    if (label.startsWith(q)) return 3;
    if (aliases.any((a) => a.startsWith(q))) return 2;
    if (label.contains(q) || aliases.any((a) => a.contains(q))) return 1;
    return 0;
  }
}

/// The commands that match [query], best first, in their category order.
List<SlashCommand> filterSlashCommands(String query, [List<SlashCommand>? from]) {
  final all = from ?? slashCommands;
  final scored = [for (final c in all) (c, c.score(query))].where((e) => e.$2 > 0).toList();
  scored.sort((a, b) => b.$2 != a.$2 ? b.$2 - a.$2 : all.indexOf(a.$1) - all.indexOf(b.$1));
  return [for (final e in scored) e.$1];
}

SlashResult _turnInto(PageDocument doc, int index, BlockKind kind, {int level = 0, String? prefix}) {
  final block = doc[index];
  var text = block.text;
  if (prefix != null && !text.startsWith(prefix)) text = prefix + text;
  if (text != block.text) doc.updateText(index, text);
  doc.convert(index, kind, level: level);
  return (block: index, offset: text.length);
}

/// Puts [block] after the current block, or in its place when it is empty,
/// then a paragraph to type on if nothing follows.
SlashResult _insertAfter(PageDocument doc, int index, Block block, {bool focusInserted = false}) {
  final current = doc[index];
  var at = index + 1;
  if (current.text.isEmpty && current.kind == BlockKind.paragraph) {
    doc.replace(index, block.copyWith(gapBefore: current.gapBefore));
    at = index;
  } else {
    doc.insert(at, block);
  }
  if (focusInserted) return (block: at, offset: block.text.length);
  if (at + 1 >= doc.length || !doc[at + 1].isText) {
    doc.insert(at + 1, Block(kind: BlockKind.paragraph));
  }
  return (block: at + 1, offset: 0);
}

const _text = 'Text';
const _lists = 'Lists';
const _blocks = 'Blocks';
const _media = 'Media';

final List<SlashCommand> slashCommands = [
  SlashCommand(
    id: 'text',
    label: 'Text',
    description: 'Plain paragraph',
    icon: Icons.notes_outlined,
    category: _text,
    aliases: ['paragraph', 'p', 'plain'],
    apply: (doc, i) => _turnInto(doc, i, BlockKind.paragraph),
  ),
  SlashCommand(
    id: 'h1',
    label: 'Heading 1',
    description: 'Large section heading',
    icon: Icons.title,
    category: _text,
    aliases: ['h1', 'title', '#'],
    apply: (doc, i) => _turnInto(doc, i, BlockKind.heading, level: 1),
  ),
  SlashCommand(
    id: 'h2',
    label: 'Heading 2',
    description: 'Medium section heading',
    icon: Icons.title,
    category: _text,
    aliases: ['h2', 'subheading', '##'],
    apply: (doc, i) => _turnInto(doc, i, BlockKind.heading, level: 2),
  ),
  SlashCommand(
    id: 'h3',
    label: 'Heading 3',
    description: 'Small section heading',
    icon: Icons.title,
    category: _text,
    aliases: ['h3', '###'],
    apply: (doc, i) => _turnInto(doc, i, BlockKind.heading, level: 3),
  ),
  SlashCommand(
    id: 'quote',
    label: 'Quote',
    description: 'Quoted text with a bar',
    icon: Icons.format_quote_outlined,
    category: _text,
    aliases: ['blockquote', 'citation', '>'],
    apply: (doc, i) => _turnInto(doc, i, BlockKind.quote),
  ),
  SlashCommand(
    id: 'callout',
    label: 'Callout',
    description: 'Highlighted note with an icon',
    icon: Icons.lightbulb_outline,
    category: _text,
    aliases: ['note', 'tip', 'info', 'warning'],
    apply: (doc, i) => _turnInto(doc, i, BlockKind.quote, prefix: '💡 '),
  ),
  SlashCommand(
    id: 'bullet',
    label: 'Bulleted list',
    description: 'Simple list with bullets',
    icon: Icons.format_list_bulleted,
    category: _lists,
    aliases: ['ul', 'unordered', 'bullets', '-'],
    apply: (doc, i) => _turnInto(doc, i, BlockKind.bullet),
  ),
  SlashCommand(
    id: 'numbered',
    label: 'Numbered list',
    description: 'List with numbers',
    icon: Icons.format_list_numbered,
    category: _lists,
    aliases: ['ol', 'ordered', 'numbers', '1.'],
    apply: (doc, i) => _turnInto(doc, i, BlockKind.numbered),
  ),
  SlashCommand(
    id: 'todo',
    label: 'To-do list',
    description: 'Checklist with checkboxes',
    icon: Icons.check_box_outlined,
    category: _lists,
    aliases: ['todo', 'to do', 'checkbox', 'task', 'checklist', '[]'],
    apply: (doc, i) => _turnInto(doc, i, BlockKind.todo),
  ),
  SlashCommand(
    id: 'code',
    label: 'Code block',
    description: 'Code with a language and monospace font',
    icon: Icons.code,
    category: _blocks,
    aliases: ['code space', 'script', 'snippet', '```', 'pre'],
    apply: (doc, i) => _turnInto(doc, i, BlockKind.code),
  ),
  SlashCommand(
    id: 'divider',
    label: 'Divider',
    description: 'Horizontal line',
    icon: Icons.horizontal_rule,
    category: _blocks,
    aliases: ['hr', 'line', 'separator', 'rule', '---'],
    apply: (doc, i) => _insertAfter(doc, i, Block(kind: BlockKind.divider)),
  ),
  SlashCommand(
    id: 'table',
    label: 'Table',
    description: 'Simple table (Markdown)',
    icon: Icons.table_chart_outlined,
    category: _blocks,
    aliases: ['grid', 'columns'],
    apply: (doc, i) {
      final table = Block(kind: BlockKind.table, text: '| Column 1 | Column 2 |\n| --- | --- |\n|  |  |');
      final at = _insertAfter(doc, i, table, focusInserted: true);
      return (block: at.block, offset: 0); // the first cell
    },
  ),
  SlashCommand(
    id: 'image',
    label: 'Image',
    description: 'Picture from a file or a link',
    icon: Icons.image_outlined,
    category: _media,
    aliases: ['picture', 'photo', 'img'],
    // The editor asks for the path and fills the block in.
    apply: (doc, i) => _insertAfter(doc, i, Block(kind: BlockKind.image)),
  ),
];
