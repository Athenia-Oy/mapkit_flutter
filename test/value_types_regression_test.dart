// Value-type regressions: copyWith clearing nullable fields, longitude
// normalisation leaving in-range values untouched, and signed-zero equality.
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

void main() {
  final here = CLLocationCoordinate2D(latitude: 1, longitude: 2);

  group('copyWith clears nullable fields with an explicit null', () {
    test(
      'MKPointAnnotation.copyWith(clusteringIdentifier: null) un-clusters',
      () {
        final a = MKPointAnnotation(
          id: const .new('a'),
          coordinate: here,
          title: 'Title',
          clusteringIdentifier: 'shops',
        );
        final b = a.copyWith(clusteringIdentifier: null, title: null);
        check(
          because: 'cannot leave a cluster',
          b.clusteringIdentifier,
        ).isNull();
        check(because: 'cannot drop the callout title', b.title).isNull();
      },
    );

    test(
      'MKPolyline.copyWith(lineDashPattern: null) restores a solid stroke',
      () {
        final dashed = MKPolyline(
          id: const .new('p'),
          coordinates: [here, here],
          lineDashPattern: const [6, 3],
        );
        check(dashed.copyWith(lineDashPattern: null).lineDashPattern).isNull();
      },
    );
  });

  group('longitude normalisation keeps in-range values verbatim', () {
    test('an in-range longitude is stored verbatim', () {
      final c = CLLocationCoordinate2D(latitude: 0, longitude: 10.1);
      check(c.longitude).equals(10.1);
    });

    test('control: the README longitude survives verbatim', () {
      final c = CLLocationCoordinate2D(
        latitude: 37.334922,
        longitude: -122.009033,
      );
      check(c.longitude).equals(-122.009033);
    });
  });

  test('control: -0.0 and 0.0 coordinates are equal with equal hashCodes', () {
    // Signed zero is the point of this control; `-0` would be the int 0.
    // ignore: prefer_int_literals
    final a = CLLocationCoordinate2D(latitude: -0.0, longitude: -0.0);
    final b = CLLocationCoordinate2D(latitude: 0, longitude: 0);
    check(a).equals(b);
    check(a.hashCode).equals(b.hashCode);
  });
}
