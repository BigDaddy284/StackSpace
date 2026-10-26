import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class OllamaException implements Exception {
  OllamaException(this.message);
  final String message;
  @override
  String toString() => message;
}

class OllamaModel {
  const OllamaModel({required this.name, this.parameterSize, this.family, this.sizeBytes = 0});

  factory OllamaModel.fromJson(Map<String, dynamic> json) {
    final details = (json['details'] as Map?)?.cast<String, dynamic>() ?? const {};
    return OllamaModel(
      name: (json['model'] ?? json['name']) as String,
      parameterSize: details['parameter_size'] as String?,
      family: details['family'] as String?,
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  final String name;
  final String? parameterSize;
  final String? family;
  final int sizeBytes;
}

/// What `/api/show` says a model can do.
class ModelCapabilities {
  const ModelCapabilities({this.tools = false, this.thinking = false, this.contextLength});

  factory ModelCapabilities.fromShow(Map<String, dynamic> json) {
    final caps = (json['capabilities'] as List?)?.cast<String>() ?? const [];
    int? contextLength;
    final info = (json['model_info'] as Map?)?.cast<String, dynamic>() ?? const {};
    for (final entry in info.entries) {
      if (entry.key.endsWith('.context_length') && entry.value is num) {
        contextLength = (entry.value as num).toInt();
      }
    }
    return ModelCapabilities(
      tools: caps.contains('tools'),
      thinking: caps.contains('thinking'),
      contextLength: contextLength,
    );
  }

  final bool tools;
  final bool thinking;
  final int? contextLength;
}

class OllamaToolCall {
  const OllamaToolCall({required this.name, required this.arguments, this.id});

  factory OllamaToolCall.fromJson(Map<String, dynamic> json) {
    final fn = (json['function'] as Map).cast<String, dynamic>();
    var args = fn['arguments'];
    // Ollama sends an object, but some models emit a JSON string instead.
    if (args is String) {
      try {
        args = jsonDecode(args);
      } on FormatException {
        args = <String, dynamic>{};
      }
    }
    return OllamaToolCall(
      id: json['id'] as String?,
      name: fn['name'] as String,
      arguments: (args as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
    );
  }

  final String? id;
  final String name;
  final Map<String, dynamic> arguments;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'function': {'name': name, 'arguments': arguments},
      };
}

/// One line of a streamed `/api/chat` response.
class ChatChunk {
  const ChatChunk({
    this.content = '',
    this.thinking = '',
    this.toolCalls = const [],
    this.done = false,
    this.doneReason,
    this.promptTokens,
    this.outputTokens,
  });

  factory ChatChunk.fromJson(Map<String, dynamic> json) {
    final message = (json['message'] as Map?)?.cast<String, dynamic>() ?? const {};
    final calls = (message['tool_calls'] as List?) ?? const [];
    return ChatChunk(
      content: (message['content'] as String?) ?? '',
      thinking: (message['thinking'] as String?) ?? '',
      toolCalls: [for (final c in calls) OllamaToolCall.fromJson((c as Map).cast<String, dynamic>())],
      done: json['done'] == true,
      doneReason: json['done_reason'] as String?,
      promptTokens: (json['prompt_eval_count'] as num?)?.toInt(),
      outputTokens: (json['eval_count'] as num?)?.toInt(),
    );
  }

  final String content;
  final String thinking;
  final List<OllamaToolCall> toolCalls;
  final bool done;
  final String? doneReason;
  final int? promptTokens;
  final int? outputTokens;
}

/// Minimal client for the parts of the Ollama REST API the assistant uses.
/// See https://github.com/ollama/ollama/blob/main/docs/api.md
class OllamaClient {
  OllamaClient({required String baseUrl, http.Client? httpClient})
      : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<String> version() async {
    final json = await _getJson('/api/version');
    return json['version'] as String? ?? 'unknown';
  }

  Future<List<OllamaModel>> listModels() async {
    final json = await _getJson('/api/tags');
    final models = (json['models'] as List?) ?? const [];
    return [for (final m in models) OllamaModel.fromJson((m as Map).cast<String, dynamic>())]
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<ModelCapabilities> show(String model) async {
    final response = await _send(() => _http.post(
          _uri('/api/show'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'model': model}),
        ));
    return ModelCapabilities.fromShow(_decode(response));
  }

  /// Streams a chat completion. [think] is `false`, `true`, or one of
  /// "low" / "medium" / "high" for models that accept a level.
  Stream<ChatChunk> chat({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Object? think,
    Map<String, dynamic>? options,
  }) async* {
    final request = http.Request('POST', _uri('/api/chat'))
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode({
        'model': model,
        'messages': messages,
        'stream': true,
        if (tools != null && tools.isNotEmpty) 'tools': tools,
        if (think != null) 'think': think,
        if (options != null && options.isNotEmpty) 'options': options,
      });

    final http.StreamedResponse response;
    try {
      response = await _http.send(request);
    } on http.ClientException catch (e) {
      throw OllamaException(_connectionMessage(e));
    }
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw OllamaException(_errorFrom(body, response.statusCode));
    }

    final lines = response.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final json = jsonDecode(line) as Map<String, dynamic>;
      if (json['error'] != null) throw OllamaException(json['error'].toString());
      yield ChatChunk.fromJson(json);
    }
  }

  void close() => _http.close();

  Future<Map<String, dynamic>> _getJson(String path) async {
    final response = await _send(() => _http.get(_uri(path)));
    return _decode(response);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw OllamaException('Ollama at $baseUrl did not answer within 10 seconds.');
    } on http.ClientException catch (e) {
      throw OllamaException(_connectionMessage(e));
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode != 200) {
      throw OllamaException(_errorFrom(response.body, response.statusCode));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String _connectionMessage(http.ClientException e) => "Can't reach Ollama at $baseUrl. Is it running? (${e.message})";

  static String _errorFrom(String body, int status) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json['error'] != null) return json['error'].toString();
    } on FormatException {
      // Not JSON; fall through to the status code.
    }
    return 'Ollama returned HTTP $status.';
  }
}
