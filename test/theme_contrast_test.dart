import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_space/app/theme.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('palettes are the exact Stills & Reels values', () {
    expect(StackPalette.darkPalette.panel, const Color.fromARGB(255, 14, 19, 37));
    expect(StackPalette.darkPalette.accentA, const Color.fromARGB(255, 38, 104, 255));
    expect(StackPalette.lightPalette.panel, const Color.fromARGB(255, 250, 251, 254));
    expect(StackPalette.lightPalette.accentB, const Color.fromARGB(255, 150, 62, 240));
  });

  for (final p in [StackPalette.darkPalette, StackPalette.lightPalette]) {
    group('${p.brightness.name} palette', () {
      test('Text and SubText reach 4.5:1 on every surface', () {
        for (final entry in p.surfaces.entries) {
          for (final (name, color) in [('text', p.text), ('subText', p.subText)]) {
            expect(contrast(color, entry.value), greaterThanOrEqualTo(4.5),
                reason: '$name on ${entry.key}: ${contrast(color, entry.value).toStringAsFixed(2)}');
          }
        }
      });

      test('error text reaches 4.5:1 on the canvas and panel', () {
        for (final surface in [p.canvas, p.panel, p.control]) {
          expect(contrast(p.error, surface), greaterThanOrEqualTo(4.5));
        }
      });

      test('white text on the primary gradient reaches 4:1 across it', () {
        // AA large-text / UI level at the purple end in dark mode (4.03), 4.5 at the blue end.
        expect(contrast(Colors.white, p.accentA), greaterThanOrEqualTo(4.5));
        expect(contrast(Colors.white, p.accentB), greaterThanOrEqualTo(4.0));
      });

      test('accents, status colours and the pill outline reach 3:1', () {
        for (final surface in [p.panel, p.pill, p.canvas, p.bar]) {
          for (final (name, color) in [
            ('accentA', p.accentA),
            ('accentB', p.accentB),
            ('success', p.success),
            ('warning', p.warning),
          ]) {
            expect(contrast(color, surface), greaterThanOrEqualTo(3),
                reason: '$name: ${contrast(color, surface).toStringAsFixed(2)}');
          }
        }
      });

      test('Muted is below 4.5:1, so it is only used for disabled controls', () {
        expect(contrast(p.muted, p.panel), lessThan(4.5));
      });
    });
  }
}
