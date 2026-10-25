import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../editor/blocks.dart';
import 'code_block.dart';
import 'inline_markdown.dart';
import 'table_block.dart';

/// The height of every row in the block list, computed before the row is
/// built.
///
/// The list gives each row a fixed extent, so a jump to the end of a page of
/// 50,000 blocks (dragging the scrollbar, Ctrl+End) costs a sum of numbers
/// instead of laying out every block in between. The numbers mirror the
/// widgets in `block_editor.dart` exactly: the same text styles, struts,
/// paddings and marker sizes, measured with a [TextPainter] at the row's
/// width. `test/block_metrics_test.dart` checks them against the rendered
/// widgets for every block kind.
class BlockMetrics {
  BlockMetrics({required this.palette, required this.textScaler, required this.inputStyle});

  final StackPalette palette;
  final TextScaler textScaler;

  /// The theme style a TextField merges its own style onto (font family and
  /// letter spacing come from here), see [inputStyleOf].
  final TextStyle inputStyle;

  /// The base style of every TextField under [context]'s theme.
  static TextStyle inputStyleOf(BuildContext context) {
    final theme = Theme.of(context);
    return theme.useMaterial3 ? theme.textTheme.bodyLarge! : theme.textTheme.titleMedium!;
  }

  /// Smallest line height of a text block, in logical pixels.
  static const minLineHeight = 24.0;

  /// Padding at the right of the list; at the left each row has a [gutter]
  /// holding its handle instead.
  static const listPadding = 22.0;
  static const gutter = 24.0;

  /// Height of the empty row after the last block.
  static const tailHeight = 120.0;

  static const mono =
      TextStyle(fontFamily: 'Cascadia Mono', fontFamilyFallback: StackType.mono, fontSize: 14, height: 1.45);

  /// Text style of a text block. Every line is at least 24 px tall, so a
  /// one-line block is a tap target of the size WCAG 2.2 asks for (the block
  /// handle beside a row keeps the row from merging with its padding).
  static TextStyle styleFor(Block block, StackPalette palette) {
    switch (block.kind) {
      case BlockKind.heading:
        final size = switch (block.level) { 1 => 30.0, 2 => 24.0, 3 => 20.0, 4 => 17.0, _ => 15.5 };
        return StackType.display(size, palette.text).copyWith(height: math.max(1.3, minLineHeight / size));
      case BlockKind.code || BlockKind.table || BlockKind.raw:
        return mono.copyWith(color: palette.text);
      case BlockKind.quote:
        return TextStyle(
            fontSize: 15.5, height: minLineHeight / 15.5, color: palette.subText, fontStyle: FontStyle.italic);
      default:
        return TextStyle(fontSize: 15.5, height: minLineHeight / 15.5, color: palette.text);
    }
  }

  /// Space above a row: none for the first, little between list items.
  static double gapAbove(Block block, Block? previous) =>
      previous == null ? 0 : (block.isList && previous.isList ? 2 : 10);

  /// Height of the row for [block] in a list [width] wide (inside the list
  /// padding), including the gap above it.
  double rowHeight(Block block, Block? previous, double width, {bool wrap = false, bool caption = false}) =>
      gapAbove(block, previous) + bodyHeight(block, width, wrap: wrap, caption: caption);

  double bodyHeight(Block block, double width, {bool wrap = false, bool caption = false}) {
    switch (block.kind) {
      case BlockKind.divider:
        return 26; // 1 px border, Divider(height: 24), 1 px border
      case BlockKind.image:
        return _imageHeight(block, width);
      case BlockKind.table:
        return TableBlockView.heightFor(block);
      case BlockKind.code:
        return CodeBlockView.heightFor(block, width,
            wrap: wrap, caption: caption, textScaler: textScaler, inputStyle: inputStyle);
      default:
        return _textHeight(block, width);
    }
  }

  double _textHeight(Block block, double width) {
    final style = inputStyle.merge(styleFor(block, palette));
    final boxed = block.kind == BlockKind.raw;
    final isList = block.isList;
    final padLeft = isList ? 24.0 * block.level : 0.0;
    final EdgeInsets padding = boxed
        ? const EdgeInsets.fromLTRB(10, 6, 10, 8)
        : block.kind == BlockKind.quote
            ? const EdgeInsets.only(left: 14)
            : block.kind == BlockKind.heading
                ? EdgeInsets.only(top: block.level == 1 ? 10 : 6)
                : EdgeInsets.zero;
    final markerWidth = isList ? 24.0 + 8.0 : 0.0;
    final fieldWidth = math.max(0.0, width - padLeft - padding.horizontal - markerWidth);
    final double field;
    if (fitsOneLine(block.text, style, fieldWidth)) {
      field = lineHeight(style);
    } else {
      field = textHeight(
        InlineMarkdownController.spanFor(block.text, style,
            styled: block.isText, markerColor: palette.subText, codeColor: palette.accentB, linkColor: palette.accentA),
        style,
        fieldWidth,
      );
    }
    final marker = switch (block.kind) {
      BlockKind.todo => 24.0,
      BlockKind.bullet || BlockKind.numbered => lineHeight(style),
      _ => 0.0,
    };
    return padding.vertical + math.max(field, marker);
  }

  /// Height of one line of [style], as the text field lays it out.
  /// True when [text] is certain to lay out on one line: no line break, and
  /// even at the widest glyph a font is likely to have (1.3 em) it fits.
  /// Most rows of a page are short, so they skip the text layout.
  bool fitsOneLine(String text, TextStyle style, double width) =>
      !text.contains('\n') && text.length * textScaler.scale(style.fontSize ?? 16) * 1.3 <= width;

  final _lineHeights = <TextStyle, double>{};

  double lineHeight(TextStyle style) =>
      _lineHeights[style] ??= textHeight(TextSpan(text: ' ', style: style), style, double.infinity);

  /// Height of [span] laid out like a text field: a strut from [style] keeps
  /// every line the same height whatever fonts the spans use.
  double textHeight(InlineSpan span, TextStyle style, double width) {
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
    )..layout(maxWidth: width);
    final height = math.max(painter.height, painter.preferredLineHeight);
    painter.dispose();
    return height;
  }

  double _imageHeight(Block block, double width) {
    // _NonTextBlock: 1 px border top and bottom; _ImageBlock: 6 px above and below.
    const frame = 2.0 + 12.0;
    double body;
    if (block.url.isNotEmpty && resolvesImage?.call(block) == true) {
      body = ImageBlockMetrics.imageHeight;
    } else {
      // One clipped line of the path next to an 18 px icon, 10 px padding around.
      body = 20 + math.max(18.0, lineHeight(ImageBlockMetrics.pathStyle));
    }
    return frame + body + 4 + ImageBlockMetrics.altHeight;
  }

  /// Tells whether an image block's file exists (set by the editor); a
  /// missing file shows the path instead of a picture.
  bool Function(Block block)? resolvesImage;
}

/// Sizes shared by the image block and its metrics.
class ImageBlockMetrics {
  /// Pictures are shown in a box of this height, scaled to fit.
  static const imageHeight = 300.0;

  /// Single-line texts with an explicit line height, so their height does not
  /// depend on the theme's font.
  static const pathStyle = TextStyle(fontSize: StackType.button, height: 1.3);
  static const altStyle = TextStyle(fontSize: StackType.hint, height: 1.3);

  /// The description field under a picture: tall enough to be a click target.
  static const altHeight = 24.0;
}
