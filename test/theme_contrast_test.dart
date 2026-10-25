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
  for (final p in [StackPalette.dark, StackPalette.light]) {
    group('${p.brightness.name} palette', () {
      test('body and secondary text reach 4.5:1 on every surface', () {
        for (final entry in p.surfaces.entries) {
          for (final (name, color) in [
            ('text', p.text),
            ('textMuted', p.textMuted),
            ('textSubtle', p.textSubtle),
            ('accentText', p.accentText),
            ('error', p.error),
          ]) {
            expect(contrast(color, entry.value), greaterThanOrEqualTo(4.5),
                reason: '$name on ${entry.key}: ${contrast(color, entry.value).toStringAsFixed(2)}');
          }
        }
      });

      test('filled and selected states keep readable text', () {
        expect(contrast(p.onAccent, p.accent), greaterThanOrEqualTo(4.5));
        expect(contrast(p.onSelected, p.selected), greaterThanOrEqualTo(4.5));
        expect(contrast(p.text, p.selected), greaterThanOrEqualTo(4.5));
        expect(contrast(p.onErrorContainer, p.errorContainer), greaterThanOrEqualTo(4.5));
        expect(contrast(p.text, p.controlHigh), greaterThanOrEqualTo(4.5));
      });

      test('input borders, status colours and icons reach 3:1', () {
        for (final surface in [p.dock, p.raised, p.panel]) {
          expect(contrast(p.inputBorder, surface), greaterThanOrEqualTo(3));
          expect(contrast(p.success, surface), greaterThanOrEqualTo(3));
          expect(contrast(p.warning, surface), greaterThanOrEqualTo(3));
          expect(contrast(p.accent, surface), greaterThanOrEqualTo(3));
        }
      });
    });
  }
}
