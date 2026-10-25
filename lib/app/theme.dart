import 'package:flutter/material.dart';

/// The Stills & Reels palette, copied value for value from its `src/Theme.cs`
/// (github.com/BigDaddy284/Stills-and-Reels). Field names match that file so
/// the two apps can be kept in step.
///
/// One accessibility rule on top: [muted] fails WCAG AA for text (3.9:1 dark,
/// 3.0:1 light), so it's only used for disabled controls. Small text uses [text]
/// or [subText]. `test/theme_contrast_test.dart` checks this.
class StackPalette {
  const StackPalette({
    required this.dark,
    required this.window,
    required this.bar,
    required this.barBorder,
    required this.canvas,
    required this.panel,
    required this.text,
    required this.subText,
    required this.muted,
    required this.hover,
    required this.pressed,
    required this.pill,
    required this.pillSep,
    required this.accentA,
    required this.accentB,
    required this.selectedText,
    required this.control,
    required this.controlBorder,
    required this.warning,
    required this.glow,
    required this.error,
    required this.success,
  });

  final bool dark;

  /// Form background.
  final Color window;

  /// Top bar, status bar, toolbars.
  final Color bar;

  /// Hairlines between bars and content.
  final Color barBorder;

  /// The editing area.
  final Color canvas;

  /// Sidebars, pop-outs, menus, tooltips, the assistant dock.
  final Color panel;
  final Color text;
  final Color subText;

  /// Disabled text and icons only.
  final Color muted;
  final Color hover;
  final Color pressed;

  /// Inside of the gradient-bordered pill (mode toolbar, message box).
  final Color pill;
  final Color pillSep;

  /// Gradient start (blue).
  final Color accentA;

  /// Gradient end (purple).
  final Color accentB;
  final Color selectedText;

  /// Button fills, slider tracks, inactive fills.
  final Color control;
  final Color controlBorder;
  final Color warning;

  /// Ambient glow behind empty states.
  final Color glow;

  // Not in Stills & Reels, which has no error or success states; chosen to sit with the palette.
  final Color error;
  final Color success;

  Brightness get brightness => dark ? Brightness.dark : Brightness.light;

  LinearGradient get accentGradient => LinearGradient(colors: [accentA, accentB]);

  /// The selected cell in the mode toolbar: a vertical blue gradient.
  LinearGradient get selectedGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        // Stills & Reels lightens the bottom towards (90,150,255), which leaves its
        // white label at 3.6:1. Darkening it slightly keeps the label at 4.5:1 or better.
        colors: [Color.lerp(accentA, Colors.black, 0.04)!, Color.lerp(accentA, Colors.black, 0.2)!],
      );

  /// The "checked" button fill: the accent gradient at low opacity.
  LinearGradient get checkedGradient => LinearGradient(colors: [
        accentA.withAlpha(dark ? 70 : 40),
        accentB.withAlpha(dark ? 70 : 40),
      ]);

  /// Surfaces text sits on, for the contrast test.
  Map<String, Color> get surfaces =>
      {'window': window, 'bar': bar, 'canvas': canvas, 'panel': panel, 'pill': pill, 'control': control, 'hover': hover};

  static const darkPalette = StackPalette(
    dark: true,
    window: Color.fromARGB(255, 10, 13, 26),
    bar: Color.fromARGB(255, 13, 17, 33),
    barBorder: Color.fromARGB(255, 30, 37, 62),
    canvas: Color.fromARGB(255, 9, 12, 24),
    panel: Color.fromARGB(255, 14, 19, 37),
    text: Color.fromARGB(255, 234, 238, 250),
    subText: Color.fromARGB(255, 172, 182, 210),
    muted: Color.fromARGB(255, 104, 114, 146),
    hover: Color.fromARGB(255, 26, 33, 62),
    pressed: Color.fromARGB(255, 34, 43, 80),
    pill: Color.fromARGB(255, 12, 18, 44),
    pillSep: Color.fromARGB(255, 62, 74, 128),
    accentA: Color.fromARGB(255, 38, 104, 255),
    accentB: Color.fromARGB(255, 176, 72, 255),
    selectedText: Color(0xFFFFFFFF),
    control: Color.fromARGB(255, 32, 40, 70),
    controlBorder: Color.fromARGB(255, 46, 56, 92),
    warning: Color.fromARGB(255, 255, 190, 110),
    glow: Color.fromARGB(255, 40, 70, 150),
    error: Color.fromARGB(255, 255, 120, 140),
    success: Color.fromARGB(255, 80, 200, 140),
  );

  static const lightPalette = StackPalette(
    dark: false,
    window: Color.fromARGB(255, 244, 246, 251),
    bar: Color.fromARGB(255, 255, 255, 255),
    barBorder: Color.fromARGB(255, 221, 226, 238),
    canvas: Color.fromARGB(255, 236, 240, 247),
    panel: Color.fromARGB(255, 250, 251, 254),
    text: Color.fromARGB(255, 20, 26, 45),
    subText: Color.fromARGB(255, 74, 85, 112),
    muted: Color.fromARGB(255, 138, 147, 168),
    hover: Color.fromARGB(255, 232, 237, 249),
    pressed: Color.fromARGB(255, 218, 226, 246),
    pill: Color.fromARGB(255, 243, 245, 255),
    pillSep: Color.fromARGB(255, 196, 204, 232),
    accentA: Color.fromARGB(255, 37, 99, 245),
    accentB: Color.fromARGB(255, 150, 62, 240),
    selectedText: Color(0xFFFFFFFF),
    control: Color.fromARGB(255, 222, 228, 242),
    controlBorder: Color.fromARGB(255, 200, 208, 228),
    warning: Color.fromARGB(255, 196, 98, 0),
    glow: Color.fromARGB(255, 160, 185, 255),
    error: Color.fromARGB(255, 190, 30, 60),
    success: Color.fromARGB(255, 20, 120, 70),
  );
}

/// Exposes the palette through the theme.
class StackColors extends ThemeExtension<StackColors> {
  const StackColors(this.palette);
  final StackPalette palette;

  static StackPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<StackColors>()?.palette ??
        (theme.brightness == Brightness.dark ? StackPalette.darkPalette : StackPalette.lightPalette);
  }

  @override
  StackColors copyWith({StackPalette? palette}) => StackColors(palette ?? this.palette);

  @override
  StackColors lerp(StackColors? other, double t) => t < 0.5 || other == null ? this : other;
}

/// Font sizes from Stills & Reels, converted from points (at 96 DPI, 1pt = 4/3 px).
class StackType {
  static const fontFamily = 'Segoe UI Variable Text';
  static const fontFallback = ['Segoe UI', 'Selawik', 'Noto Sans', 'DejaVu Sans'];
  static const displayFamily = 'Segoe UI Variable Display';
  static const displayFallback = ['Segoe UI Semibold', 'Segoe UI', 'Noto Sans', 'DejaVu Sans'];

  static const button = 13.3; // UiFont(10)
  static const menu = 14.0; // UiFont(10.5), status bar too
  static const hint = 12.7; // UiFont(9.5), tooltips too
  static const section = 11.3; // UiFont(8.5, Bold)
  static const panelTitle = 17.3; // DisplayFont(13)
  static const emptyTitle = 25.3; // DisplayFont(19)
  static const emptyDetail = 14.0; // UiFont(10.5)
  static const mono = ['Cascadia Mono', 'Consolas', 'DejaVu Sans Mono', 'monospace'];

  static TextStyle display(double size, Color color) => TextStyle(
        fontFamily: displayFamily,
        fontFamilyFallback: displayFallback,
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
      );
}

ThemeData buildTheme(StackPalette p) {
  final scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.accentA,
    onPrimary: p.selectedText,
    primaryContainer: p.pressed,
    onPrimaryContainer: p.text,
    secondary: p.accentB,
    onSecondary: p.selectedText,
    secondaryContainer: p.pressed,
    onSecondaryContainer: p.text,
    tertiary: p.warning,
    onTertiary: p.window,
    error: p.error,
    onError: p.dark ? p.window : p.selectedText,
    errorContainer: p.error.withAlpha(p.dark ? 40 : 28),
    onErrorContainer: p.text,
    surface: p.canvas,
    onSurface: p.text,
    onSurfaceVariant: p.subText,
    surfaceContainerLowest: p.panel,
    surfaceContainerLow: p.panel,
    surfaceContainer: p.panel,
    surfaceContainerHigh: p.control,
    surfaceContainerHighest: p.pressed,
    outline: p.subText,
    outlineVariant: p.barBorder,
    shadow: Colors.black,
    inverseSurface: p.text,
    onInverseSurface: p.window,
    inversePrimary: p.accentA,
  );
  final base = ThemeData(brightness: p.brightness, useMaterial3: true);
  final textTheme = base.textTheme.apply(
    fontFamily: StackType.fontFamily,
    fontFamilyFallback: StackType.fontFallback,
    bodyColor: p.text,
    displayColor: p.text,
  );
  final radius8 = BorderRadius.circular(8);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.compact,
    fontFamily: StackType.fontFamily,
    fontFamilyFallback: StackType.fontFallback,
    textTheme: textTheme,
    scaffoldBackgroundColor: p.window,
    canvasColor: p.panel,
    hoverColor: p.hover,
    highlightColor: p.pressed,
    splashFactory: NoSplash.splashFactory,
    focusColor: p.accentA.withAlpha(50),
    extensions: [StackColors(p)],
    dividerTheme: DividerThemeData(color: p.barBorder, space: 1, thickness: 1),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: p.panel, border: Border.all(color: p.controlBorder)),
      textStyle: TextStyle(
        color: p.text,
        fontSize: StackType.hint,
        fontFamily: StackType.fontFamily,
        fontFamilyFallback: StackType.fontFallback,
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accentA,
      selectionColor: p.accentA.withAlpha(p.dark ? 90 : 60),
    ),
    iconTheme: IconThemeData(color: p.text, size: 18),
    popupMenuTheme: PopupMenuThemeData(
      color: p.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(side: BorderSide(color: p.controlBorder)),
      textStyle: TextStyle(color: p.text, fontSize: StackType.menu),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.panel),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: p.controlBorder)),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? p.muted : p.text),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.pressed)
            ? p.pressed
            : s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
                ? p.hover
                : Colors.transparent),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: StackType.menu)),
        minimumSize: const WidgetStatePropertyAll(Size(180, 34)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.controlBorder)),
      titleTextStyle: StackType.display(StackType.panelTitle, p.text),
      contentTextStyle: TextStyle(color: p.subText, fontSize: StackType.menu),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.panel,
      contentTextStyle: TextStyle(color: p.text, fontSize: StackType.menu),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius8, side: BorderSide(color: p.controlBorder)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.control,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      labelStyle: TextStyle(color: p.subText),
      floatingLabelStyle: TextStyle(color: p.subText),
      hintStyle: TextStyle(color: p.subText),
      border: OutlineInputBorder(borderRadius: radius8, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius8, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: radius8, borderSide: BorderSide(color: p.accentA, width: 1.4)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(p.controlBorder),
      radius: const Radius.circular(4),
      thickness: const WidgetStatePropertyAll(6),
    ),
  );
}
