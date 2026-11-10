import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

import '_helpers/fixtures.dart';

void main() {
  group('MKCircle wire mapping', () {
    test('serializes renderer vocabulary', () {
      final platform = MKCircle(
        id: const .new('radius'),
        center: applePark,
        radius: 750,
        fillColor: const .new(0x3300FF00),
        strokeColor: const .new(0xFF112233),
        lineWidth: 2,
        zIndex: 1,
      ).toPlatform();

      check(platform.id).equals('radius');
      check(platform.center.latitude).equals(applePark.latitude);
      check(platform.radius).equals(750);
      check(platform.fillColorArgb).equals(0x3300FF00);
      check(platform.strokeColorArgb).equals(0xFF112233);
      check(platform.lineWidth).equals(2);
      check(platform.zIndex).equals(1);
      check(platform.isHidden).isFalse();
    });

    test('rejects negative or non-finite radius and lineWidth', () {
      for (final bad in <double>[-1, .nan, .infinity]) {
        check(
          () => MKCircle(id: const .new('bad'), center: applePark, radius: bad),
        ).throws<ArgumentError>();
        check(
          () => MKCircle(
            id: const .new('bad'),
            center: applePark,
            radius: 100,
            lineWidth: bad,
          ),
        ).throws<ArgumentError>();
      }
    });
  });

  group('equality', () {
    test('compares by value, ignoring onTap', () {
      check(circle('c')).equals(circle('c'));
      check(circle('c').hashCode).equals(circle('c').hashCode);
      check(circle('c') == circle('c', radius: 1)).isFalse();
    });
  });

  group('tap consumption', () {
    test('consumeTapEvents is explicit on the wire', () {
      check(circle('x').toPlatform().consumeTapEvents).isFalse();
      final capturing = circle('x').copyWith(consumeTapEvents: true);
      check(capturing.toPlatform().consumeTapEvents).isTrue();
      check(capturing.copyWith(onTap: () {}).toPlatform().consumeTapEvents)
          .isTrue();
    });

    test('onTap without consumeTapEvents throws instead of never firing', () {
      check(() => circle('x').copyWith(onTap: () {})).throws<ArgumentError>();
      final tappable = circle('x')
          .copyWith(consumeTapEvents: true, onTap: () {});
      check(() => tappable.copyWith(consumeTapEvents: false))
          .throws<ArgumentError>();
    });

    test('clearing onTap keeps the overlay equal (closures are not state)', () {
      final tappable = circle('x')
          .copyWith(consumeTapEvents: true, onTap: () {});
      check(tappable.copyWith(onTap: null)).equals(tappable);
    });
  });
}
