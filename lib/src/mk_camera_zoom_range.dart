import 'package:flutter/foundation.dart';
import 'package:mapkit_flutter/src/_internal/validate.dart';
import 'package:mapkit_flutter/src/messages.g.dart';
import 'package:meta/meta.dart';

/// Limits how close and how far the camera can get, mirroring
/// `MKMapView.CameraZoomRange` — both bounds are camera distances in meters
/// (`centerCoordinateDistance`), not tile zoom levels.
///
/// `MKCameraZoomRange()` (or [MKCameraZoomRange.unbounded]) leaves both ends
/// unbounded.
/// See: https://developer.apple.com/documentation/mapkit/mkmapview/camerazoomrange
@immutable
final class MKCameraZoomRange {
  /// Creates a camera zoom range with optional minimum and maximum center
  /// distances in meters.
  ///
  /// Throws [ArgumentError] for a negative or non-finite distance, or a
  /// minimum above the maximum.
  new({this.minCenterCoordinateDistance, this.maxCenterCoordinateDistance}) {
    if (minCenterCoordinateDistance case final min?) {
      checkNonNegative(min, 'minCenterCoordinateDistance');
    }
    if (maxCenterCoordinateDistance case final max?) {
      checkNonNegative(max, 'maxCenterCoordinateDistance');
    }
    if ((minCenterCoordinateDistance, maxCenterCoordinateDistance)
        case (final min?, final max?) when min > max) {
      throw ArgumentError(
        'minCenterCoordinateDistance ($min) must be <= '
        'maxCenterCoordinateDistance ($max)',
      );
    }
  }

  const new _unbounded()
    : minCenterCoordinateDistance = null,
      maxCenterCoordinateDistance = null;

  /// No limit at either end — MapKit's default zoom range.
  static const unbounded = MKCameraZoomRange._unbounded();

  /// Minimum camera center-coordinate distance in meters, or `null` if
  /// unbounded.
  final double? minCenterCoordinateDistance;

  /// Maximum camera center-coordinate distance in meters, or `null` if
  /// unbounded.
  final double? maxCenterCoordinateDistance;

  /// Converts this zoom range to its Pigeon wire representation.
  @internal
  PlatformCameraZoomRange toPlatform() => .new(
    minCenterCoordinateDistance: minCenterCoordinateDistance,
    maxCenterCoordinateDistance: maxCenterCoordinateDistance,
  );

  @override
  bool operator ==(Object other) =>
      other is MKCameraZoomRange &&
      other.minCenterCoordinateDistance == minCenterCoordinateDistance &&
      other.maxCenterCoordinateDistance == maxCenterCoordinateDistance;

  @override
  int get hashCode =>
      Object.hash(minCenterCoordinateDistance, maxCenterCoordinateDistance);

  @override
  String toString() =>
      'MKCameraZoomRange(min: $minCenterCoordinateDistance, '
      'max: $maxCenterCoordinateDistance)';
}
