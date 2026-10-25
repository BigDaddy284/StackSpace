import 'package:flutter/material.dart';

import '../app/settings.dart';
import 'widgets/controls.dart';

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

  Widget _field(String section, TextEditingController controller, String hint, {bool number = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(section),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: number ? TextInputType.number : null,
            decoration: InputDecoration(hintText: section),
          ),
          const SizedBox(height: 4),
          HintText(hint),
          const SizedBox(height: 10),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Theme'),
              const SizedBox(height: 6),
              Row(children: [
                for (final (mode, icon, label) in [
                  (ThemeMode.system, Icons.brightness_auto_outlined, 'Windows'),
                  (ThemeMode.light, Icons.light_mode_outlined, 'Light'),
                  (ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
                ]) ...[
                  if (mode != ThemeMode.system) const SizedBox(width: 8),
                  Expanded(
                    child: SsButton(
                      icon: icon,
                      label: label,
                      checked: _themeMode == mode,
                      onPressed: () => setState(() => _themeMode = mode),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 14),
              _field('Workspace folder', _workspace, 'Every text file in this folder is a page.'),
              _field('Ollama address', _url, 'Default ${AppSettings.defaultOllamaUrl}'),
              _field('Context length (tokens)', _context,
                  'How much text the model can see at once. Larger uses more memory.',
                  number: true),
              const SectionLabel('Assistant'),
              SsToggle(
                label: 'Ask before the assistant deletes pages',
                value: _confirmDeletes,
                onChanged: (v) => setState(() => _confirmDeletes = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        SsButton(label: 'Cancel', onPressed: () => Navigator.pop(context, false)),
        SsButton(label: 'Save', primary: true, onPressed: _save),
      ],
    );
  }
}
