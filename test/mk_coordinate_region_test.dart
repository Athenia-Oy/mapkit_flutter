import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

void main() {
  group('MKCoordinateRegion.containing', () {
    test('returns null for no coordinates', () {
      check(MKCoordinateRegion.containing(const [])).isNull();
    });

    test('single coordinate yields a zero span centered on it', () {
      final point = CLLocationCoordinate2D(latitude: 10, longitude: 20);
      final region = MKCoordinateRegion.containing([point]);
      final zeroSpan = MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0);
      check(region).isNotNull()
        ..has((r) => r.center, 'center').equals(point)
        ..has((r) => r.span, 'span').equals(zeroSpan);
    });

    test('spans the extremes with the midpoint as center', () {
      final region = MKCoordinateRegion.containing([
        .new(latitude: 10, longitude: 20),
        .new(latitude: 30, longitude: 40),
        .new(latitude: 15, longitude: 25),
      ]);
      final mid = CLLocationCoordinate2D(latitude: 20, longitude: 30);
      check(region).isNotNull()
        ..has((r) => r.center, 'center').equals(mid)
        ..has(
          (r) => r.span,
          'span',
        ).equals(.new(latitudeDelta: 20, longitudeDelta: 20));
    });
  });

  group('MKCoordinateRegion.contains', () {
    final region = MKCoordinateRegion(
      center: .new(latitude: 10, longitude: 20),
      span: .new(latitudeDelta: 4, longitudeDelta: 6),
    );

    test('accepts the center and edge coordinates', () {
      check(region.contains(.new(latitude: 10, longitude: 20))).isTrue();
      check(region.contains(.new(latitude: 12, longitude: 23))).isTrue();
    });

    test('rejects coordinates past either delta', () {
      check(region.contains(.new(latitude: 12.1, longitude: 20))).isFalse();
      check(region.contains(.new(latitude: 10, longitude: 23.1))).isFalse();
    });

    test('handles regions spanning the antimeridian', () {
      final wrapped = MKCoordinateRegion(
        center: .new(latitude: 0, longitude: 179.5),
        span: .new(latitudeDelta: 10, longitudeDelta: 2),
      );
      check(wrapped.contains(.new(latitude: 0, longitude: -179.8))).isTrue();
      check(wrapped.contains(.new(latitude: 0, longitude: 178))).isFalse();
    });
  });

  group('MKCoordinateRegion wire format', () {
    test('round-trips through the platform type', () {
      final region = MKCoordinateRegion(
        center: .new(latitude: 10, longitude: 20),
        span: .new(latitudeDelta: 1, longitudeDelta: 2),
      );
      final platform = region.toPlatform();
      check(platform.center.latitude).equals(10);
      check(platform.span.longitudeDelta).equals(2);
      check(MKCoordinateRegion.fromPlatform(platform)).equals(region);
    });
  });
}
