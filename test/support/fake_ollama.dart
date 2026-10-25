import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Pretends to be an Ollama server. Each queued chat reply is a list of
/// NDJSON objects streamed back for one /api/chat request.
class FakeOllama {
  FakeOllama(
      {this.models = const ['qwen3:8b', 'llama3.2:3b'], this.capabilities = const ['completion', 'tools', 'thinking']});

  final List<String> models;
  List<String> capabilities;
  final List<List<Map<String, dynamic>>> chatReplies = [];
  final List<Map<String, dynamic>> chatRequests = [];
  String? chatError;

  void queueText(String text, {String thinking = ''}) => chatReplies.add([
        if (thinking.isNotEmpty) _msg(thinking: thinking),
        for (final word in text.split(' ')) _msg(content: '$word '),
        {
          'done': true,
          'done_reason': 'stop',
          'prompt_eval_count': 321,
          'eval_count': 12,
          'message': {'role': 'assistant', 'content': ''}
        },
      ]);

  void queueToolCall(String name, Map<String, dynamic> args) => chatReplies.add([
        {
          'message': {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'function': {'name': name, 'arguments': args}
              },
            ],
          },
          'done': false,
        },
        {
          'done': true,
          'done_reason': 'stop',
          'message': {'role': 'assistant', 'content': ''}
        },
      ]);

  static Map<String, dynamic> _msg({String content = '', String thinking = ''}) => {
        'message': {'role': 'assistant', 'content': content, if (thinking.isNotEmpty) 'thinking': thinking},
        'done': false,
      };

  http.Client client() => MockClient.streaming((request, bodyStream) async {
        final body = await bodyStream.bytesToString();
        final path = request.url.path;
        if (path == '/api/version') return _json({'version': '0.13.0'});
        if (path == '/api/tags') {
          return _json({
            'models': [
              for (final m in models)
                {
                  'name': m,
                  'model': m,
                  'size': 1000,
                  'details': {'family': 'qwen3', 'parameter_size': '8B'}
                },
            ],
          });
        }
        if (path == '/api/show') {
          return _json({
            'capabilities': capabilities,
            'model_info': {'qwen3.context_length': 40960},
          });
        }
        if (path == '/api/chat') {
          final json = jsonDecode(body) as Map<String, dynamic>;
          chatRequests.add(json);
          if (chatError != null) {
            final error = chatError!;
            chatError = null;
            return _json({'error': error}, status: 400);
          }
          final reply = chatReplies.isEmpty ? <Map<String, dynamic>>[] : chatReplies.removeAt(0);
          final lines = reply.map((m) => utf8.encode('${jsonEncode(m)}\n'));
          return http.StreamedResponse(Stream.fromIterable(lines), 200);
        }
        return _json({'error': 'not found'}, status: 404);
      });

  static http.StreamedResponse _json(Object body, {int status = 200}) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status);
}
