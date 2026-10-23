import 'package:flutter/foundation.dart';
import 'package:mapkit_flutter/src/_internal/validate.dart';
import 'package:mapkit_flutter/src/messages.g.dart';
import 'package:meta/meta.dart';

/// The width and height of a map region in degrees, mirroring
/// `MKCoordinateSpan(latitudeDelta:longitudeDelta:)`.
/// See: https://developer.apple.com/documentation/mapkit/mkcoordinatespan
@immutable
final class MKCoordinateSpan({
  /// North-to-south span in degrees in `[0, 180]`.
  required final double latitudeDelta,

  /// East-to-west span in degrees in `[0, 360]`.
  required final double longitudeDelta,
}) {
  /// Creates a coordinate span with [latitudeDelta] in `[0, 180]` and
  /// [longitudeDelta] in `[0, 360]`; throws [ArgumentError] otherwise.
  this {
    checkInRange(latitudeDelta, 0, 180, 'latitudeDelta');
    checkInRange(longitudeDelta, 0, 360, 'longitudeDelta');
  }

  /// Constructs a coordinate span from its Pigeon wire representation.
  @internal
  factory fromPlatform(PlatformCoordinateSpan p) =>
      .new(latitudeDelta: p.latitudeDelta, longitudeDelta: p.longitudeDelta);

  /// Converts this coordinate span to its Pigeon wire representation.
  @internal
  PlatformCoordinateSpan toPlatform() =>
      .new(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta);

  @override
  bool operator ==(Object other) =>
      other is MKCoordinateSpan &&
      other.latitudeDelta == latitudeDelta &&
      other.longitudeDelta == longitudeDelta;

  @override
  int get hashCode => Object.hash(latitudeDelta, longitudeDelta);

  @override
  String toString() => 'MKCoordinateSpan($latitudeDelta, $longitudeDelta)';
}
