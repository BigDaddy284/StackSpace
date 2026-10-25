import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stack_space/ai/ollama_client.dart';

import 'support/fake_ollama.dart';

void main() {
  test('lists models and reads capabilities', () async {
    final fake = FakeOllama();
    final client = OllamaClient(baseUrl: 'http://127.0.0.1:11434/', httpClient: fake.client());
    expect(await client.version(), '0.13.0');
    final models = await client.listModels();
    expect(models.map((m) => m.name), ['llama3.2:3b', 'qwen3:8b']);
    expect(models.first.parameterSize, '8B');
    final caps = await client.show('qwen3:8b');
    expect(caps.tools, isTrue);
    expect(caps.thinking, isTrue);
    expect(caps.contextLength, 40960);
  });

  test('streams thinking, content and tool calls', () async {
    final fake = FakeOllama()
      ..queueText('Hello there', thinking: 'Let me think.')
      ..queueToolCall('read_page', {'path': 'a.md'});
    final client = OllamaClient(baseUrl: 'http://x', httpClient: fake.client());

    final chunks = await client.chat(model: 'qwen3:8b', messages: [], think: 'high').toList();
    expect(chunks.map((c) => c.thinking).join(), 'Let me think.');
    expect(chunks.map((c) => c.content).join(), 'Hello there ');
    expect(chunks.last.done, isTrue);
    expect(chunks.last.promptTokens, 321);
    expect(fake.chatRequests.single['think'], 'high');
    expect(fake.chatRequests.single['stream'], isTrue);

    final calls = (await client.chat(model: 'qwen3:8b', messages: []).toList()).expand((c) => c.toolCalls).toList();
    expect(calls.single.name, 'read_page');
    expect(calls.single.arguments, {'path': 'a.md'});
  });

  test('accepts tool arguments sent as a JSON string', () {
    final call = OllamaToolCall.fromJson({
      'function': {'name': 'read_page', 'arguments': '{"path":"x.md"}'},
    });
    expect(call.arguments, {'path': 'x.md'});
  });

  test('turns server errors and connection failures into readable messages', () async {
    final fake = FakeOllama()..chatError = 'model "nope" not found, try pulling it first';
    final client = OllamaClient(baseUrl: 'http://x', httpClient: fake.client());
    await expectLater(client.chat(model: 'nope', messages: []).toList(),
        throwsA(isA<OllamaException>().having((e) => e.message, 'message', contains('try pulling'))));

    final offline = OllamaClient(
      baseUrl: 'http://127.0.0.1:11434',
      httpClient: MockClient((_) => throw http.ClientException('Connection refused')),
    );
    await expectLater(offline.listModels(),
        throwsA(isA<OllamaException>().having((e) => e.message, 'message', contains('Is it running?'))));
  });
}
