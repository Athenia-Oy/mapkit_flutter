import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'package:mapkit_flutter/src/_internal/copy_with_keep.dart';
import 'package:mapkit_flutter/src/_internal/validate.dart';
import 'package:mapkit_flutter/src/cl_location_coordinate_2d.dart';
import 'package:mapkit_flutter/src/map_item_id.dart';
import 'package:mapkit_flutter/src/messages.g.dart';
import 'package:mapkit_flutter/src/mk_enums.dart';

/// Typed identifier for an [MKPolyline].
typedef MKPolylineId = MapItemId<MKPolyline>;

/// A connected sequence of line segments through geographical [coordinates],
/// mirroring `MKPolyline` with its `MKPolylineRenderer` stroke properties
/// merged in ([strokeColor], [lineWidth], [lineCap], [lineJoin],
/// [lineDashPattern]).
///
/// [MKPolyline.geodesic] follows the shortest path over the globe
/// (`MKGeodesicPolyline`); two or more [gradientColors] render with
/// `MKGradientPolylineRenderer`.
/// See: https://developer.apple.com/documentation/mapkit/mkpolyline
@immutable
final class MKPolyline {
  /// Straight-segment polyline (`MKPolyline`).
  ///
  /// Throws [ArgumentError] for a negative or non-finite [lineWidth], a
  /// [lineDashPattern] with a negative or non-finite length or only zeros,
  /// a single [gradientColors] entry, or an [onTap] without
  /// [consumeTapEvents].
  new({
    required this.id,
    required List<CLLocationCoordinate2D> coordinates,
    this.strokeColor = const .new(0xFF000000),
    this.lineWidth = 10,
    this.lineCap = .round,
    this.lineJoin = .round,
    List<double>? lineDashPattern,
    List<Color> gradientColors = const [],
    this.isHidden = false,
    this.zIndex = 0,
    this.consumeTapEvents = false,
    this.level = .aboveRoads,
    this.onTap,
  }) : coordinates = .unmodifiable(coordinates),
       lineDashPattern = lineDashPattern == null
           ? null
           : .unmodifiable(lineDashPattern),
       gradientColors = .unmodifiable(gradientColors),
       isGeodesic = false {
    _validate();
  }

  /// Polyline whose segments follow the shortest path over the globe,
  /// mirroring `MKGeodesicPolyline`.
  /// See: https://developer.apple.com/documentation/mapkit/mkgeodesicpolyline
  new geodesic({
    required this.id,
    required List<CLLocationCoordinate2D> coordinates,
    this.strokeColor = const .new(0xFF000000),
    this.lineWidth = 10,
    this.lineCap = .round,
    this.lineJoin = .round,
    List<double>? lineDashPattern,
    List<Color> gradientColors = const [],
    this.isHidden = false,
    this.zIndex = 0,
    this.consumeTapEvents = false,
    this.level = .aboveRoads,
    this.onTap,
  }) : coordinates = .unmodifiable(coordinates),
       lineDashPattern = lineDashPattern == null
           ? null
           : .unmodifiable(lineDashPattern),
       gradientColors = .unmodifiable(gradientColors),
       isGeodesic = true {
    _validate();
  }

  void _validate() {
    checkNonNegative(lineWidth, 'lineWidth');
    if (lineDashPattern case final pattern? when pattern.isNotEmpty) {
      for (final length in pattern) {
        checkNonNegative(length, 'lineDashPattern');
      }
      if (!pattern.any((length) => length > 0)) {
        throw ArgumentError.value(
          pattern,
          'lineDashPattern',
          'needs a dash or gap longer than 0',
        );
      }
    }
    checkTapCallback(onTap, consumeTapEvents: consumeTapEvents);
    if (gradientColors.length == 1) {
      throw ArgumentError.value(
        gradientColors,
        'gradientColors',
        'needs at least two colors (or none)',
      );
    }
  }

  /// Unique identifier used to diff this polyline across rebuilds.
  final MKPolylineId id;

  /// The vertices of the polyline. Fewer than two coordinates draws
  /// nothing — on the live map and in snapshots (matches
  /// `MKPolylineRenderer`; a single point no longer renders a dot in
  /// snapshots).
  final List<CLLocationCoordinate2D> coordinates;

  /// Whether segments follow great-circle paths (`MKGeodesicPolyline`).
  final bool isGeodesic;

  /// Stroke color (`MKPolylineRenderer.strokeColor`). Ignored when
  /// [gradientColors] is non-empty.
  final Color strokeColor;

  /// Stroke width in points (`lineWidth`).
  final double lineWidth;

  /// Stroke end-cap style. MapKit's path renderer defaults to round caps and
  /// joins, mirrored here.
  final CGLineCap lineCap;

  /// Stroke corner-join style (`MKOverlayPathRenderer.lineJoin`).
  final CGLineJoin lineJoin;

  /// Alternating dash/gap lengths in points (`lineDashPattern`), e.g.
  /// `[6, 3]`. `null` or empty strokes solid. Every length is finite and
  /// `>= 0`, with at least one `> 0`. Dotted: `[0, lineWidth * 1.5]` with
  /// [CGLineCap.round].
  final List<double>? lineDashPattern;

  /// When non-empty, the line renders with a smooth gradient spreading these
  /// colors evenly from start to end (`MKGradientPolylineRenderer`), ignoring
  /// [strokeColor]. Empty or at least two colors.
  final List<Color> gradientColors;

  /// Whether the polyline is hidden on the map.
  final bool isHidden;

  /// Flutter-side insertion-order hint between overlays. MapKit has no
  /// overlay z-index; ties resolve by insertion.
  final int zIndex;

  /// Whether this overlay captures taps: a tap on it reports to [onTap]
  /// and does not reach the map's `onTap`. With no [onTap] it just blocks
  /// map taps over its area.
  final bool consumeTapEvents;

  /// Vertical placement relative to the base map's labels/roads.
  final MKOverlayLevel level;

  /// Called when the overlay is tapped; requires [consumeTapEvents] (only
  /// overlays that capture taps receive them).
  final VoidCallback? onTap;

  /// Returns a copy with the given fields replaced.
  MKPolyline copyWith({
    List<CLLocationCoordinate2D>? coordinates,
    Color? strokeColor,
    double? lineWidth,
    CGLineCap? lineCap,
    CGLineJoin? lineJoin,
    List<double>? lineDashPattern = keepDoubles,
    List<Color>? gradientColors,
    bool? isHidden,
    int? zIndex,
    bool? consumeTapEvents,
    MKOverlayLevel? level,
    VoidCallback? onTap = keepCallback,
  }) => (isGeodesic ? MKPolyline.geodesic : MKPolyline.new)(
    id: id,
    coordinates: coordinates ?? this.coordinates,
    strokeColor: strokeColor ?? this.strokeColor,
    lineWidth: lineWidth ?? this.lineWidth,
    lineCap: lineCap ?? this.lineCap,
    lineJoin: lineJoin ?? this.lineJoin,
    lineDashPattern: identical(lineDashPattern, keepDoubles)
        ? this.lineDashPattern
        : lineDashPattern,
    gradientColors: gradientColors ?? this.gradientColors,
    isHidden: isHidden ?? this.isHidden,
    zIndex: zIndex ?? this.zIndex,
    consumeTapEvents: consumeTapEvents ?? this.consumeTapEvents,
    level: level ?? this.level,
    onTap: identical(onTap, keepCallback) ? this.onTap : onTap,
  );

  /// Converts this polyline to its Pigeon wire representation.
  @internal
  PlatformPolyline toPlatform() => .new(
    id: id.value,
    coordinates: coordinates.map((c) => c.toPlatform()).toList(),
    strokeColorArgb: strokeColor.toARGB32(),
    lineWidth: lineWidth,
    lineCap: lineCap,
    lineJoin: lineJoin,
    isHidden: isHidden,
    consumeTapEvents: consumeTapEvents,
    isGeodesic: isGeodesic,
    level: level,
    zIndex: zIndex,
    lineDashPattern: lineDashPattern,
    gradientColorsArgb: gradientColors.isEmpty
        ? null
        : gradientColors.map((c) => c.toARGB32()).toList(),
  );

  @override
  bool operator ==(Object other) =>
      other is MKPolyline &&
      other.id == id &&
      listEquals(other.coordinates, coordinates) &&
      other.isGeodesic == isGeodesic &&
      other.strokeColor == strokeColor &&
      other.lineWidth == lineWidth &&
      other.lineCap == lineCap &&
      other.lineJoin == lineJoin &&
      listEquals(other.lineDashPattern, lineDashPattern) &&
      listEquals(other.gradientColors, gradientColors) &&
      other.isHidden == isHidden &&
      other.zIndex == zIndex &&
      other.consumeTapEvents == consumeTapEvents &&
      other.level == level;

  @override
  int get hashCode => Object.hash(
    id,
    .hashAll(coordinates),
    isGeodesic,
    strokeColor,
    lineWidth,
    lineCap,
    lineJoin,
    .hashAll(lineDashPattern ?? const []),
    .hashAll(gradientColors),
    isHidden,
    zIndex,
    consumeTapEvents,
    level,
  );

  @override
  String toString() {
    final b = StringBuffer('MKPolyline(')
      ..write('id: ${id.value}, ')
      ..write('coordinates: ${coordinates.length}, ')
      ..write('lineWidth: $lineWidth, ')
      ..write('isGeodesic: $isGeodesic, ')
      ..write('isHidden: $isHidden, ')
      ..write('level: ${level.name}, ')
      ..write('onTap: ${onTap != null ? 'set' : 'null'}');
    return (b..write(')')).toString();
  }
}
