import 'package:mapkit_flutter/mapkit_flutter.dart';

/// Shared coordinates and one-liner model builders so tests don't restate
/// boilerplate.
final applePark = CLLocationCoordinate2D(
  latitude: 37.3349,
  longitude: -122.0090,
);

final infiniteLoop = CLLocationCoordinate2D(
  latitude: 37.3318,
  longitude: -122.0312,
);

final sampleCamera = MKMapCamera(centerCoordinate: applePark, distance: 1200);

final sampleRegion = MKCoordinateRegion(
  center: applePark,
  span: .new(latitudeDelta: 0.05, longitudeDelta: 0.05),
);

MKPointAnnotation annotation(
  String id, {
  CLLocationCoordinate2D? coordinate,
  String? title,
}) => .new(id: .new(id), coordinate: coordinate ?? applePark, title: title);

MKPolyline polyline(String id, {List<CLLocationCoordinate2D>? coordinates}) =>
    .new(id: .new(id), coordinates: coordinates ?? [applePark, infiniteLoop]);

MKPolygon polygon(String id, {List<CLLocationCoordinate2D>? coordinates}) =>
    .new(
      id: .new(id),
      coordinates:
          coordinates ??
          [
            .new(latitude: 0, longitude: 0),
            .new(latitude: 0, longitude: 1),
            .new(latitude: 1, longitude: 1),
          ],
    );

MKCircle circle(String id, {double radius = 500}) =>
    .new(id: .new(id), center: applePark, radius: radius);
