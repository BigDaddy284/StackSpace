import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../editor/page_editor_controller.dart';
import '../../workspace/workspace.dart';

/// Picks a file with the system dialog; swapped in tests.
Future<String?> Function(BuildContext context) pickImageFile = (context) async {
  final file = await openFile(acceptedTypeGroups: const [
    XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg']),
  ]);
  return file?.path;
};

/// Asks for an image: a file from the computer (copied next to the page) or
/// a path or link typed in. Null when cancelled.
Future<String?> showImageDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      final palette = StackColors.of(context);
      return AlertDialog(
        title: const Text('Insert image'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final path = await pickImageFile(context);
                  if (path != null && path.isNotEmpty && context.mounted) Navigator.of(context).pop(path);
                },
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Choose a file…'),
              ),
              const SizedBox(height: 6),
              Text('A file from outside the workspace is copied into an images folder next to the page.',
                  style: TextStyle(fontSize: StackType.hint, color: palette.subText)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Or a path or link',
                  hintText: 'images/photo.png or https://...',
                ),
                onSubmitted: (v) => Navigator.of(context).pop(v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Insert')),
        ],
      );
    },
  );
}

/// Turns what the user picked or typed into the URL to write in the page:
/// links stay as they are; a file inside the workspace is referenced
/// relative to the page; a file outside it is copied to `images/` next to
/// the page (a name that is taken gets a number). A path that leads nowhere
/// is kept as typed, so the page shows it as missing.
Future<String> importImage(PageEditorController editor, String picked) async {
  final path = picked.trim();
  final page = editor.path;
  if (path.isEmpty || path.contains('://') || page == null) return path;
  final workspace = editor.workspace;
  final pageDir = p.posix.dirname(page);
  final normalized = path.replaceAll('\\', '/');

  String relativeToPage(String workspaceRelative) {
    final rel = p.posix.relative(workspaceRelative, from: pageDir == '.' ? '' : pageDir);
    return rel.split('/').map(Uri.encodeComponent).join('/');
  }

  if (!p.isAbsolute(normalized) && !normalized.startsWith('/')) {
    // Relative to the page, or to the workspace root?
    try {
      final atPage = p.posix.normalize(p.posix.join(pageDir, normalized));
      if (await File(workspace.resolve(atPage)).exists()) return relativeToPage(workspace.normalize(atPage));
    } on WorkspaceException {
      // Leads outside the workspace: fall through.
    }
    try {
      if (await File(workspace.resolve(normalized)).exists()) return relativeToPage(workspace.normalize(normalized));
    } on WorkspaceException {
      // Same.
    }
    return path;
  }

  final source = File(path);
  if (!await source.exists()) return path;
  final root = p.normalize(workspace.root);
  if (p.isWithin(root, p.normalize(path))) return relativeToPage(workspace.toRelative(p.normalize(path)));

  // Copy it in: images/<name>, images/<name>-2, ...
  final folder = pageDir == '.' ? 'images' : '$pageDir/images';
  final base = p.basenameWithoutExtension(path), ext = p.extension(path);
  var name = '$base$ext';
  for (var n = 2; await File(workspace.resolve('$folder/$name')).exists(); n++) {
    name = '$base-$n$ext';
  }
  await Directory(workspace.resolve(folder)).create(recursive: true);
  await source.copy(workspace.resolve('$folder/$name'));
  await workspace.refresh();
  return relativeToPage('$folder/$name');
}
