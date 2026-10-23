import 'dart:ui' show Color;

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

import '_helpers/fixtures.dart';

void main() {
  group('MKPolyline wire mapping', () {
    test('serializes renderer vocabulary', () {
      final platform = MKPolyline(
        id: const .new('route'),
        coordinates: [applePark, infiniteLoop],
        strokeColor: const .new(0xFF0000FF),
        lineWidth: 4,
        lineCap: .butt,
        lineJoin: .miter,
        lineDashPattern: const [6, 3],
        zIndex: 2,
        level: .aboveLabels,
        consumeTapEvents: true,
      ).toPlatform();

      check(platform.id).equals('route');
      check(platform.coordinates).length.equals(2);
      check(platform.strokeColorArgb).equals(0xFF0000FF);
      check(platform.lineWidth).equals(4);
      check(platform.lineCap).equals(.butt);
      check(platform.lineJoin).equals(.miter);
      check(platform.lineDashPattern).isNotNull().deepEquals([6, 3]);
      check(platform.zIndex).equals(2);
      check(platform.level).equals(.aboveLabels);
      check(platform.consumeTapEvents).isTrue();
      check(platform.isGeodesic).isFalse();
      check(platform.isHidden).isFalse();
    });

    test('defaults mirror MKOverlayPathRenderer', () {
      final platform = polyline('p').toPlatform();
      check(platform.lineCap).equals(.round);
      check(platform.lineJoin).equals(.round);
      check(platform.lineDashPattern).isNull();
      check(platform.gradientColorsArgb).isNull();
    });

    test('gradient colors serialize as ARGB32 when present', () {
      final platform = MKPolyline(
        id: const .new('g'),
        coordinates: [applePark, infiniteLoop],
        gradientColors: const [.new(0xFFFF0000), .new(0xFF00FF00)],
      ).toPlatform();
      check(platform.gradientColorsArgb)
          .isNotNull()
          .deepEquals([0xFFFF0000, 0xFF00FF00]);
    });

    test('rejects a single gradient color', () {
      check(
        () => MKPolyline(
          id: const .new('one'),
          coordinates: [applePark, infiniteLoop],
          gradientColors: const [.new(0xFFFF0000)],
        ),
      ).throws<ArgumentError>();
      check(
        () => MKPolyline.geodesic(
          id: const .new('one'),
          coordinates: [applePark, infiniteLoop],
          gradientColors: const [.new(0xFFFF0000)],
        ),
      ).throws<ArgumentError>();
    });

    test('rejects negative or non-finite lineWidth', () {
      for (final bad in [-1.0, double.nan, double.infinity]) {
        check(
          () => MKPolyline(
            id: const .new('bad'),
            coordinates: [applePark, infiniteLoop],
            lineWidth: bad,
          ),
        ).throws<ArgumentError>();
        check(
          () => MKPolyline.geodesic(
            id: const .new('bad'),
            coordinates: [applePark, infiniteLoop],
            lineWidth: bad,
          ),
        ).throws<ArgumentError>();
      }
    });
  });

  group('lineDashPattern', () {
    for (final bad in <List<double>>[
      [0],
      [0, 0],
      [-1, 3],
      [6, .nan],
      [.infinity, 3],
    ]) {
      test('rejects $bad on both constructors', () {
        for (final create in [MKPolyline.new, MKPolyline.geodesic]) {
          check(
                () => create(
                  id: const .new('dash'),
                  coordinates: [applePark, infiniteLoop],
                  lineDashPattern: bad,
                ),
              )
              .throws<ArgumentError>()
              .has((e) => e.name, 'name')
              .equals('lineDashPattern');
        }
      });
    }

    test('copyWith rejects an all-zero pattern', () {
      check(() => polyline('p').copyWith(lineDashPattern: const [0, 0]))
          .throws<ArgumentError>();
    });

    test('accepts a dotted pattern with zero-length dashes', () {
      check(
        polyline('p').copyWith(lineDashPattern: const [0, 15]).lineDashPattern,
      ).isNotNull().deepEquals([0, 15]);
    });
  });

  group('MKPolyline.geodesic', () {
    test('flags the wire payload without mutating coordinates', () {
      final platform = MKPolyline.geodesic(
        id: const .new('arc'),
        coordinates: [applePark, infiniteLoop],
      ).toPlatform();
      check(platform.isGeodesic).isTrue();
      check(platform.coordinates).length.equals(2);
    });

    test('copyWith preserves geodesic-ness', () {
      final arc = MKPolyline.geodesic(
        id: const .new('arc'),
        coordinates: [applePark, infiniteLoop],
      );
      check(arc.copyWith(lineWidth: 2).isGeodesic).isTrue();
      check(polyline('p').copyWith(lineWidth: 2).isGeodesic).isFalse();
    });

    test('straight and geodesic lines compare unequal', () {
      final straight = polyline('p');
      final arc = MKPolyline.geodesic(
        id: const .new('p'),
        coordinates: [applePark, infiniteLoop],
      );
      check(straight == arc).isFalse();
    });
  });

  group('equality', () {
    test('compares coordinates and dash pattern by content', () {
      check(
        MKPolyline(
          id: const .new('p'),
          coordinates: [applePark],
          lineDashPattern: const [1, 2],
        ),
      ).equals(
        .new(
          id: const .new('p'),
          coordinates: [applePark],
          lineDashPattern: const [1, 2],
        ),
      );
      final dashed = polyline('p').copyWith(lineDashPattern: const [1]);
      check(polyline('p') == dashed).isFalse();
    });
  });

  group('caller-owned lists', () {
    for (final (name, make) in [
      ('MKPolyline', MKPolyline.new),
      ('MKPolyline.geodesic', MKPolyline.geodesic),
    ]) {
      test('$name snapshots its lists, so a later mutation is a new value', () {
        final coordinates = [applePark, infiniteLoop];
        final dashes = <double>[6, 3];
        final colors = <Color>[const .new(0xFF000000), const .new(0xFFFFFFFF)];
        MKPolyline build() => make(
          id: const .new('p'),
          coordinates: coordinates,
          lineDashPattern: dashes,
          gradientColors: colors,
        );
        final before = build();

        coordinates.add(applePark);
        dashes.add(1);
        colors.add(const .new(0xFFFF0000));

        check(before.coordinates).length.equals(2);
        check(before.lineDashPattern).isNotNull().length.equals(2);
        check(before.gradientColors).length.equals(2);
        check(before == build()).isFalse();
        check(() => before.coordinates.add(applePark))
            .throws<UnsupportedError>();
        check(() => before.lineDashPattern?.add(1)).throws<UnsupportedError>();
        check(before.gradientColors.clear).throws<UnsupportedError>();
      });
    }
  });

  group('tap consumption', () {
    test('consumeTapEvents is explicit on the wire', () {
      check(polyline('x').toPlatform().consumeTapEvents).isFalse();
      final capturing = polyline('x').copyWith(consumeTapEvents: true);
      check(capturing.toPlatform().consumeTapEvents).isTrue();
      check(capturing.copyWith(onTap: () {}).toPlatform().consumeTapEvents)
          .isTrue();
    });

    test('onTap without consumeTapEvents throws instead of never firing', () {
      check(() => polyline('x').copyWith(onTap: () {})).throws<ArgumentError>();
      final tappable = polyline('x')
          .copyWith(consumeTapEvents: true, onTap: () {});
      check(() => tappable.copyWith(consumeTapEvents: false))
          .throws<ArgumentError>();
    });

    test('clearing onTap keeps the overlay equal (closures are not state)', () {
      final tappable = polyline('x')
          .copyWith(consumeTapEvents: true, onTap: () {});
      check(tappable.copyWith(onTap: null)).equals(tappable);
    });
  });
}
