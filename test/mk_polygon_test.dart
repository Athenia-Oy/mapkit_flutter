import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

import '_helpers/fixtures.dart';

void main() {
  group('MKPolygon wire mapping', () {
    test('serializes interior polygons ring by ring', () {
      final platform = MKPolygon(
        id: const .new('zone'),
        coordinates: [
          .new(latitude: 0, longitude: 0),
          .new(latitude: 0, longitude: 10),
          .new(latitude: 10, longitude: 10),
        ],
        interiorPolygons: [
          [
            .new(latitude: 2, longitude: 2),
            .new(latitude: 2, longitude: 4),
            .new(latitude: 4, longitude: 4),
          ],
        ],
        fillColor: const .new(0x6600FF00),
        strokeColor: const .new(0xFF112233),
        lineWidth: 3,
      ).toPlatform();

      check(platform.id).equals('zone');
      check(platform.coordinates).length.equals(3);
      check(platform.interiorPolygons).length.equals(1);
      check(platform.interiorPolygons.single).length.equals(3);
      check(platform.fillColorArgb).equals(0x6600FF00);
      check(platform.strokeColorArgb).equals(0xFF112233);
      check(platform.lineWidth).equals(3);
      check(platform.isHidden).isFalse();
    });

    test('rejects negative or non-finite lineWidth', () {
      for (final bad in <double>[-1, .nan, .infinity]) {
        check(
          () => MKPolygon(
            id: const .new('bad'),
            coordinates: [applePark, infiniteLoop],
            lineWidth: bad,
          ),
        ).throws<ArgumentError>();
      }
    });
  });

  group('equality', () {
    test('compares rings by content', () {
      check(polygon('z')).equals(polygon('z'));
      check(polygon('z').hashCode).equals(polygon('z').hashCode);
      check(
        polygon('z') ==
            polygon('z').copyWith(
              interiorPolygons: [
                [
                  .new(latitude: 1, longitude: 1),
                  .new(latitude: 1, longitude: 2),
                  .new(latitude: 2, longitude: 2),
                ],
              ],
            ),
      ).isFalse();
    });
  });

  group('caller-owned lists', () {
    test('snapshots outer and interior rings, so a later mutation is a new '
        'value', () {
      final outer = [
        CLLocationCoordinate2D(latitude: 0, longitude: 0),
        CLLocationCoordinate2D(latitude: 0, longitude: 10),
        CLLocationCoordinate2D(latitude: 10, longitude: 10),
      ];
      final hole = [
        CLLocationCoordinate2D(latitude: 2, longitude: 2),
        CLLocationCoordinate2D(latitude: 2, longitude: 4),
        CLLocationCoordinate2D(latitude: 4, longitude: 4),
      ];
      final holes = [hole];
      MKPolygon build() => .new(
        id: const .new('zone'),
        coordinates: outer,
        interiorPolygons: holes,
      );
      final before = build();

      outer.add(applePark);
      hole.add(applePark);
      holes.add([applePark, infiniteLoop, applePark]);

      check(before.coordinates).length.equals(3);
      check(before.interiorPolygons).length.equals(1);
      check(before.interiorPolygons.single).length.equals(3);
      check(before == build()).isFalse();
      check(() => before.coordinates.add(applePark)).throws<UnsupportedError>();
      check(() => before.interiorPolygons.add([])).throws<UnsupportedError>();
      check(() => before.interiorPolygons.single.add(applePark))
          .throws<UnsupportedError>();
    });

    test('a mutated inner ring alone is a new value', () {
      final hole = [applePark, infiniteLoop, applePark];
      MKPolygon build() => .new(
        id: const .new('zone'),
        coordinates: [applePark, infiniteLoop, applePark],
        interiorPolygons: [hole],
      );
      final before = build();
      hole.add(infiniteLoop);
      check(before == build()).isFalse();
    });
  });

  group('tap consumption', () {
    test('consumeTapEvents is explicit on the wire', () {
      check(polygon('x').toPlatform().consumeTapEvents).isFalse();
      final capturing = polygon('x').copyWith(consumeTapEvents: true);
      check(capturing.toPlatform().consumeTapEvents).isTrue();
      check(capturing.copyWith(onTap: () {}).toPlatform().consumeTapEvents)
          .isTrue();
    });

    test('onTap without consumeTapEvents throws instead of never firing', () {
      check(() => polygon('x').copyWith(onTap: () {})).throws<ArgumentError>();
      final tappable = polygon('x')
          .copyWith(consumeTapEvents: true, onTap: () {});
      check(() => tappable.copyWith(consumeTapEvents: false))
          .throws<ArgumentError>();
    });

    test('clearing onTap keeps the overlay equal (closures are not state)', () {
      final tappable = polygon('x')
          .copyWith(consumeTapEvents: true, onTap: () {});
      check(tappable.copyWith(onTap: null)).equals(tappable);
    });
  });
}
