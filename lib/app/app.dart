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
