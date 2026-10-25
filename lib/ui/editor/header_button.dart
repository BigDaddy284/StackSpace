import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// A small flat button for the header strip of a code space or a table.
class HeaderButton extends StatelessWidget {
  const HeaderButton(
      {super.key, required this.tooltip, required this.semanticLabel, required this.onPressed, required this.child});
  final String tooltip;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = StackColors.of(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: semanticLabel,
        enabled: onPressed != null,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(5),
          hoverColor: palette.hover,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}
