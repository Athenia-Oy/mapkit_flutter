import 'package:flutter/foundation.dart';
import 'package:mapkit_flutter/src/cl_location_coordinate_2d.dart';
import 'package:mapkit_flutter/src/messages.g.dart';
import 'package:mapkit_flutter/src/mk_enums.dart';
import 'package:meta/meta.dart';

/// A map feature the user selected — a point of interest, territory or
/// physical feature — mirroring `MKMapFeatureAnnotation`. iOS only.
/// See: https://developer.apple.com/documentation/mapkit/mkmapfeatureannotation
@immutable
final class const MKMapFeature({
  /// `MKMapFeatureAnnotation.featureType`.
  required final MKMapFeatureType featureType,

  /// `MKMapFeatureAnnotation.coordinate`.
  required final CLLocationCoordinate2D coordinate,

  /// `MKMapFeatureAnnotation.title`.
  final String? title,

  /// `MKMapFeatureAnnotation.pointOfInterestCategory`; `null` for a
  /// territory, a physical feature or a category this package doesn't know.
  final MKPointOfInterestCategory? pointOfInterestCategory,
}) {
  /// Creates a selected map feature description.
  this;

  /// Constructs a map feature from its Pigeon wire representation.
  @internal
  factory fromPlatform(PlatformMapFeature p) => .new(
    featureType: p.featureType,
    coordinate: .fromPlatform(p.coordinate),
    title: p.title,
    pointOfInterestCategory: p.pointOfInterestCategory,
  );

  @override
  bool operator ==(Object other) =>
      other is MKMapFeature &&
      other.featureType == featureType &&
      other.coordinate == coordinate &&
      other.title == title &&
      other.pointOfInterestCategory == pointOfInterestCategory;

  @override
  int get hashCode =>
      Object.hash(featureType, coordinate, title, pointOfInterestCategory);

  @override
  String toString() =>
      'MKMapFeature(featureType: ${featureType.name}, '
      'coordinate: $coordinate, title: $title, '
      'pointOfInterestCategory: ${pointOfInterestCategory?.name})';
}
