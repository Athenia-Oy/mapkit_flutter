import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

import '_helpers/fixtures.dart';

void main() {
  group('MKPointAnnotation wire mapping', () {
    test('serializes MKAnnotationView vocabulary', () {
      final platform = MKPointAnnotation(
        id: const .new('a'),
        coordinate: applePark,
        icon: const .marker(markerTintColor: .new(0xFF2266FF)),
        title: 'Apple Park',
        subtitle: 'Cupertino',
        alpha: 0.8,
        anchorPoint: const .new(0.5, 0.5),
        isDraggable: true,
        zPriority: 750,
        clusteringIdentifier: 'offices',
      ).toPlatform();

      check(platform.id).equals('a');
      check(platform.coordinate.latitude).equals(applePark.latitude);
      check(platform.title).equals('Apple Park');
      check(platform.subtitle).equals('Cupertino');
      check(platform.alpha).equals(0.8);
      check(platform.anchorPointX).equals(0.5);
      check(platform.anchorPointY).equals(0.5);
      check(platform.isDraggable).isTrue();
      check(platform.isHidden).isFalse();
      check(platform.zPriority).equals(750);
      check(platform.clusteringIdentifier).equals('offices');
    });

    test('callout tap capture is the explicit flag', () {
      check(annotation('a').toPlatform().calloutConsumesTapEvents).isFalse();
      check(
        MKPointAnnotation(
          id: const .new('a'),
          coordinate: applePark,
          calloutConsumesTapEvents: true,
        ).toPlatform().calloutConsumesTapEvents,
      ).isTrue();
    });

    test('defaults mirror MKAnnotationView', () {
      final platform = annotation('a').toPlatform();
      check(platform.alpha).equals(1);
      check(platform.anchorPointX).equals(0.5);
      check(platform.anchorPointY).equals(1);
      check(platform.zPriority).equals(500);
      check(platform.isDraggable).isFalse();
      check(platform.clusteringIdentifier).isNull();
    });

    test('rejects out of bounds alpha values', () {
      check(
        () => MKPointAnnotation(
          id: const .new('bad'),
          coordinate: applePark,
          alpha: -0.1,
        ),
      ).throws<ArgumentError>();

      check(
        () => MKPointAnnotation(
          id: const .new('bad'),
          coordinate: applePark,
          alpha: 1.1,
        ),
      ).throws<ArgumentError>();
    });

    test('accepts alpha boundaries', () {
      for (final alpha in <double>[0, 1]) {
        check(
          () => MKPointAnnotation(
            id: const .new('edge'),
            coordinate: applePark,
            alpha: alpha,
          ),
        ).returnsNormally();
      }
    });
  });

  group('equality', () {
    test('select and drag closure identity does not affect equality', () {
      MKPointAnnotation withCallbacks() => .new(
        id: const .new('a'),
        coordinate: applePark,
        onSelect: () {},
        onDragStart: (_) {},
        onDragEnd: (_) {},
      );
      // Distinct closure instances, identical visuals → equal, so a closure
      // swap never churns the native recycle path.
      check(withCallbacks()).equals(withCallbacks());
      check(withCallbacks().hashCode).equals(withCallbacks().hashCode);
    });

    test(
      'calloutConsumesTapEvents is explicit state, not callback presence',
      () {
        final plain = MKPointAnnotation(
          id: const .new('a'),
          coordinate: applePark,
        );
        final consuming = MKPointAnnotation(
          id: const .new('a'),
          coordinate: applePark,
          calloutConsumesTapEvents: true,
        );
        final withCallout = MKPointAnnotation(
          id: const .new('a'),
          coordinate: applePark,
          calloutConsumesTapEvents: true,
          onCalloutTap: () {},
        );
        check(consuming == plain).isFalse();
        check(withCallout).equals(consuming);
        check(withCallout.toPlatform().calloutConsumesTapEvents).isTrue();
        check(plain.toPlatform().calloutConsumesTapEvents).isFalse();
      },
    );

    test('onCalloutTap without calloutConsumesTapEvents throws', () {
      check(
        () => MKPointAnnotation(
          id: const .new('a'),
          coordinate: applePark,
          onCalloutTap: () {},
        ),
      ).throws<ArgumentError>();
    });

    test('different coordinates compare unequal', () {
      final moved = annotation('a', coordinate: infiniteLoop);
      check(annotation('a') == moved).isFalse();
    });
  });

  group('copyWith', () {
    test('replaces only the given fields and keeps the id', () {
      final moved = annotation(
        'a',
        title: 't',
      ).copyWith(coordinate: infiniteLoop, isDraggable: true);
      check(moved.id).equals(const .new('a'));
      check(moved.coordinate).equals(infiniteLoop);
      check(moved.isDraggable).isTrue();
      check(moved.title).equals('t');
    });
  });

  group('clustering', () {
    test('annotations sharing a clusteringIdentifier serialize it', () {
      final ids = [
        MKPointAnnotation(
          id: const .new('a'),
          coordinate: applePark,
          clusteringIdentifier: 'stores',
        ),
        MKPointAnnotation(
          id: const .new('b'),
          coordinate: infiniteLoop,
          clusteringIdentifier: 'stores',
        ),
      ].map((a) => a.toPlatform().clusteringIdentifier).toSet();
      check(ids).deepEquals({'stores'});
    });
  });
}
