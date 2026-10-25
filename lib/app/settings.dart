import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// How hard a thinking model should think. Ollama takes `think: true/false`
/// for most thinking models, and "low" / "medium" / "high" for models such as gpt-oss.
enum ThinkLevel {
  off('Off'),
  low('Low'),
  medium('Medium'),
  high('High');

  const ThinkLevel(this.label);
  final String label;
}

/// User settings, saved with shared_preferences.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static Future<AppSettings> load() async => AppSettings._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const defaultOllamaUrl = 'http://127.0.0.1:11434';
  static const defaultContextLength = 8192;

  /// Default workspace: Documents\StackSpace on Windows, ~/StackSpace elsewhere.
  /// The STACKSPACE_WORKSPACE environment variable overrides it.
  static String get defaultWorkspacePath {
    final override = Platform.environment['STACKSPACE_WORKSPACE'];
    if (override != null && override.isNotEmpty) return override;
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.current.path;
    return Platform.isWindows ? p.join(home, 'Documents', 'StackSpace') : p.join(home, 'StackSpace');
  }

  String get workspacePath => _prefs.getString('workspacePath') ?? defaultWorkspacePath;
  set workspacePath(String value) => _set('workspacePath', value);

  String get ollamaUrl => _prefs.getString('ollamaUrl') ?? defaultOllamaUrl;
  set ollamaUrl(String value) => _set('ollamaUrl', value.trim().isEmpty ? defaultOllamaUrl : value.trim());

  String? get model => _prefs.getString('model');
  set model(String? value) => _set('model', value);

  ThinkLevel get thinkLevel =>
      ThinkLevel.values.asNameMap()[_prefs.getString('thinkLevel')] ?? ThinkLevel.medium;
  set thinkLevel(ThinkLevel value) => _set('thinkLevel', value.name);

  /// Sent to Ollama as `num_ctx`. Bigger lets the model see more of a page but uses more memory.
  int get contextLength => _prefs.getInt('contextLength') ?? defaultContextLength;
  set contextLength(int value) => _set('contextLength', value);

  bool get confirmDeletes => _prefs.getBool('confirmDeletes') ?? true;
  set confirmDeletes(bool value) => _set('confirmDeletes', value);

  /// System follows the Windows light/dark setting.
  ThemeMode get themeMode => themeModeListenable.value;
  set themeMode(ThemeMode value) {
    themeModeListenable.value = value;
    _set('themeMode', value.name);
  }

  /// Separate from [notifyListeners] so dragging the dock doesn't rebuild the whole app.
  late final themeModeListenable =
      ValueNotifier(ThemeMode.values.asNameMap()[_prefs.getString('themeMode')] ?? ThemeMode.system);

  double get dockHeight => _prefs.getDouble('dockHeight') ?? 360;
  set dockHeight(double value) => _set('dockHeight', value);

  void _set(String key, Object? value) {
    switch (value) {
      case null:
        _prefs.remove(key);
      case String v:
        _prefs.setString(key, v);
      case bool v:
        _prefs.setBool(key, v);
      case int v:
        _prefs.setInt(key, v);
      case double v:
        _prefs.setDouble(key, v);
    }
    notifyListeners();
  }
}
