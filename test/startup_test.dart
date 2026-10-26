import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:stack_space/ai/chat_controller.dart';
import 'package:stack_space/ai/ollama_client.dart';
import 'package:stack_space/app/app.dart';
import 'package:stack_space/app/settings.dart';
import 'package:stack_space/app/startup_log.dart';
import 'package:stack_space/ui/home_page.dart';
import 'support/fake_ollama.dart';
import 'support/temp.dart';

/// A preferences store that fails to load, like a damaged settings file.
class _BrokenStore extends SharedPreferencesStorePlatform {
  @override
  Future<bool> clear() async => true;
  @override
  Future<Map<String, Object>> getAll() => throw const FormatException('Unexpected end of input');
  @override
  Future<bool> remove(String key) async => true;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async => true;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

void main() {
  // Bug 5: a start that cannot read its settings or its workspace must still
  // show a themed window with a message, never stall before the first frame.

  test('settings fall back to defaults when the settings file cannot be read', () async {
    final problems = <String>[];
    SharedPreferencesStorePlatform.instance = _BrokenStore();
    final settings = await AppSettings.load(onProblem: problems.add);
    expect(problems.single, contains('Settings could not be read'));
    expect(problems.single, contains('Unexpected end of input'));
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.ollamaUrl, AppSettings.defaultOllamaUrl);
    settings.themeMode = ThemeMode.dark;
    expect(settings.themeMode, ThemeMode.dark, reason: 'settings still work for this run');
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the start-up screen draws the themed window colour and a message', (tester) async {
    await tester.pumpWidget(const StartupScreen(message: 'Loading settings…'));
    expect(find.text('Loading settings…'), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color.fromARGB(255, 10, 13, 26));
  });

  testWidgets('a workspace that cannot be opened shows a message with Try again instead of a spinner', (tester) async {
    // Real file work goes through runAsync in a widget test.
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('startup_')))!;
    addTearDown(() => deleteTemp(dir));
    // A file where the workspace folder should be: creating the folder fails.
    final blocked = File('${dir.path}/ws');
    await tester.runAsync(() => blocked.writeAsString('not a folder'));
    SharedPreferences.setMockInitialValues({'workspacePath': blocked.path});
    final settings = await tester.runAsync(AppSettings.load);
    final fake = FakeOllama();
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: HomePage(
        settings: settings!,
        chatFactory: (s, tools) => ChatController(
          settings: s,
          tools: tools,
          clientFactory: (url) => OllamaClient(baseUrl: url, httpClient: fake.client()),
        ),
      ),
    ));
    expect(find.textContaining('Opening '), findsOneWidget, reason: 'the loading state names the folder');
    await settle(tester);
    expect(find.text('Workspace not available'), findsOneWidget);
    expect(find.textContaining(blocked.path), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Fix the folder and retry: the app opens.
    await tester.runAsync(() async {
      await blocked.delete();
      await Directory(blocked.path).create();
      await File('${blocked.path}/hello.md').writeAsString('# Hello\n');
    });
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('Workspace not available'), findsNothing);
    expect(find.text('hello.md'), findsWidgets);
  });

  test('the start-up log writes timed lines and keeps the file bounded', () async {
    // The log file needs the platform channel; here only the in-memory part
    // is exercised, plus the trimming through a file of our own.
    StartupLog.log('something happened');
    final dir = await Directory.systemTemp.createTemp('startuplog_');
    addTearDown(() => deleteTemp(dir));
    final file = File('${dir.path}/startup.log');
    await file.writeAsString(List.generate(500, (i) => 'line $i').join('\n'));
    // ignore: invalid_use_of_visible_for_testing_member
    StartupLog.trimForTest(file);
    final lines = await file.readAsLines();
    expect(lines.length, StartupLog.keepLines);
    expect(lines.first, 'line 100');
    expect(lines.last, 'line 499');
  });
}
