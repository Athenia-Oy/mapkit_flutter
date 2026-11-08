import 'package:flutter/foundation.dart';
import 'package:mapkit_flutter/src/_internal/validate.dart';
import 'package:mapkit_flutter/src/map_item_id.dart';
import 'package:mapkit_flutter/src/messages.g.dart';
import 'package:mapkit_flutter/src/mk_enums.dart';
import 'package:meta/meta.dart';

/// Typed identifier for an [MKTileOverlay].
typedef MKTileOverlayId = MapItemId<MKTileOverlay>;

/// Raster tile overlay drawn over the base map, mirroring
/// `MKTileOverlay(urlTemplate:)` with its renderer [alpha] merged in.
///
/// The [urlTemplate] uses `{x}`, `{y}`, `{z}` placeholders matching the
/// standard slippy-map scheme.
/// See: https://developer.apple.com/documentation/mapkit/mktileoverlay
@immutable
final class MKTileOverlay({
  /// Unique identifier used to add or remove this tile overlay.
  required final MKTileOverlayId id,

  /// Slippy-map URL template, e.g.
  /// `https://tile.openstreetmap.org/{z}/{x}/{y}.png`.
  required final String urlTemplate,

  /// Lowest tile zoom level the overlay serves (`MKTileOverlay.minimumZ`).
  final int minimumZ = 0,

  /// Highest tile zoom level the overlay serves (`MKTileOverlay.maximumZ`).
  final int maximumZ = 21,

  /// Tile size in points (`MKTileOverlay.tileSize`). Most providers serve
  /// 256-point tiles; Mapbox / Apple high-DPI sources use 512.
  final int tileSize = 256,

  /// When `true`, the overlay replaces the base map underneath it
  /// (`MKTileOverlay.canReplaceMapContent`). Use for opaque world-coverage
  /// providers like a styled basemap; leave `false` for transparent
  /// supplemental layers. A snapshot leaves out the base map too, and is
  /// transparent wherever no tile covers it.
  final bool canReplaceMapContent = false,

  /// Renderer opacity (`MKTileOverlayRenderer.alpha`). Default 1.0.
  final double alpha = 1.0,

  /// Vertical placement relative to the base map's labels/roads.
  final MKOverlayLevel level = .aboveRoads,
}) {
  /// Creates a raster tile overlay for [urlTemplate].
  ///
  /// Throws [ArgumentError] when [alpha] is outside `[0, 1]`, [minimumZ] is
  /// negative or above [maximumZ], or [tileSize] is not positive.
  this {
    checkInRange(alpha, 0, 1, 'alpha');
    if (minimumZ < 0) {
      throw ArgumentError.value(minimumZ, 'minimumZ', 'must be >= 0');
    }
    if (minimumZ > maximumZ) {
      throw ArgumentError(
        'minimumZ ($minimumZ) must be <= maximumZ ($maximumZ)',
      );
    }
    if (tileSize <= 0) {
      throw ArgumentError.value(tileSize, 'tileSize', 'must be > 0');
    }
  }

  /// Converts this tile overlay to its Pigeon wire representation.
  @internal
  PlatformTileOverlay toPlatform() => .new(
    id: id.value,
    urlTemplate: urlTemplate,
    minimumZ: minimumZ,
    maximumZ: maximumZ,
    tileSize: tileSize,
    canReplaceMapContent: canReplaceMapContent,
    alpha: alpha,
    level: level,
  );

  @override
  bool operator ==(Object other) =>
      other is MKTileOverlay &&
      other.id == id &&
      other.urlTemplate == urlTemplate &&
      other.minimumZ == minimumZ &&
      other.maximumZ == maximumZ &&
      other.tileSize == tileSize &&
      other.canReplaceMapContent == canReplaceMapContent &&
      other.alpha == alpha &&
      other.level == level;

  @override
  int get hashCode => Object.hash(
    id,
    urlTemplate,
    minimumZ,
    maximumZ,
    tileSize,
    canReplaceMapContent,
    alpha,
    level,
  );

  @override
  String toString() {
    final b = StringBuffer('MKTileOverlay(')
      ..write('id: ${id.value}, ')
      ..write('urlTemplate: $urlTemplate, ')
      ..write('z: $minimumZ-$maximumZ, ')
      ..write('alpha: $alpha, ')
      ..write('level: ${level.name}');
    return (b..write(')')).toString();
  }
}
