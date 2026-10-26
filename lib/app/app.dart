import 'package:flutter/material.dart';

import '../platform/title_bar.dart';
import '../ui/home_page.dart';
import 'settings.dart';
import 'theme.dart';

class StackSpaceApp extends StatelessWidget {
  const StackSpaceApp({super.key, required this.settings});

  final AppSettings settings;

  static final _light = buildTheme(StackPalette.lightPalette);
  static final _dark = buildTheme(StackPalette.darkPalette);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings.themeModeListenable,
      builder: (context, child) => MaterialApp(
        title: 'StackSpace',
        debugShowCheckedModeBanner: false,
        theme: _light,
        darkTheme: _dark,
        themeMode: settings.themeMode,
        builder: (context, child) {
          TitleBar.sync(StackColors.of(context));
          return child!;
        },
        home: child,
      ),
      child: HomePage(settings: settings),
    );
  }
}

/// What the window shows before the settings are loaded: the dark palette's
/// window colour and one line of text, so a slow or stuck start is visible
/// as such rather than as an unpainted window.
class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final p = StackPalette.darkPalette;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: StackSpaceApp._dark,
      home: Scaffold(
        backgroundColor: p.window,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: p.accentA)),
              const SizedBox(height: 14),
              Text(message, style: TextStyle(color: p.subText, fontSize: StackType.menu)),
            ],
          ),
        ),
      ),
    );
  }
}
