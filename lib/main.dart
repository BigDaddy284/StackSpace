import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/settings.dart';
import 'app/startup_log.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    StartupLog.captureErrors();
    unawaited(StartupLog.open().then((_) => StartupLog.log('log open')));
    StartupLog.log('binding ready');
    // The window is shown on the first frame, so draw one before any loading:
    // a launch that stalls while reading settings or the workspace still
    // shows a themed window and a message, never a blank one (Bug 5).
    runApp(const StartupScreen(message: 'Loading settings…'));
    WidgetsBinding.instance.addPostFrameCallback((_) => StartupLog.log('first frame'));
    final settings = await AppSettings.load(onProblem: StartupLog.log);
    StartupLog.log('settings loaded: theme ${settings.themeMode.name}, workspace ${settings.workspacePath}');
    runApp(StackSpaceApp(settings: settings));
  }, (error, stack) {
    StartupLog.log('Uncaught error: $error\n$stack');
  });
}
