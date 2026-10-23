import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

void main() {
  group('MapItemId', () {
    test('equal value and type compare equal', () {
      const a = MKAnnotationId('a');
      check(a).equals(const .new('a'));
      check(a.hashCode).equals(const MKAnnotationId('a').hashCode);
    });

    test('phantom type keeps ids of different kinds apart', () {
      const Object annotation = MKAnnotationId('same');
      const Object polyline = MKPolylineId('same');
      const Object circle = MKCircleId('same');
      check(annotation == polyline).isFalse();
      check(polyline == circle).isFalse();
    });

    test('different values compare unequal', () {
      check(const MKPolylineId('a') == const MKPolylineId('b')).isFalse();
    });
  });
}
