import 'package:flutter/material.dart';

import 'widgets/controls.dart';

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(message)),
      actions: [
        SsButton(label: 'Cancel', onPressed: () => Navigator.pop(context, false)),
        SsButton(
          label: confirmLabel,
          icon: destructive ? Icons.delete_outline : null,
          primary: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> promptDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String confirmLabel = 'Create',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PromptDialog(title: title, label: label, initial: initial, confirmLabel: confirmLabel),
  );
}

/// Owns the field's controller for as long as the dialog is on screen,
/// including its closing animation (disposing it on pop broke that frame).
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, required this.label, required this.initial, required this.confirmLabel});

  final String title;
  final String label;
  final String initial;
  final String confirmLabel;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    controller = TextEditingController(text: initial);
    final dot = initial.lastIndexOf('.');
    final slash = initial.lastIndexOf('/');
    controller.selection = TextSelection(baseOffset: slash + 1, extentOffset: dot > slash ? dot : initial.length);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
      ),
      actions: [
        SsButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        SsButton(label: widget.confirmLabel, primary: true, onPressed: () => Navigator.pop(context, controller.text)),
      ],
    );
  }
}

void showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
