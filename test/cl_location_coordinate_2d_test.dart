import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

void main() {
  group('CLLocationCoordinate2D', () {
    test('equality is value-based', () {
      final a = CLLocationCoordinate2D(latitude: 10, longitude: 20);
      final b = CLLocationCoordinate2D(latitude: 10, longitude: 20);
      check(a).equals(b);
      check(a.hashCode).equals(b.hashCode);
    });

    test('rejects latitude outside [-90, 90] instead of clamping', () {
      // Swapped arguments (Tokyo as lat 139.69 / lng 35.68) must fail loudly,
      // not land on the North Pole.
      check(() => CLLocationCoordinate2D(latitude: 139.69, longitude: 35.68))
          .throws<ArgumentError>();
      check(() => CLLocationCoordinate2D(latitude: -90.0001, longitude: 0))
          .throws<ArgumentError>();
      check(CLLocationCoordinate2D(latitude: 90, longitude: 0).latitude)
          .equals(90);
      check(CLLocationCoordinate2D(latitude: -90, longitude: 0).latitude)
          .equals(-90);
    });

    test('wraps longitude to [-180, 180)', () {
      final at190 = CLLocationCoordinate2D(latitude: 0, longitude: 190);
      final atNeg190 = CLLocationCoordinate2D(latitude: 0, longitude: -190);
      final at180 = CLLocationCoordinate2D(latitude: 0, longitude: 180);
      final at540 = CLLocationCoordinate2D(latitude: 0, longitude: 540);
      final atSubNeg180 = CLLocationCoordinate2D(
        latitude: 0,
        longitude: -180.00000000000003,
      );
      check(at190.longitude).equals(-170);
      check(atNeg190.longitude).equals(170);
      check(at180.longitude).equals(-180);
      check(at540.longitude).equals(-180);
      check(atSubNeg180.longitude).equals(-180);
      check(atSubNeg180.longitude).isLessThan(180);
    });

    test('rejects non-finite coordinates', () {
      for (final bad in <double>[.nan, .infinity, .negativeInfinity]) {
        check(() => CLLocationCoordinate2D(latitude: bad, longitude: 0))
            .throws<ArgumentError>();
        check(() => CLLocationCoordinate2D(latitude: 0, longitude: bad))
            .throws<ArgumentError>();
      }
    });

    test('round-trips through the platform type', () {
      final original = CLLocationCoordinate2D(latitude: 37.5, longitude: -122);
      final platform = original.toPlatform();
      check(platform.latitude).equals(37.5);
      check(platform.longitude).equals(-122);
      check(CLLocationCoordinate2D.fromPlatform(platform)).equals(original);
    });

    test('Coordinate is an alias for the full Apple symbol', () {
      final alias = CLLocationCoordinate2D(latitude: 1, longitude: 2);
      final expected = CLLocationCoordinate2D(latitude: 1, longitude: 2);
      check(alias).equals(expected);
    });
  });
}
