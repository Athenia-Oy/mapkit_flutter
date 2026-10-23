import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

void main() {
  final osm = MKTileOverlay(
    id: const .new('osm'),
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  group('MKTileOverlay wire mapping', () {
    test('serializes MKTileOverlay vocabulary', () {
      final platform = MKTileOverlay(
        id: const .new('osm'),
        urlTemplate: 'https://t/{z}/{x}/{y}.png',
        minimumZ: 3,
        maximumZ: 17,
        tileSize: 512,
        canReplaceMapContent: true,
        alpha: 0.5,
        level: .aboveLabels,
      ).toPlatform();

      check(platform.id).equals('osm');
      check(platform.urlTemplate).equals('https://t/{z}/{x}/{y}.png');
      check(platform.minimumZ).equals(3);
      check(platform.maximumZ).equals(17);
      check(platform.tileSize).equals(512);
      check(platform.canReplaceMapContent).isTrue();
      check(platform.alpha).equals(0.5);
      check(platform.level).equals(.aboveLabels);
    });

    test('defaults mirror MKTileOverlay', () {
      final platform = osm.toPlatform();
      check(platform.minimumZ).equals(0);
      check(platform.maximumZ).equals(21);
      check(platform.tileSize).equals(256);
      check(platform.canReplaceMapContent).isFalse();
      check(platform.alpha).equals(1);
    });

    test('rejects an invalid z range or tileSize', () {
      check(
        () => MKTileOverlay(
          id: const .new('bad'),
          urlTemplate: 'https://t/{z}/{x}/{y}.png',
          minimumZ: 10,
          maximumZ: 3,
        ),
      ).throws<ArgumentError>();
      check(
        () => MKTileOverlay(
          id: const .new('bad'),
          urlTemplate: 'https://t/{z}/{x}/{y}.png',
          minimumZ: -1,
        ),
      ).throws<ArgumentError>();
      check(
        () => MKTileOverlay(
          id: const .new('bad'),
          urlTemplate: 'https://t/{z}/{x}/{y}.png',
          tileSize: 0,
        ),
      ).throws<ArgumentError>();
    });

    test('rejects out of bounds alpha values', () {
      check(
        () => MKTileOverlay(
          id: const .new('bad'),
          urlTemplate: 'https://t/{z}/{x}/{y}.png',
          alpha: -0.1,
        ),
      ).throws<ArgumentError>();

      check(
        () => MKTileOverlay(
          id: const .new('bad'),
          urlTemplate: 'https://t/{z}/{x}/{y}.png',
          alpha: 1.1,
        ),
      ).throws<ArgumentError>();
    });

    test('accepts alpha boundaries', () {
      for (final alpha in <double>[0, 1]) {
        check(
          () => MKTileOverlay(
            id: const .new('edge'),
            urlTemplate: 'https://t/{z}/{x}/{y}.png',
            alpha: alpha,
          ),
        ).returnsNormally();
      }
    });
  });

  group('equality', () {
    test('compares by value', () {
      check(osm).equals(
        .new(
          id: const .new('osm'),
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        ),
      );
      check(
        osm ==
            .new(
              id: const .new('other'),
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            ),
      ).isFalse();
    });
  });
}
