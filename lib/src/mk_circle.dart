import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'package:mapkit_flutter/src/_internal/copy_with_keep.dart';
import 'package:mapkit_flutter/src/_internal/validate.dart';
import 'package:mapkit_flutter/src/cl_location_coordinate_2d.dart';
import 'package:mapkit_flutter/src/map_item_id.dart';
import 'package:mapkit_flutter/src/messages.g.dart';
import 'package:mapkit_flutter/src/mk_enums.dart';

/// Typed identifier for an [MKCircle].
typedef MKCircleId = MapItemId<MKCircle>;

/// A circle of a fixed [radius] in meters centered on a coordinate, mirroring
/// `MKCircle(center:radius:)` with its `MKCircleRenderer` fill/stroke
/// properties merged in.
/// See: https://developer.apple.com/documentation/mapkit/mkcircle
@immutable
final class MKCircle({
  /// Unique identifier used to diff this circle across rebuilds.
  required final MKCircleId id,

  /// Center coordinate of the circle.
  required final CLLocationCoordinate2D center,

  /// Radius in meters.
  required final double radius,

  /// Interior fill color (`MKCircleRenderer.fillColor`).
  final Color fillColor = const .new(0x00000000),

  /// Outline stroke color (`MKCircleRenderer.strokeColor`).
  final Color strokeColor = const .new(0xFF000000),

  /// Stroke width in points (`lineWidth`).
  final double lineWidth = 10,

  /// Flutter-side insertion-order hint between overlays. MapKit has no
  /// overlay z-index; ties resolve by insertion.
  final int zIndex = 0,

  /// Whether the circle is hidden on the map.
  final bool isHidden = false,

  /// Whether this overlay captures taps: a tap on it reports to [onTap]
  /// and does not reach the map's `onTap`. With no [onTap] it just blocks
  /// map taps over its area.
  final bool consumeTapEvents = false,

  /// Vertical placement relative to the base map's labels/roads.
  final MKOverlayLevel level = .aboveRoads,

  /// Called when the overlay is tapped; requires [consumeTapEvents] (only
  /// overlays that capture taps receive them).
  final VoidCallback? onTap,
}) {
  /// Creates a circle overlay centered on [center] with [radius] meters.
  ///
  /// Throws [ArgumentError] for a negative or non-finite [radius] or
  /// [lineWidth], or an [onTap] without [consumeTapEvents].
  this {
    checkNonNegative(radius, 'radius');
    checkNonNegative(lineWidth, 'lineWidth');
    checkTapCallback(onTap, consumeTapEvents: consumeTapEvents);
  }

  /// Returns a copy with the given fields replaced.
  MKCircle copyWith({
    CLLocationCoordinate2D? center,
    double? radius,
    Color? fillColor,
    Color? strokeColor,
    double? lineWidth,
    int? zIndex,
    bool? isHidden,
    bool? consumeTapEvents,
    MKOverlayLevel? level,
    VoidCallback? onTap = keepCallback,
  }) => .new(
    id: id,
    center: center ?? this.center,
    radius: radius ?? this.radius,
    fillColor: fillColor ?? this.fillColor,
    strokeColor: strokeColor ?? this.strokeColor,
    lineWidth: lineWidth ?? this.lineWidth,
    zIndex: zIndex ?? this.zIndex,
    isHidden: isHidden ?? this.isHidden,
    consumeTapEvents: consumeTapEvents ?? this.consumeTapEvents,
    level: level ?? this.level,
    onTap: identical(onTap, keepCallback) ? this.onTap : onTap,
  );

  /// Converts this circle to its Pigeon wire representation.
  @internal
  PlatformCircle toPlatform() => .new(
    id: id.value,
    center: center.toPlatform(),
    radius: radius,
    fillColorArgb: fillColor.toARGB32(),
    strokeColorArgb: strokeColor.toARGB32(),
    lineWidth: lineWidth,
    zIndex: zIndex,
    isHidden: isHidden,
    consumeTapEvents: consumeTapEvents,
    level: level,
  );

  @override
  bool operator ==(Object other) =>
      other is MKCircle &&
      other.id == id &&
      other.center == center &&
      other.radius == radius &&
      other.fillColor == fillColor &&
      other.strokeColor == strokeColor &&
      other.lineWidth == lineWidth &&
      other.zIndex == zIndex &&
      other.isHidden == isHidden &&
      other.consumeTapEvents == consumeTapEvents &&
      other.level == level;

  @override
  int get hashCode => Object.hash(
    id,
    center,
    radius,
    fillColor,
    strokeColor,
    lineWidth,
    zIndex,
    isHidden,
    consumeTapEvents,
    level,
  );

  @override
  String toString() {
    final b = StringBuffer('MKCircle(')
      ..write('id: ${id.value}, ')
      ..write('center: $center, ')
      ..write('radius: $radius, ')
      ..write('lineWidth: $lineWidth, ')
      ..write('isHidden: $isHidden, ')
      ..write('level: ${level.name}, ')
      ..write('onTap: ${onTap != null ? 'set' : 'null'}');
    return (b..write(')')).toString();
  }
}
