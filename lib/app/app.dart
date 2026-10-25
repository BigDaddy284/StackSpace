import 'package:flutter/material.dart';

import '../ui/home_page.dart';
import 'settings.dart';

class StackSpaceApp extends StatelessWidget {
  const StackSpaceApp({super.key, required this.settings});

  final AppSettings settings;

  static ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF5B5BD6), brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StackSpace',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: HomePage(settings: settings),
    );
  }
}
