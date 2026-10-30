import 'package:flutter/material.dart';

import '../../editor/spell_checker.dart';

/// Wavy red underlines under misspelled words, for a text controller.
mixin SpellingMarks on TextEditingController {
  /// Off for code and other verbatim text.
  bool get checkSpelling => true;

  /// Parts of the text never checked (inline code, link targets).
  List<TextRange> spellingSkips(String text) => const [];

  String? _checkedText;
  int _checkedGeneration = -1;
  List<TextRange> _misspelled = const [];

  /// The misspelled words in the text now. Cached until the text or the
  /// dictionary changes, so moving the caret costs nothing.
  List<TextRange> get misspellings {
    final checker = SpellChecker.instance;
    if (!checkSpelling || !checker.active) return const [];
    if (_checkedText != text || _checkedGeneration != checker.generation) {
      _checkedText = text;
      _checkedGeneration = checker.generation;
      _misspelled = checker.misspellings(text, skip: spellingSkips(text));
    }
    return _misspelled;
  }

  /// The misspelled word at the caret or covering the selection, if any.
  TextRange? misspellingAtSelection() {
    final sel = selection;
    if (!sel.isValid) return null;
    for (final r in misspellings) {
      if (r.start <= sel.start && sel.end <= r.end) return r;
    }
    return null;
  }

  /// [span] with the misspelled words underlined. While the field has focus
  /// ([withComposing]) the word right before the caret is left alone: it is
  /// probably still being typed.
  TextSpan markMisspellings(TextSpan span, {required bool withComposing, Color color = const Color(0xFFE5484D)}) {
    var ranges = misspellings;
    if (ranges.isEmpty) return span;
    if (withComposing && selection.isValid && selection.isCollapsed) {
      final caret = selection.baseOffset;
      ranges = [for (final r in ranges) if (r.end != caret) r];
      if (ranges.isEmpty) return span;
    }
    final mark = TextStyle(
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.wavy,
      decorationColor: color,
    );
    var offset = 0;
    InlineSpan walk(InlineSpan s) {
      if (s is! TextSpan) {
        offset += 1; // a placeholder is one character
        return s;
      }
      final pieces = <InlineSpan>[];
      var marked = false;
      final t = s.text;
      if (t != null && t.isNotEmpty) {
        final start = offset;
        final end = start + t.length;
        var at = start;
        for (final r in ranges) {
          if (r.end <= at || r.start >= end) continue;
          final a = r.start < at ? at : r.start;
          final b = r.end > end ? end : r.end;
          if (a > at) pieces.add(TextSpan(text: t.substring(at - start, a - start)));
          marked = true;
          final own = s.style?.decoration;
          pieces.add(TextSpan(
            text: t.substring(a - start, b - start),
            style: own == null || own == TextDecoration.none
                ? mark
                : mark.copyWith(decoration: TextDecoration.combine([own, TextDecoration.underline])),
          ));
          at = b;
        }
        if (at < end) pieces.add(TextSpan(text: t.substring(at - start)));
        offset = end;
      }
      final children = [for (final c in s.children ?? const <InlineSpan>[]) walk(c)];
      if (!marked) {
        return TextSpan(text: t, style: s.style, children: s.children == null ? null : children, recognizer: s.recognizer);
      }
      return TextSpan(style: s.style, children: [...pieces, ...children], recognizer: s.recognizer);
    }

    return walk(span) as TextSpan;
  }

  /// Replaces the misspelled word [range] with [word] as if typed, so the
  /// field's change handlers run.
  static void replace(EditableTextState state, TextRange range, String word) {
    final value = state.textEditingValue;
    state.userUpdateTextEditingValue(
      TextEditingValue(
        text: value.text.replaceRange(range.start, range.end, word),
        selection: TextSelection.collapsed(offset: range.start + word.length),
      ),
      SelectionChangedCause.toolbar,
    );
  }
}

/// A plain text controller with spelling marks (table cells).
class SpellCheckedController extends TextEditingController with SpellingMarks {
  SpellCheckedController({super.text});

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final span = super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    if (withComposing && value.composing.isValid) return span;
    return markMisspellings(span, withComposing: withComposing);
  }
}

/// The right-click menu of a text field, with spelling suggestions on top
/// when the click landed on a misspelled word.
Widget spellingContextMenu(BuildContext context, EditableTextState state) {
  final controller = state.widget.controller;
  final items = <ContextMenuButtonItem>[];
  final range = controller is SpellingMarks && !state.widget.readOnly ? controller.misspellingAtSelection() : null;
  if (range != null) {
    final word = range.textInside(controller.text);
    final suggestions = SpellChecker.instance.suggestions(word, limit: 5);
    for (final s in suggestions) {
      items.add(ContextMenuButtonItem(
        label: s,
        onPressed: () {
          state.hideToolbar();
          SpellingMarks.replace(state, range, s);
        },
      ));
    }
    if (suggestions.isEmpty) items.add(const ContextMenuButtonItem(label: 'No suggestions', onPressed: null));
    items
      ..add(ContextMenuButtonItem(
        label: 'Add to dictionary',
        onPressed: () {
          state.hideToolbar();
          SpellChecker.instance.addWord(word);
        },
      ))
      ..add(ContextMenuButtonItem(
        label: 'Ignore',
        onPressed: () {
          state.hideToolbar();
          SpellChecker.instance.ignore(word);
        },
      ));
  }
  items.addAll(state.contextMenuButtonItems);
  return AdaptiveTextSelectionToolbar.buttonItems(anchors: state.contextMenuAnchors, buttonItems: items);
}
