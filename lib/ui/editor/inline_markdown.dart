import 'package:flutter/material.dart';

import '../../editor/links.dart';

/// A text controller that shows inline Markdown (bold, italic, code, strike,
/// links) styled while keeping the markers in the text, so what is saved is
/// exactly what was typed.
class InlineMarkdownController extends TextEditingController {
  InlineMarkdownController({super.text});

  /// Off for code and other verbatim blocks.
  bool styled = true;

  String? _staleOld;
  String? _staleNew;

  /// Records that the editor itself changed this field's text from [from] to
  /// [to] while it may be receiving typing from the platform. The platform's
  /// text input keeps its own copy of the text, so for a moment it can still
  /// send updates built on the old text; [reconcile] moves them onto the new.
  void expectChange(String from, String to) {
    if (from == to) return;
    _staleOld = from;
    _staleNew = to;
  }

  /// Maps an incoming [value] that is still based on the text before
  /// [expectChange] onto the new text, and makes the field show it. Returns
  /// the value to use.
  TextEditingValue reconcile(TextEditingValue value) {
    final old = _staleOld;
    final now = _staleNew;
    if (old == null || now == null) return value;
    // A late update always carries more than the old text: the platform only
    // sends a change. Anything else is built on the new text.
    if (value.text == now || value.text.length <= old.length || !value.text.startsWith(old)) {
      _staleOld = null;
      _staleNew = null;
      return value;
    }
    final shift = now.length - old.length;
    final fixed = TextEditingValue(
      text: now + value.text.substring(old.length),
      selection: value.selection.isValid
          ? TextSelection(
              baseOffset: (value.selection.baseOffset + shift).clamp(0, 1 << 30),
              extentOffset: (value.selection.extentOffset + shift).clamp(0, 1 << 30),
            )
          : const TextSelection.collapsed(offset: 0),
    );
    this.value = fixed;
    return fixed;
  }

  Color markerColor = const Color(0xFF888888);
  Color codeColor = const Color(0xFF888888);
  Color linkColor = const Color(0xFF4488FF);

  static final _pattern = RegExp(
    '${r'(\*\*[^*\n]+?\*\*)|(`[^`\n]+?`)|(~~[^~\n]+?~~)|(\[[^\]\n]+?\]\([^)\n]+?\))|(?<![\w*])(\*[^*\n]+?\*)(?![\w*])|(?<![\w_])(_[^_\n]+?_)(?![\w_])|('}${bareUrlPattern.pattern})',
  );

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (!styled || text.isEmpty || (withComposing && value.composing.isValid)) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    return spanFor(text, style ?? const TextStyle(),
        styled: true, markerColor: markerColor, codeColor: codeColor, linkColor: linkColor);
  }

  /// The styled span for [text], also used to measure a block's height
  /// before it is built, so it must match what the field shows exactly.
  static TextSpan spanFor(String text, TextStyle base,
      {required bool styled, required Color markerColor, required Color codeColor, required Color linkColor}) {
    if (!styled || text.isEmpty) return TextSpan(text: text, style: base);
    final marker = base.copyWith(color: markerColor);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _pattern.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final s = m.group(0)!;
      if (m.group(1) != null) {
        spans.addAll(_wrapped(s, 2, marker, base.copyWith(fontWeight: FontWeight.w700)));
      } else if (m.group(2) != null) {
        spans.addAll(_wrapped(
            s,
            1,
            marker,
            base.copyWith(
                fontFamily: 'Cascadia Mono',
                fontFamilyFallback: const ['Consolas', 'DejaVu Sans Mono', 'monospace'],
                color: codeColor)));
      } else if (m.group(3) != null) {
        spans.addAll(_wrapped(s, 2, marker, base.copyWith(decoration: TextDecoration.lineThrough)));
      } else if (m.group(4) != null) {
        final close = s.indexOf(']');
        spans.add(TextSpan(text: '[', style: marker));
        spans.add(TextSpan(
            text: s.substring(1, close),
            style: base.copyWith(color: linkColor, decoration: TextDecoration.underline, decorationColor: linkColor)));
        spans.add(TextSpan(text: s.substring(close), style: marker));
      } else if (m.group(7) != null) {
        // A bare URL is a link too (Bug 2); Ctrl+click opens it.
        spans.add(TextSpan(
            text: s,
            style: base.copyWith(color: linkColor, decoration: TextDecoration.underline, decorationColor: linkColor)));
      } else {
        spans.addAll(_wrapped(s, 1, marker, base.copyWith(fontStyle: FontStyle.italic)));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(style: base, children: spans);
  }

  static List<InlineSpan> _wrapped(String s, int n, TextStyle marker, TextStyle inner) => [
        TextSpan(text: s.substring(0, n), style: marker),
        TextSpan(text: s.substring(n, s.length - n), style: inner),
        TextSpan(text: s.substring(s.length - n), style: marker),
      ];
}
