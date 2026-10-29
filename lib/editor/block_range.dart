import 'package:flutter/services.dart';

import 'blocks.dart';
import 'page_document.dart';

/// Whether a block's text is edited in a plain text field, so a selection can
/// start or end part-way through it. Code spaces, tables, images and dividers
/// are either wholly inside a selection or outside it.
bool hasInlineText(Block block) => block.isText || block.kind == BlockKind.raw;

/// A selection that spans blocks: from [anchor], where it started, to
/// [focus], where it is now. Offsets count in a block's text.
class BlockRange {
  const BlockRange(this.anchor, this.focus);

  /// The range from [start] to [end], backward when [backward] is set.
  factory BlockRange.ordered(Caret start, Caret end, {bool backward = false}) =>
      backward ? BlockRange(end, start) : BlockRange(start, end);

  final Caret anchor;
  final Caret focus;

  bool get backward => focus.block < anchor.block || (focus.block == anchor.block && focus.offset < anchor.offset);
  Caret get start => backward ? focus : anchor;
  Caret get end => backward ? anchor : focus;
  bool get isCollapsed => anchor == focus;
  bool covers(int index) => index >= start.block && index <= end.block;

  /// The part of block [index]'s text inside the range, or null when the
  /// block is outside it. A block without inline text is selected whole.
  TextSelection? selectionIn(int index, Block block) {
    if (!covers(index)) return null;
    final length = block.text.length;
    if (!hasInlineText(block)) return TextSelection(baseOffset: 0, extentOffset: length);
    final from = index == start.block ? start.offset.clamp(0, length) : 0;
    final to = index == end.block ? end.offset.clamp(0, length) : length;
    return TextSelection(baseOffset: from, extentOffset: to < from ? from : to);
  }

  /// The same range with its offsets clamped to [blocks] as they are now.
  BlockRange clampTo(List<Block> blocks) {
    Caret clamp(Caret c) {
      final block = c.block.clamp(0, blocks.length - 1);
      return (block: block, offset: c.offset.clamp(0, blocks[block].text.length));
    }

    return BlockRange(clamp(anchor), clamp(focus));
  }

  @override
  bool operator ==(Object other) => other is BlockRange && other.anchor == anchor && other.focus == focus;

  @override
  int get hashCode => Object.hash(anchor, focus);

  @override
  String toString() => 'BlockRange(${anchor.block}:${anchor.offset} -> ${focus.block}:${focus.offset})';
}

/// The selected blocks, cut down to the selected part of the first and last.
List<Block> rangeBlocks(List<Block> blocks, BlockRange range) => [
      for (var i = range.start.block; i <= range.end.block && i < blocks.length; i++)
        hasInlineText(blocks[i])
            ? (() {
                final sel = range.selectionIn(i, blocks[i])!;
                return blocks[i].copyWith(text: blocks[i].text.substring(sel.start, sel.end));
              })()
            : blocks[i],
    ];

/// The selection as Markdown, the way it would be saved: what Ctrl+C copies.
String rangeMarkdown(List<Block> blocks, BlockRange range) {
  final picked = rangeBlocks(blocks, range);
  if (picked.isEmpty) return '';
  final out = writeMarkdown([for (final (i, b) in picked.indexed) i == 0 ? b.copyWith(clearGap: true) : b]);
  return out.endsWith('\n') ? out.substring(0, out.length - 1) : out;
}

/// Deletes the selection, or replaces it with [insert]: the text before the
/// selection in its first block and the text after it in its last block join
/// into one block. Returns the caret after the inserted text.
Caret deleteRange(PageDocument doc, BlockRange range, {String insert = ''}) {
  final s = range.start, e = range.end;
  final first = doc[s.block];
  final last = doc[e.block];
  final firstText = hasInlineText(first);
  final lastText = hasInlineText(last);
  final head = firstText ? first.text.substring(0, s.offset.clamp(0, first.text.length)) : '';
  final tail = lastText ? last.text.substring(e.offset.clamp(0, last.text.length)) : '';
  final Block kept;
  final Caret caret;
  if (firstText) {
    kept = first.copyWith(text: head + insert + tail);
    caret = (block: s.block, offset: head.length + insert.length);
  } else if (lastText) {
    kept = last.copyWith(text: insert + tail, gapBefore: first.gapBefore, clearGap: first.gapBefore == null);
    caret = (block: s.block, offset: insert.length);
  } else {
    kept = Block(kind: BlockKind.paragraph, text: insert);
    caret = (block: s.block, offset: insert.length);
  }
  doc.replaceRange(s.block, e.block + 1, [kept], before: s, after: caret);
  return caret;
}

/// The selection after trimming the spaces at either end: Markdown markers
/// have to hug the words ("** word**" is not bold).
TextSelection _trimmed(String value, TextSelection sel) {
  var start = sel.start, end = sel.end;
  while (start < end && value[start].trim().isEmpty) {
    start++;
  }
  while (end > start && value[end - 1].trim().isEmpty) {
    end--;
  }
  return TextSelection(baseOffset: start, extentOffset: end);
}

/// Whether the selection already has [marker] on both sides, inside or just
/// outside it.
bool hasMarker(String value, TextSelection sel, String marker) {
  final t = _trimmed(value, sel);
  final n = marker.length;
  final inner = value.substring(t.start, t.end);
  if (inner.length >= 2 * n && inner.startsWith(marker) && inner.endsWith(marker)) return true;
  return t.start >= n &&
      t.end + n <= value.length &&
      value.substring(t.start - n, t.start) == marker &&
      value.substring(t.end, t.end + n) == marker;
}

/// Wraps the selection in [marker] (`**`, `_`, `` ` ``, `~~`), or removes the
/// markers when it already has them. [remove] forces one or the other: a
/// selection already marked is not wrapped twice, and one without markers is
/// left as it is when removing. Returns the new text and selection.
({String text, TextSelection selection}) toggleMarker(String value, TextSelection sel, String marker, {bool? remove}) {
  final t = _trimmed(value, sel);
  final start = t.start, end = t.end;
  final n = marker.length;
  final inner = value.substring(start, end);
  final marked = hasMarker(value, sel, marker);
  if (remove ?? marked) {
    if (!marked) return (text: value, selection: sel);
    if (inner.length >= 2 * n && inner.startsWith(marker) && inner.endsWith(marker)) {
      return (
        text: value.replaceRange(start, end, inner.substring(n, inner.length - n)),
        selection: TextSelection(baseOffset: start, extentOffset: end - 2 * n),
      );
    }
    return (
      text: value.replaceRange(start - n, end + n, inner),
      selection: TextSelection(baseOffset: start - n, extentOffset: end - n),
    );
  }
  if (marked) return (text: value, selection: sel);
  return (
    text: value.replaceRange(start, end, '$marker$inner$marker'),
    selection: TextSelection(baseOffset: start + n, extentOffset: end + n),
  );
}

/// Bold, italic, strikethrough or code over every text block in the range,
/// as one undo step. When every selected part already has the marker it is
/// removed, otherwise added where it is missing. Returns the range over the
/// same text afterwards.
BlockRange formatRange(PageDocument doc, BlockRange range, String marker) {
  final s = range.start, e = range.end;
  final parts = <int, TextSelection>{};
  for (var i = s.block; i <= e.block; i++) {
    if (!doc[i].isText) continue;
    final sel = range.selectionIn(i, doc[i])!;
    if (doc[i].text.substring(sel.start, sel.end).trim().isEmpty) continue;
    parts[i] = sel;
  }
  if (parts.isEmpty) return range;
  final remove = parts.entries.every((p) => hasMarker(doc[p.key].text, p.value, marker));
  var start = s, end = e;
  final next = <Block>[];
  for (var i = s.block; i <= e.block; i++) {
    final sel = parts[i];
    if (sel == null) {
      next.add(doc[i]);
      continue;
    }
    final result = toggleMarker(doc[i].text, sel, marker, remove: remove);
    next.add(doc[i].copyWith(text: result.text));
    // Added markers stay inside the range, so the same key takes them off.
    final n = remove || result.text == doc[i].text ? 0 : marker.length;
    if (i == s.block) start = (block: i, offset: result.selection.start - n);
    if (i == e.block) end = (block: i, offset: result.selection.end + n);
  }
  doc.replaceRange(s.block, e.block + 1, next, before: s, after: end, resetGaps: false);
  return BlockRange.ordered(start, end, backward: range.backward);
}

/// Indents (or with a negative [delta], outdents) every list item in the range.
void indentRange(PageDocument doc, BlockRange range, int delta) {
  final s = range.start.block, e = range.end.block;
  final next = <Block>[];
  var changed = false;
  for (var i = s; i <= e; i++) {
    final b = doc[i];
    final level = b.isList ? (b.level + delta).clamp(0, 8) : b.level;
    if (level != b.level) changed = true;
    next.add(level == b.level ? b : b.copyWith(level: level, clearNumber: true));
  }
  if (changed) doc.replaceRange(s, e + 1, next, before: range.start, after: range.end, resetGaps: false);
}

/// Turns every text block in the range into [kind] at [level], keeping their
/// text. Text blocks turned into a code block join into one, a line each.
/// Returns where the caret goes when the blocks joined, or null when the
/// range still covers the same blocks.
Caret? convertRange(PageDocument doc, BlockRange range, BlockKind kind, int level) {
  final s = range.start.block, e = range.end.block;
  final picked = [for (var i = s; i <= e; i++) doc[i]];
  if (kind == BlockKind.code && picked.every((b) => b.isText)) {
    final code = Block(id: picked.first.id, kind: BlockKind.code, text: picked.map((b) => b.text).join('\n'));
    final caret = (block: s, offset: code.text.length);
    doc.replaceRange(s, e + 1, [code], before: range.start, after: caret);
    return caret;
  }
  final next = [
    for (final b in picked)
      !b.isText || (b.kind == kind && (kind != BlockKind.heading || b.level == level))
          ? b
          : Block(
              id: b.id,
              kind: kind,
              text: b.text,
              // A list item turned into another kind of list keeps its nesting.
              level: kind == BlockKind.heading ? level : (b.isList && Block(kind: kind).isList ? b.level : 0),
              marker: b.marker,
            ),
  ];
  doc.replaceRange(s, e + 1, next, before: range.start, after: range.end);
  return null;
}

/// Pastes [markdown] (copied from a selection that spanned blocks) into block
/// [index], between [head] and [tail]: its first block joins the text before
/// the caret, its last block the text after. Returns the caret after the
/// pasted text, or null when [markdown] is a single block, which pastes as
/// plain text.
Caret? pasteBlocks(PageDocument doc, int index, String head, String tail, String markdown) {
  final parsed = parseMarkdown(markdown);
  if (parsed.length < 2) return null;
  final current = doc[index];
  final out = <Block>[];
  final first = parsed.first;
  if (hasInlineText(first)) {
    out.add(head.isEmpty ? _withId(first, current.id, current.gapBefore) : current.copyWith(text: head + first.text));
  } else {
    if (head.isNotEmpty) out.add(current.copyWith(text: head));
    out.add(first);
  }
  // The pasted blocks take the default spacing around them.
  out.addAll([for (final b in parsed.sublist(1, parsed.length - 1)) b.copyWith(clearGap: true)]);
  final last = parsed.last.copyWith(clearGap: true);
  Caret caret;
  if (hasInlineText(last)) {
    out.add(last.copyWith(text: last.text + tail));
    caret = (block: index + out.length - 1, offset: last.text.length);
  } else {
    out.add(last);
    caret = (block: index + out.length - 1, offset: last.text.length);
    if (tail.isNotEmpty) {
      out.add(Block(kind: BlockKind.paragraph, text: tail));
      caret = (block: index + out.length - 1, offset: 0);
    }
  }
  doc.replaceRange(index, index + 1, out, before: (block: index, offset: head.length), after: caret);
  return caret;
}

/// [block] with the identity [id], so the field showing that block shows it.
Block _withId(Block block, int id, int? gapBefore) => Block(
      id: id,
      kind: block.kind,
      text: block.text,
      level: block.level,
      number: block.number,
      checked: block.checked,
      language: block.language,
      caption: block.caption,
      url: block.url,
      alt: block.alt,
      marker: block.marker,
      gapBefore: gapBefore,
    );
