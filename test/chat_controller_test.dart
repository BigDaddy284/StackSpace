import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stack_space/ai/chat_controller.dart';
import 'package:stack_space/ai/ollama_client.dart';
import 'package:stack_space/ai/workspace_tools.dart';
import 'package:stack_space/app/settings.dart';
import 'package:stack_space/workspace/workspace.dart';

import 'support/fake_ollama.dart';

void main() {
  late Directory dir;
  late Workspace ws;
  late FakeOllama fake;
  late ChatController chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('chat_test_');
    ws = Workspace(dir.path);
    await ws.init();
    await ws.write('todo.md', '# Todo\n- buy milk\n- call mom');
    fake = FakeOllama();
    chat = ChatController(
      settings: await AppSettings.load(),
      tools: WorkspaceTools(ws),
      clientFactory: (url) => OllamaClient(baseUrl: url, httpClient: fake.client()),
    );
  });

  tearDown(() async {
    ws.dispose();
    await dir.delete(recursive: true);
  });

  test('connect picks the first model and loads its capabilities', () async {
    await chat.connect();
    expect(chat.status, OllamaStatus.connected);
    expect(chat.model, 'llama3.2:3b');
    expect(chat.capabilities.tools, isTrue);
  });

  test('sends the open page and selection as context', () async {
    await chat.connect();
    fake.queueText('Sure.');
    await chat.send('make this shorter',
        context: const ChatContext(
          pagePath: 'todo.md',
          pageText: '# Todo\n- buy milk\n- call mom',
          selection: '- buy milk',
          selectionStartLine: 2,
          selectionEndLine: 2,
        ));
    final messages = fake.chatRequests.single['messages'] as List;
    expect(messages.first['role'], 'system');
    final user = messages.last['content'] as String;
    expect(user, contains('<page path="todo.md">'));
    expect(user, contains('2| - buy milk'));
    expect(user, contains('<selection>\n- buy milk\n</selection>'));
    expect(user, endsWith('make this shorter'));
    expect((chat.items.first as UserItem).contextLabels, ['todo.md', 'Selection: line 2']);
  });

  test('runs tool calls until the model answers, then the edit can be undone', () async {
    await chat.connect();
    fake
      ..queueToolCall('edit_lines', {'path': 'todo.md', 'start_line': 3, 'end_line': 3, 'new_text': '- call dad'})
      ..queueText('Changed mom to dad.');
    await chat.send('swap mom for dad');

    expect(await ws.read('todo.md'), '# Todo\n- buy milk\n- call dad');
    expect(fake.chatRequests, hasLength(2));
    final second = fake.chatRequests[1]['messages'] as List;
    expect(second[second.length - 2]['tool_calls'], isNotEmpty);
    expect(second.last['role'], 'tool');
    expect(second.last['tool_name'], 'edit_lines');

    final tool = chat.items.whereType<ToolItem>().single;
    expect(tool.status, ToolStatus.done);
    expect(tool.summary, 'Edited todo.md (line 3)');
    expect((chat.items.last as AssistantItem).content.toString().trim(), 'Changed mom to dad.');

    await chat.revert(tool);
    expect(await ws.read('todo.md'), '# Todo\n- buy milk\n- call mom');
    expect(tool.edit!.reverted, isTrue);
  });

  test('maps the thinking level to what Ollama expects', () async {
    await chat.connect();
    chat.setThinkLevel(ThinkLevel.high);
    fake.queueText('a');
    await chat.send('hi');
    expect(fake.chatRequests.last['think'], true);

    chat.setThinkLevel(ThinkLevel.off);
    fake.queueText('b');
    await chat.send('hi');
    expect(fake.chatRequests.last['think'], false);

    // gpt-oss takes a level instead of true/false.
    chat.settings.model = 'gpt-oss:20b';
    chat.setThinkLevel(ThinkLevel.low);
    fake.queueText('c');
    await chat.send('hi');
    expect(fake.chatRequests.last['think'], 'low');

    fake.capabilities = ['completion', 'tools'];
    await chat.selectModel('llama3.2:3b');
    fake.queueText('d');
    await chat.send('hi');
    expect(fake.chatRequests.last.containsKey('think'), isFalse);
  });

  test('retries without tools when the model rejects them', () async {
    await chat.connect();
    fake
      ..chatError = 'registry.ollama.ai/library/gemma:2b does not support tools'
      ..queueText('Plain answer.');
    await chat.send('hello');
    expect(fake.chatRequests, hasLength(2));
    expect(fake.chatRequests.last.containsKey('tools'), isFalse);
    expect(chat.items.whereType<ErrorItem>(), isEmpty);
  });

  test('reports offline when Ollama is not running', () async {
    final offline = ChatController(
      settings: chat.settings,
      tools: chat.tools,
      clientFactory: (url) => OllamaClient(
        baseUrl: url,
        httpClient: MockClient((_) => throw http.ClientException('Connection refused')),
      ),
    );
    await offline.connect();
    expect(offline.status, OllamaStatus.offline);
    expect(offline.statusMessage, contains('Is it running?'));
  });
}
