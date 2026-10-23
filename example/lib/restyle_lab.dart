import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

/// `markerTintColor` options the restyle demo cycles through. `null` is
/// MapKit's default red balloon — cycling back to it proves the
/// reset-to-default (nil) path the 0.2.2 fix added to `applyMarkerStyle`.
const tintPalette = <Color?>[
  null,
  .new(0xFF3F51B5), // indigo
  .new(0xFF009688), // teal
  .new(0xFFFF9800), // orange
  .new(0xFFE91E63), // pink
  .new(0xFF4CAF50), // green
];

/// SF Symbol glyph options. `null` clears the glyph back to MapKit's default
/// dot — again exercising the nil-reset path.
const glyphPalette = <String?>[
  null,
  'star.fill',
  'flag.fill',
  'heart.fill',
  'bolt.fill',
  'leaf.fill',
];

/// Callout subtitle options. `null` removes the subtitle, which on a
/// custom-image pin must clear the stale callout accessory.
const subtitlePalette = <String?>[
  null,
  'Selected',
  'Restyled in place',
  'Same id, new icon',
];

/// Styling the demo mutates for a single pin, kept free of widgets so the
/// in-place-update transitions are pure and unit-testable. Every transition
/// returns a *new* value for the *same* pin id — exactly the "stable id, new
/// icon" rebuild the marker-restyle fix repairs.
@immutable
class const PinStyle({
  final Color? tint,
  final String? glyph,
  final String? subtitle,
}) {
  /// Advance `markerTintColor` to the next palette entry (wraps).
  PinStyle withNextTint() =>
      .new(tint: _next(tintPalette, tint), glyph: glyph, subtitle: subtitle);

  /// Advance the SF Symbol glyph to the next palette entry (wraps).
  PinStyle withNextGlyph() =>
      .new(tint: tint, glyph: _next(glyphPalette, glyph), subtitle: subtitle);

  /// Advance the callout subtitle to the next palette entry (wraps).
  PinStyle withNextSubtitle() => .new(
    tint: tint,
    glyph: glyph,
    subtitle: _next(subtitlePalette, subtitle),
  );

  /// Clear every field back to MapKit's defaults.
  PinStyle reset() => const .new();

  @override
  bool operator ==(Object other) =>
      other is PinStyle &&
      other.tint == tint &&
      other.glyph == glyph &&
      other.subtitle == subtitle;

  @override
  int get hashCode => Object.hash(tint, glyph, subtitle);
}

/// The next entry after [current] in [options], wrapping around. An item that
/// is not in the list (or `current` past the end) restarts at the first entry.
T _next<T>(List<T> options, T current) {
  final i = options.indexOf(current);
  return options[(i + 1) % options.length];
}
