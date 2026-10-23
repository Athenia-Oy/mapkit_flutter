import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';
import 'package:mapkit_flutter/src/messages.g.dart';

void main() {
  test('MKMapFeature.fromPlatform maps fields and supports equality', () {
    final wire = PlatformMapFeature(
      featureType: .pointOfInterest,
      coordinate: .new(latitude: 37.3346, longitude: -122.009),
      title: 'Apple Park',
      pointOfInterestCategory: .park,
    );

    final feature = MKMapFeature.fromPlatform(wire);

    check(feature).equals(
      .new(
        featureType: .pointOfInterest,
        coordinate: .new(latitude: 37.3346, longitude: -122.009),
        title: 'Apple Park',
        pointOfInterestCategory: .park,
      ),
    );
    check(feature.hashCode).equals(
      MKMapFeature(
        featureType: .pointOfInterest,
        coordinate: .new(latitude: 37.3346, longitude: -122.009),
        title: 'Apple Park',
        pointOfInterestCategory: .park,
      ).hashCode,
    );
    check(
      feature ==
          .new(
            featureType: .territory,
            coordinate: .new(latitude: 37.3346, longitude: -122.009),
          ),
    ).isFalse();
    check(feature.toString()).equals(
      'MKMapFeature(featureType: pointOfInterest, '
      'coordinate: CLLocationCoordinate2D(37.3346, -122.009), '
      'title: Apple Park, pointOfInterestCategory: park)',
    );
  });
}
