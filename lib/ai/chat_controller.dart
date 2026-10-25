import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app/settings.dart';
import '../workspace/workspace.dart';
import 'ollama_client.dart';
import 'workspace_tools.dart';

enum OllamaStatus { unknown, connecting, connected, offline }

/// What the user is looking at when they send a message: the open page and
/// any text they have selected in it.
class ChatContext {
  const ChatContext({this.pagePath, this.pageText, this.selection, this.selectionStartLine, this.selectionEndLine});

  final String? pagePath;
  final String? pageText;
  final String? selection;
  final int? selectionStartLine;
  final int? selectionEndLine;

  bool get hasSelection => selection != null && selection!.trim().isNotEmpty;
}

sealed class ChatItem {}

class UserItem extends ChatItem {
  UserItem(this.text, this.contextLabels);
  final String text;
  final List<String> contextLabels;
}

class AssistantItem extends ChatItem {
  final thinking = StringBuffer();
  final content = StringBuffer();
  bool streaming = true;
  final DateTime started = DateTime.now();
  Duration? thoughtFor;
  DateTime? _thinkingEnded;
}

enum ToolStatus { running, done, failed }

class ToolItem extends ChatItem {
  ToolItem(this.name, this.arguments);
  final String name;
  final Map<String, dynamic> arguments;
  ToolStatus status = ToolStatus.running;
  String summary = '';
  String result = '';
  AiEdit? edit;
}

class ErrorItem extends ChatItem {
  ErrorItem(this.message);
  final String message;
}

/// Runs the conversation with the local model: sends the user's message with
/// the current page as context, streams the reply, and carries out any tool
/// calls the model makes until it gives a final answer.
class ChatController extends ChangeNotifier {
  ChatController({
    required this.settings,
    required this.tools,
    OllamaClient Function(String baseUrl)? clientFactory,
  }) : _clientFactory = clientFactory ?? ((url) => OllamaClient(baseUrl: url, httpClient: http.Client()));

  final AppSettings settings;
  final WorkspaceTools tools;
  final OllamaClient Function(String baseUrl) _clientFactory;

  /// Called before each message is sent, so the editor can save unsaved text
  /// and the model sees what's on screen.
  Future<void> Function()? beforeSend;

  static const maxToolRounds = 15;
  static const _maxPageChars = 24000;

  final List<ChatItem> items = [];
  final List<Map<String, dynamic>> _history = [];

  OllamaStatus status = OllamaStatus.unknown;
  String? statusMessage;
  String? ollamaVersion;
  List<OllamaModel> models = const [];
  ModelCapabilities capabilities = const ModelCapabilities();
  int? lastPromptTokens;

  bool _busy = false;
  bool get busy => _busy;
  bool _stopRequested = false;
  OllamaClient? _activeClient;

  Workspace get workspace => tools.workspace;
  String? get model => settings.model;
  ThinkLevel get thinkLevel => settings.thinkLevel;

  /// True when the selected model is a thinking model that takes a level
  /// instead of on/off.
  bool get supportsThinkLevels => (model ?? '').toLowerCase().contains('gpt-oss');

  Future<void> connect() async {
    status = OllamaStatus.connecting;
    statusMessage = null;
    notifyListeners();
    final client = _clientFactory(settings.ollamaUrl);
    try {
      ollamaVersion = await client.version();
      models = await client.listModels();
      status = OllamaStatus.connected;
      if (models.isEmpty) {
        statusMessage = 'Ollama is running but has no models. Run "ollama pull qwen3" in a terminal.';
      } else if (model == null || !models.any((m) => m.name == model)) {
        settings.model = models.first.name;
      }
      if (model != null && models.isNotEmpty) await _loadCapabilities(client);
    } on OllamaException catch (e) {
      status = OllamaStatus.offline;
      statusMessage = e.message;
      models = const [];
    } finally {
      client.close();
    }
    notifyListeners();
  }

  Future<void> selectModel(String name) async {
    settings.model = name;
    notifyListeners();
    final client = _clientFactory(settings.ollamaUrl);
    try {
      await _loadCapabilities(client);
    } on OllamaException catch (e) {
      statusMessage = e.message;
    } finally {
      client.close();
    }
    notifyListeners();
  }

  void setThinkLevel(ThinkLevel level) {
    settings.thinkLevel = level;
    notifyListeners();
  }

  Future<void> _loadCapabilities(OllamaClient client) async {
    capabilities = await client.show(model!);
  }

  void newChat() {
    if (_busy) stop();
    items.clear();
    _history.clear();
    lastPromptTokens = null;
    notifyListeners();
  }

  void stop() {
    if (!_busy) return;
    _stopRequested = true;
    _activeClient?.close();
  }

  Future<void> send(String text, {ChatContext context = const ChatContext()}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _busy) return;
    if (model == null) {
      items.add(ErrorItem('No model selected. Start Ollama and pick a model first.'));
      notifyListeners();
      return;
    }
    _busy = true;
    _stopRequested = false;
    items.add(UserItem(trimmed, _contextLabels(context)));
    notifyListeners();

    try {
      await beforeSend?.call();
      _history.add({'role': 'user', 'content': _withContext(trimmed, context)});
      await _runAgent();
    } finally {
      _busy = false;
      _activeClient = null;
      notifyListeners();
    }
  }

  List<String> _contextLabels(ChatContext context) => [
        if (context.pagePath != null) context.pagePath!,
        if (context.hasSelection)
          context.selectionStartLine == context.selectionEndLine
              ? 'Selection: line ${context.selectionStartLine}'
              : 'Selection: lines ${context.selectionStartLine}-${context.selectionEndLine}',
      ];

  String _withContext(String text, ChatContext context) {
    if (context.pagePath == null && !context.hasSelection) return text;
    final buffer = StringBuffer('<context>\n');
    final path = context.pagePath;
    if (path != null) {
      final page = context.pageText ?? '';
      final lineCount = page.isEmpty ? 0 : page.split('\n').length;
      buffer.writeln('The user has the page "$path" open ($lineCount lines).');
      if (page.length <= _maxPageChars) {
        buffer
          ..writeln('<page path="$path">')
          ..writeln(_numbered(page))
          ..writeln('</page>');
      } else {
        buffer.writeln('It is too long to include here; use read_page to read the parts you need.');
      }
    }
    if (context.hasSelection) {
      final where = path == null ? '' : ' of "$path"';
      buffer
        ..writeln('The user selected lines ${context.selectionStartLine}-${context.selectionEndLine}$where. '
            'When they say "this", they mean the selection.')
        ..writeln('<selection>')
        ..writeln(context.selection)
        ..writeln('</selection>');
    }
    buffer
      ..writeln('</context>')
      ..writeln()
      ..write(text);
    return buffer.toString();
  }

  static String _numbered(String text) {
    final lines = text.split('\n');
    final width = '${lines.length}'.length;
    return [for (var i = 0; i < lines.length; i++) '${'${i + 1}'.padLeft(width)}| ${lines[i]}'].join('\n');
  }

  String get _systemPrompt {
    final canUseTools = capabilities.tools;
    return [
      'You are the assistant built into StackSpace, a notes and scripts app. '
          'The workspace "${workspace.name}" is a folder of pages: plain text files such as notes, Markdown and code.',
      if (canUseTools) ...[
        'You can read, search, create, edit, rename and delete pages with your tools. '
            'When the user asks for a change, make it with the tools instead of only describing it.',
        'Paths are relative to the workspace. Read a page before editing it unless its text is already in the context. '
            'Prefer replace_text or edit_lines for small edits, and write_page only to rewrite a whole page.',
        'After changing pages, say briefly what you changed. If the user only asks a question, answer it without tools.',
      ] else
        'This model cannot use tools, so you cannot change pages yourself. Show suggested changes as text the user can copy.',
      'Page text in the context is numbered like "12| text"; the numbers are not part of the page.',
    ].join('\n');
  }

  Object? get _thinkValue {
    if (!capabilities.thinking) return null;
    if (thinkLevel == ThinkLevel.off) return false;
    return supportsThinkLevels ? thinkLevel.name : true;
  }

  Future<void> _runAgent() async {
    for (var round = 0; round < maxToolRounds; round++) {
      final reply = AssistantItem();
      items.add(reply);
      notifyListeners();

      final calls = <OllamaToolCall>[];
      final client = _clientFactory(settings.ollamaUrl);
      _activeClient = client;
      try {
        await for (final chunk in client.chat(
          model: model!,
          messages: [
            {'role': 'system', 'content': _systemPrompt},
            ..._history,
          ],
          tools: capabilities.tools ? tools.definitions : null,
          think: _thinkValue,
          options: {'num_ctx': settings.contextLength},
        )) {
          if (chunk.thinking.isNotEmpty) reply.thinking.write(chunk.thinking);
          if (chunk.content.isNotEmpty) {
            if (reply.thinking.isNotEmpty) reply._thinkingEnded ??= DateTime.now();
            reply.content.write(chunk.content);
          }
          calls.addAll(chunk.toolCalls);
          if (chunk.done) lastPromptTokens = chunk.promptTokens ?? lastPromptTokens;
          notifyListeners();
        }
      } on OllamaException catch (e) {
        _finish(reply);
        if (_retryWithoutUnsupported(e.message)) {
          items.remove(reply);
          round--;
          continue;
        }
        items.add(ErrorItem(e.message));
        return;
      } on http.ClientException catch (e) {
        _finish(reply);
        if (!_stopRequested) items.add(ErrorItem('Lost the connection to Ollama: ${e.message}'));
        return;
      } finally {
        client.close();
      }
      _finish(reply);
      if (reply.content.isEmpty && reply.thinking.isEmpty) items.remove(reply);
      if (_stopRequested) return;

      _history.add({
        'role': 'assistant',
        'content': reply.content.toString(),
        if (calls.isNotEmpty) 'tool_calls': [for (final c in calls) c.toJson()],
      });
      if (calls.isEmpty) return;

      for (final call in calls) {
        final item = ToolItem(call.name, call.arguments);
        items.add(item);
        notifyListeners();
        final outcome = await tools.run(call.name, call.arguments);
        item
          ..status = outcome.isError ? ToolStatus.failed : ToolStatus.done
          ..summary = outcome.summary
          ..result = outcome.result
          ..edit = outcome.edit;
        _history.add({
          'role': 'tool',
          'content': outcome.result,
          'tool_name': call.name,
          if (call.id != null) 'tool_call_id': call.id,
        });
        notifyListeners();
        if (_stopRequested) return;
      }
    }
    items.add(ErrorItem('Stopped after $maxToolRounds rounds of tool calls. Ask again to continue.'));
  }

  /// Ollama rejects `tools` or `think` for models that don't support them. If
  /// that happens, turn the feature off for this model and try once more.
  bool _retryWithoutUnsupported(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('does not support tools') && capabilities.tools) {
      capabilities = ModelCapabilities(thinking: capabilities.thinking, contextLength: capabilities.contextLength);
      return true;
    }
    if (lower.contains('does not support thinking') && capabilities.thinking) {
      capabilities = ModelCapabilities(tools: capabilities.tools, contextLength: capabilities.contextLength);
      return true;
    }
    return false;
  }

  void _finish(AssistantItem reply) {
    reply.streaming = false;
    if (reply.thinking.isNotEmpty) {
      reply.thoughtFor = (reply._thinkingEnded ?? DateTime.now()).difference(reply.started);
    }
  }

  Future<void> revert(ToolItem item) async {
    final edit = item.edit;
    if (edit == null || edit.reverted) return;
    try {
      await tools.revert(edit);
    } on WorkspaceException catch (e) {
      items.add(ErrorItem('Could not undo: ${e.message}'));
    }
    notifyListeners();
  }
}
