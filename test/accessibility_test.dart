import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stack_space/ai/chat_controller.dart';
import 'package:stack_space/ai/ollama_client.dart';
import 'package:stack_space/app/settings.dart';
import 'package:stack_space/app/theme.dart';
import 'package:stack_space/ui/home_page.dart';

import 'support/fake_ollama.dart';
import 'support/temp.dart';

/// WCAG 2.2 target size (minimum), AA: 24 by 24 CSS pixels.
const wcagTargetSize = MinimumTapTargetGuideline(
  size: Size(24, 24),
  link: 'https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum',
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('a11y_test_');
    await File('${dir.path}/notes.md').writeAsString('# Notes\nSome text\n');
    SharedPreferences.setMockInitialValues({'workspacePath': dir.path});
  });

  tearDown(() => deleteTemp(dir));

  Future<void> pumpApp(WidgetTester tester, StackPalette palette, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final fake = FakeOllama()..queueText('Here is a summary of your notes.', thinking: 'Reading the page.');
    final settings = await tester.runAsync(AppSettings.load);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(palette),
      home: HomePage(
        settings: settings!,
        chatFactory: (s, tools) => ChatController(
          settings: s,
          tools: tools,
          clientFactory: (url) => OllamaClient(baseUrl: url, httpClient: fake.client()),
        ),
      ),
    ));
    await settle(tester);
  }

  Future<void> openChatAndSend(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Open the assistant (Ctrl+J)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('composer')), 'summarise');
    await tester.pump();
    await tester.tap(find.byTooltip('Send (Enter)'));
    await settle(tester);
  }

  for (final palette in [StackPalette.lightPalette, StackPalette.darkPalette]) {
    final mode = palette.brightness.name;

    testWidgets('$mode: closed dock meets contrast, label and target guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, palette);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(wcagTargetSize));
      handle.dispose();
    });

    testWidgets('$mode: open chat with a reply meets the guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, palette);
      await openChatAndSend(tester);
      expect(find.textContaining('Here is a summary'), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(wcagTargetSize));
      handle.dispose();
    });
  }

  testWidgets('works at 150% text size without overflow', (tester) async {
    await pumpApp(tester, StackPalette.darkPalette, textScale: 1.5);
    await openChatAndSend(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme button cycles Windows, light and dark', (tester) async {
    await pumpApp(tester, StackPalette.lightPalette);
    expect(find.byTooltip('Theme: follow Windows. Click for light'), findsOneWidget);
    await tester.tap(find.byTooltip('Theme: follow Windows. Click for light'));
    await tester.pump();
    await tester.tap(find.byTooltip('Theme: light. Click for dark'));
    await tester.pump();
    expect(find.byTooltip('Theme: dark. Click to follow Windows'), findsOneWidget);
  });
}
