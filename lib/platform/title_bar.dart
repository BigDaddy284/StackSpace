import 'dart:io';

import 'package:flutter/services.dart';

import '../app/theme.dart';

/// Colours the Windows title bar like Stills & Reels: caption in Bar, title in
/// Text, and a matching border. Does nothing on other platforms.
class TitleBar {
  static const _channel = MethodChannel('stackspace/window');
  static StackPalette? _last;

  static void sync(StackPalette p) {
    if (!Platform.isWindows || identical(p, _last)) return;
    _last = p;
    _channel.invokeMethod<void>('setTitleBarColors', {
      'dark': p.dark ? 1 : 0,
      'caption': p.bar.toARGB32(),
      'text': p.text.toARGB32(),
      'border': (p.dark ? const Color.fromARGB(255, 40, 48, 84) : p.barBorder).toARGB32(),
    }).catchError((Object _) {});
  }
}
