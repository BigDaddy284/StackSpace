import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Paints a rounded rectangle with an optional fill (colour or gradient) and an
/// optional gradient stroke. Used for every Stills & Reels style control.
class _RRectPainter extends CustomPainter {
  _RRectPainter({
    required this.radius,
    this.fill,
    this.fillGradient,
    this.stroke,
    this.strokeColor,
    this.strokeWidth = 1,
    this.glow,
    this.glowSpread = 0,
  });

  final double radius;
  final Color? fill;
  final Gradient? fillGradient;
  final Gradient? stroke;
  final Color? strokeColor;
  final double strokeWidth;
  final Color? glow;
  final double glowSpread;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (glow != null && glowSpread > 0) {
      // Stills & Reels draws six translucent rounded rects growing outwards.
      const steps = 6;
      for (var i = steps; i >= 1; i--) {
        final grow = glowSpread * i / steps;
        final alpha = (glow!.a * (1 - (i - 1) / steps) / 2.2).clamp(0.0, 1.0);
        final r = RRect.fromRectAndRadius(rect.inflate(grow), Radius.circular(radius + grow));
        canvas.drawRRect(r, Paint()..color = glow!.withValues(alpha: alpha));
      }
    }
    final rrect = RRect.fromRectAndRadius(rect.deflate(strokeWidth / 2), Radius.circular(radius));
    if (fillGradient != null) {
      canvas.drawRRect(rrect, Paint()..shader = fillGradient!.createShader(rect));
    } else if (fill != null) {
      canvas.drawRRect(rrect, Paint()..color = fill!);
    }
    if (stroke != null || strokeColor != null) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      if (stroke != null) {
        paint.shader = stroke!.createShader(rect);
      } else {
        paint.color = strokeColor!;
      }
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(_RRectPainter old) =>
      old.fill != fill ||
      old.fillGradient != fillGradient ||
      old.stroke != stroke ||
      old.strokeColor != strokeColor ||
      old.glow != glow ||
      old.radius != radius;
}

/// Tracks hover, press and keyboard focus for a custom control.
class _Interactive extends StatefulWidget {
  const _Interactive({required this.builder, this.onTap});

  final Widget Function(BuildContext context, bool hover, bool pressed, bool focused) builder;
  final VoidCallback? onTap;

  @override
  State<_Interactive> createState() => _InteractiveState();
}

class _InteractiveState extends State<_Interactive> {
  bool _hover = false, _pressed = false, _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap?.call();
          return null;
        }),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: widget.builder(context, _hover && enabled, _pressed, _focused),
      ),
    );
  }
}

/// Stills & Reels' ThemedButton: 36px tall, 8px corners, icon and/or text.
///
/// * normal: Control fill, Hover / Pressed on interaction.
/// * [primary]: blue-to-purple gradient fill with white content.
/// * [checked]: faint gradient fill with a gradient outline.
/// * [compact]: no fill until hovered (toolbar and status-bar icons).
class SsButton extends StatelessWidget {
  const SsButton({
    super.key,
    this.icon,
    this.label,
    this.tooltip,
    this.semanticLabel,
    required this.onPressed,
    this.primary = false,
    this.checked = false,
    this.compact = false,
    this.alignLeft = false,
    this.height = 36,
    this.width,
    this.iconSize = 18,
    this.radius = 8,
    this.fontSize = StackType.button,
    this.fontWeight,
    this.trailing,
  });

  final IconData? icon;
  final String? label;
  final String? tooltip;
  final String? semanticLabel;
  final VoidCallback? onPressed;
  final bool primary, checked, compact, alignLeft;
  final double height;
  final double? width;
  final double iconSize;
  final double radius;
  final double fontSize;
  final FontWeight? fontWeight;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    final enabled = onPressed != null;
    Widget button = _Interactive(
      onTap: onPressed,
      builder: (context, hover, pressed, focused) {
        final fg = !enabled
            ? p.muted
            : primary
                ? p.selectedText
                : p.text;
        Color? fill;
        Gradient? fillGradient;
        Gradient? stroke;
        if (primary && enabled) {
          fillGradient = p.accentGradient;
        } else if (checked && enabled) {
          fillGradient = p.checkedGradient;
          stroke = p.accentGradient;
        } else if (!compact) {
          fill = pressed ? p.pressed : (hover ? p.hover : p.control);
        } else if (hover) {
          fill = pressed ? p.pressed : p.hover;
        }
        final children = <Widget>[
          if (icon != null) Icon(icon, size: iconSize, color: fg),
          if (icon != null && label != null) const SizedBox(width: 8),
          if (label != null)
            Flexible(
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontSize: fontSize, fontWeight: fontWeight),
              ),
            ),
          if (trailing != null) trailing!,
        ];
        return CustomPaint(
          painter: _RRectPainter(
            radius: radius,
            fill: fill,
            fillGradient: fillGradient,
            stroke: stroke,
            strokeColor: focused && stroke == null ? p.accentA : null,
            strokeWidth: stroke != null ? 1.4 : 1.2,
          ),
          foregroundPainter: primary && enabled && hover
              ? _RRectPainter(radius: radius, fill: Colors.white.withAlpha(pressed ? 50 : 28))
              : null,
          child: Container(
            height: height,
            width: width,
            constraints: BoxConstraints(minWidth: height),
            padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 12),
            // Only align (which makes the box fill its parent) when the width is fixed.
            alignment: width == null ? null : (alignLeft ? Alignment.centerLeft : Alignment.center),
            child: Row(
              mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: alignLeft ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: children,
            ),
          ),
        );
      },
    );
    button = Semantics(
      button: true,
      enabled: enabled,
      selected: checked,
      label: semanticLabel ?? label ?? tooltip,
      onTap: onPressed,
      excludeSemantics: true,
      child: button,
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, excludeFromSemantics: true, child: button);
    return button;
  }
}

/// Uppercase bold section heading ("TOOLS", "COLOUR" in Stills & Reels), with
/// an optional value on the right ("13 px").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.value});
  final String text;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    return Semantics(
      header: true,
      child: SizedBox(
        height: 24,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                text.toUpperCase(),
                style: TextStyle(
                  color: p.subText,
                  fontSize: StackType.section,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            if (value != null) Text(value!, style: TextStyle(color: p.subText, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Panel heading ("Edit picture").
class PanelTitle extends StatelessWidget {
  const PanelTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: StackType.display(StackType.panelTitle, StackColors.of(context).text),
        ),
      );
}

/// Wrapped hint text under a panel title.
class HintText extends StatelessWidget {
  const HintText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: StackColors.of(context).subText, fontSize: StackType.hint, height: 1.35));
}

class ModeCell {
  const ModeCell({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;
}

/// The gradient-bordered toolbar pill from the middle of Stills & Reels' top
/// bar: 42px tall, 4px inset, glowing; the selected cell is a blue capsule.
class ModePill extends StatelessWidget {
  const ModePill({super.key, required this.cells});
  final List<ModeCell> cells;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    final mid = Color.lerp(p.accentA, p.accentB, 0.5)!;
    final children = <Widget>[];
    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      if (i > 0) {
        final showSep = !cell.selected && !cells[i - 1].selected;
        children.add(Container(
          width: 1,
          height: 34 * (1 - 2 * 0.22),
          color: showSep ? p.pillSep : Colors.transparent,
        ));
      }
      children.add(_ModeCellView(cell: cell));
    }
    return CustomPaint(
      painter: _RRectPainter(
        radius: 21,
        fill: p.pill,
        stroke: p.accentGradient,
        strokeWidth: 1.6,
        glow: mid.withAlpha(p.dark ? 60 : 30),
        glowSpread: 7,
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _ModeCellView extends StatelessWidget {
  const _ModeCellView({required this.cell});
  final ModeCell cell;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    Widget view = _Interactive(
      onTap: cell.onTap,
      builder: (context, hover, pressed, focused) {
        final fg = cell.selected ? p.selectedText : p.text;
        return CustomPaint(
          painter: cell.selected
              ? _RRectPainter(
                  radius: 17,
                  fillGradient: p.selectedGradient,
                  strokeColor: Colors.white.withAlpha(90),
                  glow: p.accentA.withAlpha(p.dark ? 110 : 60),
                  glowSpread: 6,
                )
              : hover || focused
                  ? _RRectPainter(
                      radius: 16, fill: pressed ? p.pressed : p.hover, strokeColor: focused ? p.accentA : null)
                  : null,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(cell.icon, size: 19, color: fg),
              const SizedBox(width: 9),
              Text(cell.label, style: TextStyle(color: fg, fontSize: StackType.menu)),
            ]),
          ),
        );
      },
    );
    view = Semantics(
      button: true,
      toggled: cell.selected,
      label: cell.label,
      onTap: cell.onTap,
      excludeSemantics: true,
      child: view,
    );
    if (cell.tooltip != null) view = Tooltip(message: cell.tooltip!, excludeFromSemantics: true, child: view);
    return view;
  }
}

/// A box with the pill's look: Pill fill, gradient outline, optional glow.
/// Used for the message box.
class PillBox extends StatelessWidget {
  const PillBox({super.key, required this.child, this.radius = 18, this.glow = false});
  final Widget child;
  final double radius;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    return CustomPaint(
      painter: _RRectPainter(
        radius: radius,
        fill: p.pill,
        stroke: p.accentGradient,
        strokeWidth: 1.6,
        glow: glow ? Color.lerp(p.accentA, p.accentB, 0.5)!.withAlpha(p.dark ? 60 : 30) : null,
        glowSpread: glow ? 7 : 0,
      ),
      child: child,
    );
  }
}

/// A rounded fill used for rows and cards: Hover when hovered, the checked
/// gradient look when [selected].
class SsRow extends StatelessWidget {
  const SsRow({
    super.key,
    required this.child,
    required this.onTap,
    this.selected = false,
    this.onSecondaryTapDown,
    this.height = 32,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final GestureTapDownCallback? onSecondaryTapDown;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    return GestureDetector(
      onSecondaryTapDown: onSecondaryTapDown,
      child: _Interactive(
        onTap: onTap,
        builder: (context, hover, pressed, focused) => CustomPaint(
          painter: selected
              ? _RRectPainter(radius: 8, fillGradient: p.checkedGradient, stroke: p.accentGradient, strokeWidth: 1.4)
              : hover || focused
                  ? _RRectPainter(
                      radius: 8, fill: pressed ? p.pressed : p.hover, strokeColor: focused ? p.accentA : null)
                  : null,
          child: SizedBox(height: height, child: child),
        ),
      ),
    );
  }
}

/// Stills & Reels' empty state: a soft glow, a large gradient icon, a bold
/// title and a line of detail.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.detail, this.actions = const []});
  final IconData icon;
  final String title;
  final String? detail;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final showIcon = constraints.maxHeight > 260;
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 0.7,
            colors: [p.glow.withAlpha(p.dark ? 26 : 50), p.glow.withAlpha(0)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showIcon) ...[
                    ShaderMask(
                      shaderCallback: (r) => p.accentGradient.createShader(r),
                      child: Icon(icon,
                          size: 72,
                          color: Colors.white,
                          shadows: [Shadow(color: p.accentB.withAlpha(110), blurRadius: 18)]),
                    ),
                    const SizedBox(height: 22),
                  ],
                  Text(title,
                      textAlign: TextAlign.center,
                      style: StackType.display(showIcon ? StackType.emptyTitle : 18, p.text)),
                  if (detail != null) ...[
                    const SizedBox(height: 10),
                    Text(detail!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.subText, fontSize: StackType.emptyDetail, height: 1.4)),
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: actions),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Stills & Reels' ThemedToggle: a 40x22 track, gradient when on.
class SsToggle extends StatelessWidget {
  const SsToggle({super.key, required this.value, required this.onChanged, required this.label});
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    return Semantics(
      toggled: value,
      label: label,
      button: true,
      onTap: () => onChanged(!value),
      excludeSemantics: true,
      child: _Interactive(
        onTap: () => onChanged(!value),
        builder: (context, hover, pressed, focused) => SizedBox(
          height: 34,
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(color: p.text, fontSize: StackType.button))),
            CustomPaint(
              painter: _RRectPainter(
                radius: 11,
                fillGradient: value ? p.accentGradient : null,
                fill: value ? null : (hover ? p.hover : p.control),
                strokeColor: focused ? p.accentA : (value ? null : p.controlBorder),
              ),
              child: SizedBox(
                width: 40,
                height: 22,
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 120),
                  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: value ? Colors.white : p.subText),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
