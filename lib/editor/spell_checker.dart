import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'links.dart';

typedef _Index = ({Map<String, int> exact, Map<String, String> lower});

/// Checks English (US) spelling against a bundled word list (SCOWL size 60,
/// the size most spell checkers ship) and the words the user added.
///
/// Words in capitals (acronyms), words with a capital inside (StackSpace,
/// iPhone), and anything that looks like a file name, path, address or code
/// are left alone, so notes full of names and code are not covered in marks.
class SpellChecker extends ChangeNotifier {
  SpellChecker();

  static final instance = SpellChecker();

  static const asset = 'assets/spelling/en_US.txt.gz';

  /// Each word as written in the list, with its place in it. The list is
  /// ordered from the most common words to the rarest, so a lower place is a
  /// better suggestion.
  var _exact = <String, int>{};

  /// The lower-case form of each word, to its most common written form.
  var _lower = <String, String>{};

  final _added = <String>{};
  final _ignored = <String>{};
  bool _enabled = true;
  bool _ready = false;

  /// Called with every added word whenever one is added, to save them.
  void Function(List<String> words)? onAddedChanged;

  /// Bumped on every change that can turn a mark on or off, so a cached
  /// result can tell it is stale.
  int get generation => _generation;
  int _generation = 0;

  bool get enabled => _enabled;
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    _changed();
  }

  /// Whether text is checked now: turned on and the word list loaded.
  bool get active => _enabled && _ready;

  List<String> get addedWords => _added.toList()..sort();

  /// Loads the bundled word list. Unpacking and indexing it (a few hundred
  /// milliseconds) happens off the UI thread.
  Future<void> load() async {
    final data = await rootBundle.load(asset);
    _use(await compute(_unpack, data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
  }

  static _Index _unpack(Uint8List bytes) => _index(const LineSplitter().convert(utf8.decode(gzip.decode(bytes))));

  /// Uses [words] (most common first) as the word list.
  void useWords(Iterable<String> words) => _use(_index(words));

  static _Index _index(Iterable<String> words) {
    final exact = <String, int>{};
    final lower = <String, String>{};
    var i = 0;
    for (final raw in words) {
      final w = raw.trim();
      if (w.isEmpty) continue;
      exact.putIfAbsent(w, () => i++);
      lower.putIfAbsent(w.toLowerCase(), () => w);
    }
    return (exact: exact, lower: lower);
  }

  void _use(_Index index) {
    _exact = index.exact;
    _lower = index.lower;
    _ready = true;
    _changed();
  }

  /// The user's own words, saved between runs.
  void setAddedWords(Iterable<String> words) {
    _added
      ..clear()
      ..addAll(words.map(_normal));
    _changed();
  }

  /// Adds [word] to the user's dictionary.
  void addWord(String word) {
    if (!_added.add(_normal(word))) return;
    onAddedChanged?.call(addedWords);
    _changed();
  }

  /// Stops marking [word] until the app closes.
  void ignore(String word) {
    if (!_ignored.add(_normal(word))) return;
    _changed();
  }

  void _changed() {
    _generation++;
    notifyListeners();
  }

  static String _normal(String word) => word.replaceAll('’', "'");

  /// Whether [word] (letters, maybe with apostrophes inside) is spelled right,
  /// or is a kind of word that is not checked.
  bool isCorrect(String word) {
    final w = _normal(word);
    if (w.length < 2 || !_ready) return true;
    // Acronyms and words with capitals inside are names more often than not.
    if (w.substring(1).contains(_upper)) return true;
    if (_added.contains(w) || _ignored.contains(w)) return true;
    final lower = w.toLowerCase();
    if (_added.contains(lower) || _ignored.contains(lower)) return true;
    if (_known(w)) return true;
    // "The" at the start of a sentence: the lower-case word is in the list.
    if (w != lower && _known(lower)) return true;
    return false;
  }

  bool _known(String w) {
    if (_exact.containsKey(w)) return true;
    // Possessives are not in the list: "Kevin's" is right if "Kevin" is.
    if (w.endsWith("'s") && w.length > 3) return _exact.containsKey(w.substring(0, w.length - 2));
    return false;
  }

  static final _upper = RegExp(r'[A-ZÀ-Þ]');
  static final _word = RegExp("[A-Za-zÀ-ÖØ-öø-ÿ]+(?:['’][A-Za-zÀ-ÖØ-öø-ÿ]+)*");
  static final _letter = RegExp('[A-Za-zÀ-ÖØ-öø-ÿ]');

  /// Characters that, right next to a word, show it is part of a path,
  /// address, number or code rather than prose.
  static const _codeNeighbours = r'0123456789_/\@#$%&=<>|{}~^+';

  /// The misspelled words in [text], leaving out anything inside [skip]
  /// (code and links) and inside URLs.
  List<TextRange> misspellings(String text, {List<TextRange> skip = const []}) {
    if (!_ready || text.isEmpty) return const [];
    final out = <TextRange>[];
    final skips = [
      ...skip,
      for (final m in bareUrlPattern.allMatches(text)) TextRange(start: m.start, end: m.end),
    ];
    for (final m in _word.allMatches(text)) {
      if (skips.any((s) => m.start < s.end && m.end > s.start)) continue;
      if (_partOfCode(text, m.start, m.end)) continue;
      if (!isCorrect(m.group(0)!)) out.add(TextRange(start: m.start, end: m.end));
    }
    return out;
  }

  static bool _partOfCode(String text, int start, int end) {
    final before = start > 0 ? text[start - 1] : '';
    final after = end < text.length ? text[end] : '';
    if (before.isNotEmpty && _codeNeighbours.contains(before)) return true;
    if (after.isNotEmpty && _codeNeighbours.contains(after)) return true;
    // file.txt, example.com, obj.method
    if (after == '.' && end + 1 < text.length && _letter.hasMatch(text[end + 1])) return true;
    if (before == '.' && start > 1 && _letter.hasMatch(text[start - 2])) return true;
    // scheme: and drive letters
    if (after == ':' && end + 1 < text.length && (text[end + 1] == '/' || text[end + 1] == r'\')) return true;
    return false;
  }

  /// Up to [limit] likely corrections for [word], best first, in the word's
  /// own capitalisation.
  List<String> suggestions(String word, {int limit = 6}) {
    if (!_ready) return const [];
    final w = _normal(word);
    final lower = w.toLowerCase();
    final scored = <String, List<int>>{};
    void consider(String candidate, int distance) {
      final form = _lower[candidate];
      if (form == null || candidate == lower) return;
      // Keep the lower-case form when the list has both "may" and "May".
      final written = _exact.containsKey(candidate) ? candidate : form;
      // Fewer edits first; then words with the same first letter, then plain
      // words over names and abbreviations, then the more common word.
      final score = [
        distance,
        candidate[0] == lower[0] ? 0 : 1,
        written == candidate ? 0 : 1,
        _exact[written]!,
      ];
      final old = scored[written];
      if (old == null || _compare(score, old) < 0) scored[written] = score;
    }

    // Two letters swapped is the most common slip ("teh"), so it counts as
    // less than one edit.
    for (var i = 0; i + 1 < lower.length; i++) {
      consider(lower.substring(0, i) + lower[i + 1] + lower[i] + lower.substring(i + 2), 0);
    }
    final near = _edits(lower);
    for (final e in near) {
      consider(e, 1);
    }
    // Two edits away only when one is not enough, and only for words short
    // enough that it stays quick (each step multiplies the candidates).
    if (scored.length < limit && lower.length <= 14) {
      for (final e in near) {
        for (final e2 in _edits(e)) {
          if (!scored.containsKey(e2)) consider(e2, 2);
        }
      }
    }
    final best = scored.keys.toList()..sort((a, b) => _compare(scored[a]!, scored[b]!));
    return [for (final s in best.take(limit)) _caseLike(w, s)];
  }

  static int _compare(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return 0;
  }

  static const _alphabet = "abcdefghijklmnopqrstuvwxyz'";

  /// Every string one deletion, swap, replacement or insertion away.
  static Set<String> _edits(String w) {
    final out = <String>{};
    for (var i = 0; i <= w.length; i++) {
      final a = w.substring(0, i), b = w.substring(i);
      if (b.isNotEmpty) out.add(a + b.substring(1));
      if (b.length > 1) out.add(a + b[1] + b[0] + b.substring(2));
      for (var k = 0; k < _alphabet.length; k++) {
        final c = _alphabet[k];
        if (b.isNotEmpty && c != b[0]) out.add(a + c + b.substring(1));
        out.add(a + c + b);
      }
    }
    return out;
  }

  /// [suggestion] capitalised like [word]: "Teh" gives "The".
  static String _caseLike(String word, String suggestion) {
    if (suggestion.isEmpty || !_upper.hasMatch(word[0])) return suggestion;
    return suggestion[0].toUpperCase() + suggestion.substring(1);
  }
}
