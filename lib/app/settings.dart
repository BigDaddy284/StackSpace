import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

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

/// Which palette the dark theme uses. Graphite is the default; Classic is the
/// original navy and purple.
enum DarkStyle {
  graphite('Graphite'),
  classic('Classic');

  const DarkStyle(this.label);
  final String label;
}

/// Copies the settings folder an older build used into the current one, once.
///
/// Builds before the StackSpace rename were named `stack_space` in the
/// executable's version info, and Windows keeps app data under that name
/// (`%APPDATA%\com.stackspace\stack_space`). The renamed build looks in
/// `...\StackSpace`, so without this the first launch after the update would
/// lose the saved workspace and settings. Files already in [current] are kept.
/// Returns true when settings were copied.
bool migrateOldSupportFolder(Directory old, Directory current) {
  try {
    final oldPrefs = File(p.join(old.path, 'shared_preferences.json'));
    final newPrefs = File(p.join(current.path, 'shared_preferences.json'));
    if (!oldPrefs.existsSync() || newPrefs.existsSync()) return false;
    current.createSync(recursive: true);
    for (final entity in old.listSync()) {
      if (entity is! File) continue;
      final target = File(p.join(current.path, p.basename(entity.path)));
      if (!target.existsSync()) entity.copySync(target.path);
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// User settings, saved with shared_preferences.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  /// Loads the saved settings. If the settings file cannot be read (a
  /// damaged file, a locked folder), the app starts with defaults in memory
  /// instead of never starting (Bug 5); [onProblem] gets the reason.
  static Future<AppSettings> load({void Function(String problem)? onProblem}) async {
    if (Platform.isWindows) {
      try {
        final current = await getApplicationSupportDirectory();
        final old = Directory(p.join(current.parent.path, 'stack_space'));
        if (migrateOldSupportFolder(old, current)) {
          onProblem?.call('Settings copied from ${old.path}');
        }
      } catch (_) {}
    }
    try {
      return AppSettings._(await SharedPreferences.getInstance());
    } catch (e) {
      onProblem?.call('Settings could not be read, using defaults for this run: $e');
      SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
      return AppSettings._(await SharedPreferences.getInstance());
    }
  }

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

  ThinkLevel get thinkLevel => ThinkLevel.values.asNameMap()[_prefs.getString('thinkLevel')] ?? ThinkLevel.medium;
  set thinkLevel(ThinkLevel value) => _set('thinkLevel', value.name);

  /// Sent to Ollama as `num_ctx`. Bigger lets the model see more of a page but uses more memory.
  int get contextLength => _prefs.getInt('contextLength') ?? defaultContextLength;
  set contextLength(int value) => _set('contextLength', value);

  bool get confirmDeletes => _prefs.getBool('confirmDeletes') ?? true;
  set confirmDeletes(bool value) => _set('confirmDeletes', value);

  bool get checkSpelling => _prefs.getBool('checkSpelling') ?? true;
  set checkSpelling(bool value) => _set('checkSpelling', value);

  /// Words added to the spelling dictionary.
  List<String> get spellingWords => _prefs.getStringList('spellingWords') ?? const [];
  set spellingWords(List<String> words) => _prefs.setStringList('spellingWords', words);

  /// System follows the Windows light/dark setting.
  ThemeMode get themeMode => themeModeListenable.value;
  set themeMode(ThemeMode value) {
    themeModeListenable.value = value;
    _set('themeMode', value.name);
  }

  /// Separate from [notifyListeners] so dragging the dock doesn't rebuild the whole app.
  late final themeModeListenable =
      ValueNotifier(ThemeMode.values.asNameMap()[_prefs.getString('themeMode')] ?? ThemeMode.system);

  /// The palette for the dark theme (and for Follow Windows when Windows is dark).
  DarkStyle get darkStyle => darkStyleListenable.value;
  set darkStyle(DarkStyle value) {
    darkStyleListenable.value = value;
    _set('darkStyle', value.name);
  }

  late final darkStyleListenable =
      ValueNotifier(DarkStyle.values.asNameMap()[_prefs.getString('darkStyle')] ?? DarkStyle.graphite);

  double get dockHeight => _prefs.getDouble('dockHeight') ?? 360;
  set dockHeight(double value) => _set('dockHeight', value);

  static const defaultSidebarWidth = 260.0;

  /// Width of the pages panel, set by dragging its right edge.
  double get sidebarWidth => _prefs.getDouble('sidebarWidth') ?? defaultSidebarWidth;
  set sidebarWidth(double value) => _set('sidebarWidth', value);

  /// Folders folded in the pages panel, per workspace (Bug 3). A folder on
  /// disk has no identity but its path, so the paths are what is kept; the
  /// panel moves them on a rename and drops them on a delete.
  Set<String> collapsedFolders(String workspaceRoot) =>
      (_prefs.getStringList('collapsedFolders:$workspaceRoot') ?? const []).toSet();

  Future<void> setCollapsedFolders(String workspaceRoot, Set<String> folders) =>
      _prefs.setStringList('collapsedFolders:$workspaceRoot', folders.toList()..sort());

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
