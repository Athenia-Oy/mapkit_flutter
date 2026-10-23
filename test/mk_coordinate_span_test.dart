import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

void main() {
  group('MKCoordinateSpan', () {
    test('equality is value-based', () {
      final a = MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 2);
      final b = MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 2);
      check(a).equals(b);
      check(a.hashCode).equals(b.hashCode);
    });

    test('rejects out-of-range or non-finite deltas', () {
      MKCoordinateSpan span(double lat, double lng) =>
          .new(latitudeDelta: lat, longitudeDelta: lng);
      check(() => span(-1, 0)).throws<ArgumentError>();
      check(() => span(0, -1)).throws<ArgumentError>();
      check(() => span(180.1, 0)).throws<ArgumentError>();
      check(() => span(0, 360.1)).throws<ArgumentError>();
      check(() => span(.nan, 0)).throws<ArgumentError>();
      check(() => span(0, .infinity)).throws<ArgumentError>();
    });

    test('round-trips through the platform type', () {
      final original = MKCoordinateSpan(
        latitudeDelta: 1.5,
        longitudeDelta: 2.5,
      );
      final platform = original.toPlatform();
      check(platform.latitudeDelta).equals(1.5);
      check(platform.longitudeDelta).equals(2.5);
      check(MKCoordinateSpan.fromPlatform(platform)).equals(original);
    });

    test('toString representation', () {
      final span = MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 3.4);
      check(span.toString()).equals('MKCoordinateSpan(1.2, 3.4)');
    });
  });
}
