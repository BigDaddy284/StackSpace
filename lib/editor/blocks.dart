/// The block model of a page and its Markdown reader and writer.
///
/// A page file stays plain Markdown. In the editor it is a list of [Block]s,
/// each edited on its own, so a page with thousands of lines of code never
/// lays out as one text run. The reader is line-based and keeps anything it
/// does not understand verbatim (as a [BlockKind.raw] block), so a page that
/// is opened and saved without edits comes back unchanged, line for line,
/// apart from blank-line normalisation between blocks.
library;

enum BlockKind { paragraph, heading, bullet, numbered, todo, quote, code, divider, image, table, raw }

class Block {
  Block({
    required this.kind,
    this.text = '',
    this.level = 0,
    this.number,
    this.checked = false,
    this.language,
    this.caption = '',
    this.url = '',
    this.alt = '',
    this.marker = '-',
    this.gapBefore,
    int? id,
  }) : id = id ?? _nextId++;

  static int _nextId = 1;

  /// Stable identity for widget keys; survives edits of the same block.
  final int id;
  final BlockKind kind;

  /// Body text. Paragraphs, quotes and list items may hold soft line breaks.
  /// For code it is the code; for tables and raw blocks the verbatim lines.
  final String text;

  /// Heading level 1-6, or list nesting depth (0 = top level).
  final int level;

  /// Explicit number of a numbered item, if the file had one.
  final int? number;
  final bool checked;

  /// Code fence language, or null for none.
  final String? language;

  /// Caption of a code block: the rest of the fence line after the language
  /// (`\`\`\`python Download helper`).
  final String caption;
  final String url;
  final String alt;

  /// Bullet character of a bullet or todo item: '-', '*' or '+'.
  final String marker;

  /// Blank lines between this block and the one before it in the file, or
  /// null to use the default (none inside a list, one otherwise). Set by the
  /// reader so an unedited page writes back exactly as it was read.
  final int? gapBefore;

  bool get isList => kind == BlockKind.bullet || kind == BlockKind.numbered || kind == BlockKind.todo;
  bool get isText => switch (kind) {
        BlockKind.paragraph ||
        BlockKind.heading ||
        BlockKind.bullet ||
        BlockKind.numbered ||
        BlockKind.todo ||
        BlockKind.quote =>
          true,
        _ => false,
      };

  Block copyWith({
    BlockKind? kind,
    String? text,
    int? level,
    int? number,
    bool clearNumber = false,
    bool? checked,
    String? language,
    bool clearLanguage = false,
    String? caption,
    String? url,
    String? alt,
    String? marker,
    int? gapBefore,
    bool clearGap = false,
  }) =>
      Block(
        id: id,
        kind: kind ?? this.kind,
        text: text ?? this.text,
        level: level ?? this.level,
        number: clearNumber ? null : number ?? this.number,
        checked: checked ?? this.checked,
        language: clearLanguage ? null : language ?? this.language,
        caption: caption ?? this.caption,
        url: url ?? this.url,
        alt: alt ?? this.alt,
        marker: marker ?? this.marker,
        gapBefore: clearGap ? null : gapBefore ?? this.gapBefore,
      );

  /// A fresh copy with a new identity (for duplicating).
  Block clone() => Block(
      kind: kind,
      text: text,
      level: level,
      number: number,
      checked: checked,
      language: language,
      url: url,
      alt: alt,
      marker: marker);

  @override
  String toString() =>
      'Block#$id(${kind.name}${level > 0 ? ' l$level' : ''}: ${text.length > 30 ? '${text.substring(0, 30)}...' : text})';
}

final _heading = RegExp(r'^(#{1,6}) (.*)$');
final _fence = RegExp(r'^(`{3,}|~{3,})\s*([\w#+.-]*)(?:[ \t]+(.*?))?[ \t]*$');
final _divider = RegExp(r'^(?:-{3,}|\*{3,}|_{3,})\s*$');
final _listItem = RegExp(r'^( *)(?:([-*+])|(\d+)\.) (?:\[([ xX])\] )?(.*)$');
final _image = RegExp(r'^!\[([^\]]*)\]\(([^)\s]+)\)\s*$');
final _quote = RegExp(r'^> ?(.*)$');
final _tableRow = RegExp(r'^\|.*\|\s*$');

/// Reads Markdown into blocks.
List<Block> parseMarkdown(String markdown) {
  final lines = markdown.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  final blocks = <Block>[];
  final paragraph = <String>[];
  var blanks = 0;

  void add(Block block) {
    blocks.add(block.copyWith(gapBefore: blanks));
    blanks = 0;
  }

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    final text = paragraph.join('\n');
    paragraph.clear();
    add(Block(kind: BlockKind.paragraph, text: text));
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      flushParagraph();
      blanks++;
      i++;
      continue;
    }
    final fence = _fence.firstMatch(line);
    if (fence != null) {
      flushParagraph();
      final marker = fence.group(1)!;
      final language = fence.group(2)!;
      final caption = fence.group(3) ?? '';
      final body = <String>[];
      i++;
      bool closes(String l) {
        final t = l.trimRight();
        return t.length >= marker.length && t == marker[0] * t.length;
      }

      while (i < lines.length && !closes(lines[i])) {
        body.add(lines[i]);
        i++;
      }
      i++; // closing fence (or past the end)
      add(Block(
          kind: BlockKind.code, text: body.join('\n'), language: language.isEmpty ? null : language, caption: caption));
      continue;
    }
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      flushParagraph();
      add(Block(kind: BlockKind.heading, level: heading.group(1)!.length, text: heading.group(2)!));
      i++;
      continue;
    }
    if (_divider.hasMatch(line)) {
      flushParagraph();
      add(Block(kind: BlockKind.divider));
      i++;
      continue;
    }
    final item = _listItem.firstMatch(line);
    if (item != null) {
      flushParagraph();
      final indent = item.group(1)!.length;
      final numbered = item.group(3) != null;
      final check = item.group(4);
      add(Block(
        marker: item.group(2) ?? '-',
        kind: check != null
            ? BlockKind.todo
            : numbered
                ? BlockKind.numbered
                : BlockKind.bullet,
        level: indent ~/ 2,
        number: numbered ? int.parse(item.group(3)!) : null,
        checked: check != null && check != ' ',
        text: item.group(5)!,
      ));
      i++;
      continue;
    }
    final image = _image.firstMatch(line);
    if (image != null) {
      flushParagraph();
      add(Block(kind: BlockKind.image, alt: image.group(1)!, url: image.group(2)!));
      i++;
      continue;
    }
    if (_quote.hasMatch(line)) {
      flushParagraph();
      final body = <String>[];
      while (i < lines.length && _quote.hasMatch(lines[i])) {
        body.add(_quote.firstMatch(lines[i])!.group(1)!);
        i++;
      }
      add(Block(kind: BlockKind.quote, text: body.join('\n')));
      continue;
    }
    if (_tableRow.hasMatch(line)) {
      flushParagraph();
      final rows = <String>[];
      while (i < lines.length && _tableRow.hasMatch(lines[i])) {
        rows.add(lines[i]);
        i++;
      }
      add(Block(kind: BlockKind.table, text: rows.join('\n')));
      continue;
    }
    if (line.startsWith('<') || line.startsWith('    ')) {
      // HTML or an indented code block: keep verbatim.
      flushParagraph();
      final raw = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        raw.add(lines[i]);
        i++;
      }
      add(Block(kind: BlockKind.raw, text: raw.join('\n')));
      continue;
    }
    paragraph.add(line);
    i++;
  }
  flushParagraph();
  return blocks;
}

/// Writes blocks back as Markdown, ending with one newline.
String writeMarkdown(List<Block> blocks) {
  final out = StringBuffer();
  var number = 0;
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    number = block.kind == BlockKind.numbered ? number + 1 : 0;
    if (i > 0) out.write('\n' * (1 + gapBetween(blocks[i - 1], block)));
    out.write(blockToMarkdown(block, number: number));
  }
  if (blocks.isNotEmpty) out.write('\n');
  return out.toString();
}

/// Blank lines written between [previous] and [block]: what the file had, or
/// none inside a list and one everywhere else.
int gapBetween(Block previous, Block block) => block.gapBefore ?? (block.isList && previous.isList ? 0 : 1);

String blockToMarkdown(Block block, {int number = 1}) {
  final indent = '  ' * block.level;
  switch (block.kind) {
    case BlockKind.paragraph:
      return block.text;
    case BlockKind.heading:
      return '${'#' * block.level.clamp(1, 6)} ${block.text}';
    case BlockKind.bullet:
      return '$indent${block.marker} ${block.text}';
    case BlockKind.numbered:
      return '$indent${block.number ?? number}. ${block.text}';
    case BlockKind.todo:
      return '$indent${block.marker} [${block.checked ? 'x' : ' '}] ${block.text}';
    case BlockKind.quote:
      return block.text.split('\n').map((l) => l.isEmpty ? '>' : '> $l').join('\n');
    case BlockKind.code:
      var fence = '```';
      while (block.text.contains(fence)) {
        fence += '`';
      }
      // A caption needs a language word in front of it so it can be read back.
      final language = block.language ?? (block.caption.isNotEmpty ? 'text' : '');
      final info = block.caption.isNotEmpty ? '$language ${block.caption}' : language;
      return '$fence$info\n${block.text}\n$fence';
    case BlockKind.divider:
      return '---';
    case BlockKind.image:
      return '![${block.alt}](${block.url})';
    case BlockKind.table || BlockKind.raw:
      return block.text;
  }
}

/// 1-based line number in [writeMarkdown]'s output where [index]'s block starts.
int blockStartLine(List<Block> blocks, int index) {
  var line = 1;
  for (var i = 0; i < index && i < blocks.length; i++) {
    line += '\n'.allMatches(blockToMarkdown(blocks[i])).length + 1 + gapBetween(blocks[i], blocks[i + 1]);
  }
  return line;
}
