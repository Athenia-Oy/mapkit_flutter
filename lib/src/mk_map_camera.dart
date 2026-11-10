import 'dart:math' show log, pow;

import 'package:flutter/foundation.dart';
import 'package:mapkit_flutter/src/_internal/validate.dart';
import 'package:mapkit_flutter/src/cl_location_coordinate_2d.dart';
import 'package:mapkit_flutter/src/messages.g.dart';
import 'package:meta/meta.dart';

/// The map's point of view, mirroring `MKMapCamera`: the camera looks at
/// [centerCoordinate] from [distance] meters (`centerCoordinateDistance`),
/// rotated to the compass [heading] and tilted by [pitch] degrees.
/// See: https://developer.apple.com/documentation/mapkit/mkmapcamera
@immutable
final class MKMapCamera({
  /// Ground coordinate at the center of the viewport.
  required final CLLocationCoordinate2D centerCoordinate,

  /// `MKMapCamera.centerCoordinateDistance` — meters between the camera and
  /// [centerCoordinate].
  required final double distance,

  /// Compass heading in degrees (0 = north).
  final double heading = 0.0,

  /// Tilt in degrees, in `[0, 90)` (0 = looking straight down).
  ///
  /// MapKit caps the tilt it actually shows by zoom level, and imagery maps
  /// stay flat, so reading the camera back can report less than you set.
  final double pitch = 0.0,
}) {
  /// Creates a camera looking at [centerCoordinate] from [distance] meters.
  ///
  /// Throws [ArgumentError] unless [distance] is a finite value `> 0`,
  /// [heading] is finite and [pitch] is in `[0, 90)`: MapKit resets a pitch of
  /// 90 or more to 0 and mirrors a negative one.
  this {
    if (!(distance > 0 && distance.isFinite)) {
      throw ArgumentError.value(
        distance,
        'distance',
        'must be a finite value > 0 meters',
      );
    }
    checkFinite(heading, 'heading');
    if (!(pitch >= 0 && pitch < 90)) {
      throw ArgumentError.value(pitch, 'pitch', 'must be in [0, 90) degrees');
    }
  }

  /// Constructs a camera from its Pigeon wire representation.
  @internal
  factory fromPlatform(PlatformMapCamera p) => .new(
    centerCoordinate: .fromPlatform(p.centerCoordinate),
    distance: p.distance,
    heading: p.heading,
    pitch: p.pitch,
  );

  /// Camera at the Web-Mercator [zoomLevel] familiar from tile-based SDKs.
  ///
  /// The conversion `distance = 591657550.5 / 2^(zoomLevel - 1)` is the
  /// de-facto standard approximation — it ignores latitude and viewport size,
  /// so treat zoom levels as a convenience, not an exact MapKit concept.
  factory withZoomLevel({
    required CLLocationCoordinate2D centerCoordinate,
    required double zoomLevel,
    double heading = 0.0,
    double pitch = 0.0,
  }) => .new(
    centerCoordinate: centerCoordinate,
    distance: _zoomBaseDistance / pow(2.0, zoomLevel - 1),
    heading: heading,
    pitch: pitch,
  );

  /// Approximate Web-Mercator zoom level for [distance] — the inverse of
  /// [MKMapCamera.withZoomLevel], with the same caveats.
  double get zoomLevel => _log2(_zoomBaseDistance / distance) + 1;

  static const double _zoomBaseDistance = 591657550.5;

  static double _log2(double x) => log(x) / 0.6931471805599453;

  /// Returns a copy with the given fields replaced.
  MKMapCamera copyWith({
    CLLocationCoordinate2D? centerCoordinate,
    double? distance,
    double? heading,
    double? pitch,
  }) => .new(
    centerCoordinate: centerCoordinate ?? this.centerCoordinate,
    distance: distance ?? this.distance,
    heading: heading ?? this.heading,
    pitch: pitch ?? this.pitch,
  );

  /// Converts this camera to its Pigeon wire representation.
  @internal
  PlatformMapCamera toPlatform() => .new(
    centerCoordinate: centerCoordinate.toPlatform(),
    distance: distance,
    heading: heading,
    pitch: pitch,
  );

  @override
  bool operator ==(Object other) =>
      other is MKMapCamera &&
      other.centerCoordinate == centerCoordinate &&
      other.distance == distance &&
      other.heading == heading &&
      other.pitch == pitch;

  @override
  int get hashCode => Object.hash(centerCoordinate, distance, heading, pitch);

  @override
  String toString() =>
      'MKMapCamera(centerCoordinate: $centerCoordinate, distance: $distance, '
      'heading: $heading, pitch: $pitch)';
}
