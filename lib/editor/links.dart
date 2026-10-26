import 'package:url_launcher/url_launcher.dart' as launcher;

/// Links in a text block: Markdown `[label](url)` and bare `https://…` URLs.
///
/// The page is Markdown, so a link *is* its text; these helpers find links
/// in a block, turn a pasted URL into a link, and open a link safely.
class LinkMatch {
  const LinkMatch({required this.start, required this.end, required this.url, required this.label});

  /// Range of the whole link in the block's text (`[label](url)` or the URL).
  final int start;
  final int end;
  final String url;
  final String label;

  bool get isMarkdown => label != url;
}

/// `[label](url)` with no newline inside; the label may hold `*` or `` ` ``.
final markdownLinkPattern = RegExp(r'\[([^\]\n]+?)\]\(([^)\s]+?)\)');

/// A bare URL: `http(s)://` or `www.` up to whitespace, never ending in
/// punctuation that is more likely to belong to the sentence.
final bareUrlPattern = RegExp(r'(?<![\w/\]\(])(?:https?://|www\.)[^\s<>()\[\]]*[^\s<>()\[\].,;:!?' "'" r'"]');

/// Every link in [text], in order; a URL inside a Markdown link is part of it.
List<LinkMatch> linksIn(String text) {
  final found = <LinkMatch>[];
  final taken = <(int, int)>[];
  for (final m in markdownLinkPattern.allMatches(text)) {
    found.add(LinkMatch(start: m.start, end: m.end, url: m.group(2)!, label: m.group(1)!));
    taken.add((m.start, m.end));
  }
  for (final m in bareUrlPattern.allMatches(text)) {
    if (taken.any((t) => m.start >= t.$1 && m.start < t.$2)) continue;
    found.add(LinkMatch(start: m.start, end: m.end, url: m.group(0)!, label: m.group(0)!));
  }
  found.sort((a, b) => a.start.compareTo(b.start));
  return found;
}

/// The link under [offset] (a caret just after it counts), or null.
LinkMatch? linkAt(String text, int offset) {
  for (final link in linksIn(text)) {
    if (offset >= link.start && offset <= link.end) return link;
  }
  return null;
}

/// True when [text] is one URL and nothing else, so a paste of it should
/// become a link.
bool isUrl(String text) {
  final t = text.trim();
  if (t.isEmpty || t.contains(RegExp(r'\s'))) return false;
  final m = bareUrlPattern.firstMatch(t);
  return m != null && m.start == 0 && m.end == t.length;
}

/// A text change that inserted exactly one URL: where it went and what it
/// replaced. Null for any other change (typing, a longer paste, a deletion).
({int start, String removed, String url})? pastedUrl(String before, String after) {
  if (after.length <= before.length) return null;
  // Typing adds one character at a time; a paste adds the whole URL at once.
  // Without this, typing the "e" of "https://e" would be taken for a paste
  // of "https://e" over "https://".
  var prefix = 0;
  while (prefix < before.length && prefix < after.length && before[prefix] == after[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < before.length - prefix &&
      suffix < after.length - prefix &&
      before[before.length - 1 - suffix] == after[after.length - 1 - suffix]) {
    suffix++;
  }
  if (after.length - prefix - suffix < 2) return null;
  // The URL and the text around it can share characters ("here" → "https"),
  // so try every URL in the result rather than the longest common prefix.
  for (final m in bareUrlPattern.allMatches(after)) {
    final url = m.group(0)!;
    if (url.length < 8) continue;
    final tail = after.length - m.end;
    final removedLength = before.length - m.start - tail;
    if (removedLength < 0 || removedLength >= url.length) continue;
    if (!after.startsWith(before.substring(0, m.start))) continue;
    if (before.substring(m.start + removedLength) != after.substring(m.end)) continue;
    return (start: m.start, removed: before.substring(m.start, m.start + removedLength), url: url);
  }
  return null;
}

/// The URI the app will open for [url], or null when the scheme is not one
/// the app opens (only web pages and mail links; never `file:`, `javascript:`
/// or anything else).
Uri? safeUri(String url) {
  var text = url.trim();
  if (text.startsWith('www.')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' || scheme == 'https') return uri.host.isEmpty ? null : uri;
  if (scheme == 'mailto') return uri.path.isEmpty ? null : uri;
  return null;
}

/// Opens a URI with the system browser or mail app; tests swap it.
Future<bool> Function(Uri uri) launch = (uri) => launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);

/// Opens [url] when it is safe; returns what happened for the status line.
Future<String?> openLink(String url) async {
  final uri = safeUri(url);
  if (uri == null) return 'Only web and mail links can be opened: $url';
  try {
    final ok = await launch(uri);
    return ok ? null : 'Could not open $url';
  } catch (e) {
    return 'Could not open $url: $e';
  }
}
