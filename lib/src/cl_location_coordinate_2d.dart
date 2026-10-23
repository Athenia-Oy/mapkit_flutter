import 'package:flutter/foundation.dart';
import 'package:mapkit_flutter/src/_internal/validate.dart';
import 'package:mapkit_flutter/src/messages.g.dart';
import 'package:meta/meta.dart';

/// Shorthand alias for [CLLocationCoordinate2D]. Consumers who find the full
/// Apple symbol too long can use `Coordinate`; mixed-SDK files can `hide` it.
typedef Coordinate = CLLocationCoordinate2D;

/// A geographic latitude/longitude pair in degrees, mirroring Core Location's
/// `CLLocationCoordinate2D(latitude:longitude:)`.
///
/// Latitude must lie in `[-90, 90]`; longitude is wrapped to `[-180, 180)`
/// (180° east normalizes to `-180`); in-range values are stored verbatim.
/// See: https://developer.apple.com/documentation/corelocation/cllocationcoordinate2d
@immutable
final class CLLocationCoordinate2D {
  /// Creates a coordinate, wrapping [longitude] into `[-180, 180)`.
  ///
  /// Throws [ArgumentError] when [latitude] is outside `[-90, 90]` or either
  /// value is not finite — swapped arguments fail here instead of landing on
  /// a pole.
  new({required double latitude, required double longitude})
    : latitude = _checkLatitude(latitude),
      longitude = _wrapLongitude(longitude);

  /// Constructs a coordinate from its Pigeon wire representation.
  @internal
  factory fromPlatform(PlatformCoordinate p) =>
      .new(latitude: p.latitude, longitude: p.longitude);

  static double _checkLatitude(double latitude) {
    checkInRange(latitude, -90, 90, 'latitude');
    return latitude;
  }

  static double _wrapLongitude(double longitude) {
    checkFinite(longitude, 'longitude');
    if (longitude >= -180.0 && longitude < 180.0) return longitude;
    final wrapped = (longitude + 180.0) % 360.0 - 180.0;
    return wrapped >= 180.0 ? -180.0 : wrapped;
  }

  /// Latitude in degrees in `[-90, 90]`.
  final double latitude;

  /// Longitude in degrees in `[-180, 180)`.
  final double longitude;

  /// Converts this coordinate to its Pigeon wire representation.
  @internal
  PlatformCoordinate toPlatform() =>
      .new(latitude: latitude, longitude: longitude);

  @override
  bool operator ==(Object other) =>
      other is CLLocationCoordinate2D &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'CLLocationCoordinate2D($latitude, $longitude)';
}
