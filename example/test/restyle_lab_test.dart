import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter_example/restyle_lab.dart';

void main() {
  group('PinStyle in-place transitions', () {
    test('withNextTint advances the palette and wraps to the null default', () {
      var style = const PinStyle();
      check(style.tint).isNull();

      style = style.withNextTint();
      check(style.tint).equals(tintPalette[1]);

      // Walk to the last entry, then wrap back to MapKit's default (null).
      for (var i = 2; i < tintPalette.length; i++) {
        style = style.withNextTint();
      }
      check(style.tint).equals(tintPalette.last);
      check(style.withNextTint().tint).isNull();
    });

    test('withNextGlyph advances while preserving tint and subtitle', () {
      const start = PinStyle(tint: .new(0xFF009688), subtitle: 'keep me');
      final next = start.withNextGlyph();

      check(next.glyph).equals(glyphPalette[1]);
      check(next.tint).equals(start.tint);
      check(next.subtitle).equals('keep me');
    });

    test('withNextSubtitle cycles through the palette back to null', () {
      var style = const PinStyle();
      for (var i = 0; i < subtitlePalette.length; i++) {
        style = style.withNextSubtitle();
      }
      check(style.subtitle).isNull();
    });

    test('reset clears every field to the defaults', () {
      const style = PinStyle(
        tint: .new(0xFFE91E63),
        glyph: 'star.fill',
        subtitle: 'x',
      );
      check(style.reset()).equals(const .new());
    });

    test('value equality distinguishes a restyle from the original', () {
      const a = PinStyle(tint: .new(0xFF3F51B5));
      check(a).equals(const .new(tint: .new(0xFF3F51B5)));
      check(a == a.withNextTint()).isFalse();
    });
  });
}
