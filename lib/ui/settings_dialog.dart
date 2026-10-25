import 'package:flutter/material.dart';

import '../app/settings.dart';

/// Returns true if anything changed.
Future<bool> showSettingsDialog(BuildContext context, AppSettings settings) async {
  final result = await showDialog<bool>(context: context, builder: (_) => _SettingsDialog(settings: settings));
  return result ?? false;
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.settings});
  final AppSettings settings;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final _url = TextEditingController(text: widget.settings.ollamaUrl);
  late final _context = TextEditingController(text: '${widget.settings.contextLength}');
  late final _workspace = TextEditingController(text: widget.settings.workspacePath);
  late bool _confirmDeletes = widget.settings.confirmDeletes;
  late ThemeMode _themeMode = widget.settings.themeMode;

  @override
  void dispose() {
    _url.dispose();
    _context.dispose();
    _workspace.dispose();
    super.dispose();
  }

  void _save() {
    final s = widget.settings;
    s.ollamaUrl = _url.text;
    s.contextLength = int.tryParse(_context.text.trim())?.clamp(2048, 262144) ?? AppSettings.defaultContextLength;
    if (_workspace.text.trim().isNotEmpty) s.workspacePath = _workspace.text.trim();
    s.confirmDeletes = _confirmDeletes;
    s.themeMode = _themeMode;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appearance', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Windows')),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
              ],
              selected: {_themeMode},
              onSelectionChanged: (v) => setState(() => _themeMode = v.first),
            ),
            const SizedBox(height: 16),
            TextField(controller: _workspace, decoration: const InputDecoration(labelText: 'Workspace folder')),
            const SizedBox(height: 4),
            Text('Every text file in this folder is a page.', style: muted),
            const SizedBox(height: 16),
            TextField(controller: _url, decoration: const InputDecoration(labelText: 'Ollama address')),
            const SizedBox(height: 4),
            Text('Default ${AppSettings.defaultOllamaUrl}', style: muted),
            const SizedBox(height: 16),
            TextField(
              controller: _context,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Context length (tokens)'),
            ),
            const SizedBox(height: 4),
            Text('How much text the model can see at once. Larger uses more memory.', style: muted),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ask before the assistant deletes pages'),
              value: _confirmDeletes,
              onChanged: (v) => setState(() => _confirmDeletes = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
