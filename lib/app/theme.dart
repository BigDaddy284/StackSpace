import 'package:flutter/material.dart';

/// Colours shared with Stills & Reels: deep navy surfaces, a bright blue accent
/// and a blue-to-violet gradient for the "hero" controls. Every text colour here
/// is checked against the surfaces it sits on in `test/theme_contrast_test.dart`
/// (WCAG AA: 4.5:1 for text, 3:1 for borders and icons).
class StackPalette {
  const StackPalette({
    required this.brightness,
    required this.canvas,
    required this.panel,
    required this.dock,
    required this.raised,
    required this.control,
    required this.controlHigh,
    required this.selected,
    required this.onSelected,
    required this.text,
    required this.textMuted,
    required this.textSubtle,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.violet,
    required this.divider,
    required this.inputBorder,
    required this.warning,
    required this.success,
    required this.error,
    required this.errorContainer,
    required this.onErrorContainer,
  });

  final Brightness brightness;

  /// Editor background.
  final Color canvas;

  /// Sidebar and status bar.
  final Color panel;

  /// Chat dock background.
  final Color dock;

  /// Cards, popup menus and dialogs.
  final Color raised;

  /// Button and chip fills, user chat bubbles.
  final Color control;

  /// Code blocks.
  final Color controlHigh;

  /// Selected sidebar row and context chips.
  final Color selected;
  final Color onSelected;

  final Color text;

  /// Secondary text: hints, labels.
  final Color textMuted;

  /// Least important text that still has to be readable (counters, separators).
  final Color textSubtle;

  /// Fill for primary buttons (white text on top).
  final Color accent;
  final Color onAccent;

  /// Accent used as text or icon colour on dark/light surfaces.
  final Color accentText;
  final Color violet;
  final Color divider;

  /// Border of text inputs; must reach 3:1 against the dock.
  final Color inputBorder;
  final Color warning;
  final Color success;
  final Color error;
  final Color errorContainer;
  final Color onErrorContainer;

  LinearGradient get gradient => LinearGradient(colors: [accent, violet]);

  /// Surfaces that text can sit on, for the contrast test.
  Map<String, Color> get surfaces => {
        'canvas': canvas,
        'panel': panel,
        'dock': dock,
        'raised': raised,
        'control': control,
      };

  static const dark = StackPalette(
    brightness: Brightness.dark,
    canvas: Color(0xFF0B0F1F),
    panel: Color(0xFF0E1325),
    dock: Color(0xFF0D1224),
    raised: Color(0xFF161C33),
    control: Color(0xFF1A2140),
    controlHigh: Color(0xFF202846),
    selected: Color(0xFF1F2B55),
    onSelected: Color(0xFFDCE4FF),
    text: Color(0xFFE8EBF5),
    textMuted: Color(0xFFA3ABC6),
    textSubtle: Color(0xFF8C95B3),
    accent: Color(0xFF2F6BF5),
    onAccent: Color(0xFFFFFFFF),
    accentText: Color(0xFF7AA2FF),
    violet: Color(0xFF8B5CF6),
    divider: Color(0xFF232B47),
    inputBorder: Color(0xFF5C6894),
    warning: Color(0xFFF2B451),
    success: Color(0xFF4CC38A),
    error: Color(0xFFFF6B7A),
    errorContainer: Color(0xFF3A1520),
    onErrorContainer: Color(0xFFFFC9CF),
  );

  static const light = StackPalette(
    brightness: Brightness.light,
    canvas: Color(0xFFFFFFFF),
    panel: Color(0xFFF2F4FA),
    dock: Color(0xFFF8F9FD),
    raised: Color(0xFFFFFFFF),
    control: Color(0xFFE8EBF5),
    controlHigh: Color(0xFFE1E5F0),
    selected: Color(0xFFDDE5FF),
    onSelected: Color(0xFF13235C),
    text: Color(0xFF12162A),
    textMuted: Color(0xFF4A5270),
    textSubtle: Color(0xFF5A6280),
    accent: Color(0xFF2C62E8),
    onAccent: Color(0xFFFFFFFF),
    accentText: Color(0xFF2556D1),
    violet: Color(0xFF6A4BE8),
    divider: Color(0xFFDDE1EC),
    inputBorder: Color(0xFF7A829F),
    warning: Color(0xFF8A5300),
    success: Color(0xFF1C7A4C),
    error: Color(0xFFC42B3B),
    errorContainer: Color(0xFFFCE4E7),
    onErrorContainer: Color(0xFF7A1020),
  );
}

/// Extra colours the widgets need that ColorScheme has no slot for.
class StackColors extends ThemeExtension<StackColors> {
  const StackColors(this.palette);
  final StackPalette palette;

  static StackPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<StackColors>()?.palette ??
        (theme.brightness == Brightness.dark ? StackPalette.dark : StackPalette.light);
  }

  @override
  StackColors copyWith({StackPalette? palette}) => StackColors(palette ?? this.palette);

  @override
  StackColors lerp(StackColors? other, double t) => t < 0.5 || other == null ? this : other;
}

ThemeData buildTheme(StackPalette p) {
  final scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
    primaryContainer: p.selected,
    onPrimaryContainer: p.onSelected,
    secondary: p.violet,
    onSecondary: p.onAccent,
    secondaryContainer: p.selected,
    onSecondaryContainer: p.onSelected,
    tertiary: p.warning,
    onTertiary: p.canvas,
    error: p.error,
    onError: p.brightness == Brightness.dark ? p.canvas : p.onAccent,
    errorContainer: p.errorContainer,
    onErrorContainer: p.onErrorContainer,
    surface: p.canvas,
    onSurface: p.text,
    onSurfaceVariant: p.textMuted,
    surfaceContainerLowest: p.dock,
    surfaceContainerLow: p.panel,
    surfaceContainer: p.raised,
    surfaceContainerHigh: p.control,
    surfaceContainerHighest: p.controlHigh,
    outline: p.textSubtle,
    outlineVariant: p.divider,
    shadow: Colors.black,
    inverseSurface: p.text,
    onInverseSurface: p.canvas,
    inversePrimary: p.accentText,
  );
  final radius = BorderRadius.circular(8);
  final controlShape = RoundedRectangleBorder(borderRadius: radius);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.compact,
    scaffoldBackgroundColor: p.canvas,
    extensions: [StackColors(p)],
    dividerTheme: DividerThemeData(color: p.divider, space: 1, thickness: 1),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(color: p.text, borderRadius: BorderRadius.circular(6)),
      textStyle: TextStyle(color: p.canvas, fontSize: 12),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accentText,
      selectionColor: p.accent.withValues(alpha: 0.35),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: p.textMuted, shape: controlShape),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.accentText, shape: controlShape),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: controlShape)),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        backgroundColor: p.control,
        side: BorderSide(color: p.divider),
        shape: controlShape,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: p.divider)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.divider)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.text,
      contentTextStyle: TextStyle(color: p.canvas),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      labelStyle: TextStyle(color: p.textMuted),
      hintStyle: TextStyle(color: p.textMuted),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStatePropertyAll(p.inputBorder),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(p.textSubtle.withValues(alpha: 0.5)),
      radius: const Radius.circular(4),
    ),
  );
}

/// Small uppercase heading used for sidebar sections, like "TOOLS" in Stills & Reels.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    return Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(color: p.textMuted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6),
      ),
    );
  }
}

/// A rounded pill with the blue-to-violet gradient border, used for the
/// Assistant button and the focused message box.
class GradientBorder extends StatelessWidget {
  const GradientBorder({
    super.key,
    required this.child,
    this.radius = 999,
    this.width = 1.5,
    this.glow = false,
    this.active = true,
  });

  final Widget child;
  final double radius;
  final double width;
  final bool glow;

  /// When false, draws a plain input border instead of the gradient.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = StackColors.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: active ? p.gradient : null,
        color: active ? null : p.inputBorder,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: glow
            ? [BoxShadow(color: p.violet.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: -2)]
            : null,
      ),
      padding: EdgeInsets.all(active ? width : 1),
      child: ClipRRect(borderRadius: BorderRadius.circular(radius - width), child: child),
    );
  }
}
