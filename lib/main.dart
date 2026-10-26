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
    WidgetsBinding.instance.addPostFrameCallback((_) => StartupLog.log('first frame, ${_viewSize()}'));
    // Window moves during start-up (PowerToys FancyZones snapping the window
    // into its zone) are logged, to tell a blank window that never got its
    // new size from one that got it but did not draw.
    final sizeLogger = _ViewSizeLogger();
    WidgetsBinding.instance.addObserver(sizeLogger);
    Timer(const Duration(seconds: 10), () => WidgetsBinding.instance.removeObserver(sizeLogger));
    final settings = await AppSettings.load(onProblem: StartupLog.log);
    StartupLog.log('settings loaded: theme ${settings.themeMode.name}, workspace ${settings.workspacePath}');
    runApp(StackSpaceApp(settings: settings));
  }, (error, stack) {
    StartupLog.log('Uncaught error: $error\n$stack');
  });
}

String _viewSize() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return 'no view';
  final size = views.first.physicalSize;
  return 'view ${size.width.round()}x${size.height.round()}';
}

class _ViewSizeLogger with WidgetsBindingObserver {
  @override
  void didChangeMetrics() => StartupLog.log('window resized: ${_viewSize()}');
}
