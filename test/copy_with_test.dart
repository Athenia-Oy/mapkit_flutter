import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

import '_helpers/fixtures.dart';

/// One nullable `copyWith` parameter: omitted keeps, `null` clears, a value
/// sets.
typedef _Case<M> = ({
  String name,
  Object? Function(M) read,
  M Function(M) clear,
  M Function(M) set,
  Object? next,
});

void main() {
  void tap() {}
  void nextTap() {}
  void onCoordinate(CLLocationCoordinate2D _) {}
  void nextOnCoordinate(CLLocationCoordinate2D _) {}

  group('MKPointAnnotation.copyWith', () {
    final full = MKPointAnnotation(
      id: const .new('a'),
      coordinate: applePark,
      title: 'title',
      subtitle: 'subtitle',
      clusteringIdentifier: 'shops',
      calloutConsumesTapEvents: true,
      onCalloutTap: tap,
      onDragStart: onCoordinate,
      onDragEnd: onCoordinate,
      onSelect: tap,
      onDeselect: tap,
    );

    for (final c in <_Case<MKPointAnnotation>>[
      (
        name: 'title',
        read: (a) => a.title,
        clear: (a) => a.copyWith(title: null),
        set: (a) => a.copyWith(title: 'next'),
        next: 'next',
      ),
      (
        name: 'subtitle',
        read: (a) => a.subtitle,
        clear: (a) => a.copyWith(subtitle: null),
        set: (a) => a.copyWith(subtitle: 'next'),
        next: 'next',
      ),
      (
        name: 'clusteringIdentifier',
        read: (a) => a.clusteringIdentifier,
        clear: (a) => a.copyWith(clusteringIdentifier: null),
        set: (a) => a.copyWith(clusteringIdentifier: 'next'),
        next: 'next',
      ),
      (
        name: 'onCalloutTap',
        read: (a) => a.onCalloutTap,
        clear: (a) => a.copyWith(onCalloutTap: null),
        set: (a) => a.copyWith(onCalloutTap: nextTap),
        next: nextTap,
      ),
      (
        name: 'onDragStart',
        read: (a) => a.onDragStart,
        clear: (a) => a.copyWith(onDragStart: null),
        set: (a) => a.copyWith(onDragStart: nextOnCoordinate),
        next: nextOnCoordinate,
      ),
      (
        name: 'onDragEnd',
        read: (a) => a.onDragEnd,
        clear: (a) => a.copyWith(onDragEnd: null),
        set: (a) => a.copyWith(onDragEnd: nextOnCoordinate),
        next: nextOnCoordinate,
      ),
      (
        name: 'onSelect',
        read: (a) => a.onSelect,
        clear: (a) => a.copyWith(onSelect: null),
        set: (a) => a.copyWith(onSelect: nextTap),
        next: nextTap,
      ),
      (
        name: 'onDeselect',
        read: (a) => a.onDeselect,
        clear: (a) => a.copyWith(onDeselect: null),
        set: (a) => a.copyWith(onDeselect: nextTap),
        next: nextTap,
      ),
    ]) {
      test('${c.name}: omitted keeps, null clears, a value sets', () {
        check(c.read(full)).isNotNull();
        check(c.read(full.copyWith())).equals(c.read(full));
        check(c.read(c.clear(full))).isNull();
        check(c.read(c.set(full))).equals(c.next);
      });
    }

    test('an untyped closure literal keeps its parameter type', () {
      CLLocationCoordinate2D? last;
      full.copyWith(onDragEnd: (c) => last = c).onDragEnd?.call(infiniteLoop);
      check(last).equals(infiniteLoop);
    });

    test('equality ignores closures; calloutConsumesTapEvents is state', () {
      check(full.copyWith(onCalloutTap: nextTap)).equals(full);
      check(full.copyWith(onCalloutTap: nextTap).hashCode)
          .equals(full.hashCode);
      check(full.copyWith(onCalloutTap: null)).equals(full);
      check(
        full.copyWith(onCalloutTap: null, calloutConsumesTapEvents: false) ==
            full,
      ).isFalse();
    });
  });

  group('MKPolyline.copyWith', () {
    final full = MKPolyline(
      id: const .new('p'),
      coordinates: [applePark, infiniteLoop],
      lineDashPattern: const [6, 3],
      consumeTapEvents: true,
      onTap: tap,
    );

    test('lineDashPattern: omitted keeps, null clears, a value sets', () {
      check(full.copyWith().lineDashPattern).isNotNull().deepEquals([6, 3]);
      check(full.copyWith(lineDashPattern: null).lineDashPattern).isNull();
      check(full.copyWith(lineDashPattern: [2, 4]).lineDashPattern)
          .isNotNull()
          .deepEquals([2, 4]);
    });

    for (final c in <_Case<MKPolyline>>[
      (
        name: 'onTap',
        read: (p) => p.onTap,
        clear: (p) => p.copyWith(onTap: null),
        set: (p) => p.copyWith(onTap: nextTap),
        next: nextTap,
      ),
    ]) {
      test('${c.name}: omitted keeps, null clears, a value sets', () {
        check(c.read(full)).isNotNull();
        check(c.read(full.copyWith())).equals(c.read(full));
        check(c.read(c.clear(full))).isNull();
        check(c.read(c.set(full))).equals(c.next);
      });
    }

    test('an empty dash pattern is stored, not rejected', () {
      check(full.copyWith(lineDashPattern: []).lineDashPattern)
          .isNotNull()
          .isEmpty();
      check(full.copyWith(lineDashPattern: const []).lineDashPattern)
          .isNotNull()
          .isEmpty();
    });

    test('int literals become a double dash pattern', () {
      check(full.copyWith(lineDashPattern: const [1]).lineDashPattern)
          .isNotNull()
          .deepEquals([1.0]);
    });

    test('equality ignores closures; consumeTapEvents is state', () {
      check(full.copyWith(onTap: nextTap)).equals(full);
      check(full.copyWith(onTap: nextTap).hashCode).equals(full.hashCode);
      check(full.copyWith(onTap: null)).equals(full);
      check(full.copyWith(onTap: null, consumeTapEvents: false) == full)
          .isFalse();
    });
  });

  group('MKCircle.copyWith', () {
    final full = MKCircle(
      id: const .new('c'),
      center: applePark,
      radius: 500,
      consumeTapEvents: true,
      onTap: tap,
    );

    for (final c in <_Case<MKCircle>>[
      (
        name: 'onTap',
        read: (c) => c.onTap,
        clear: (c) => c.copyWith(onTap: null),
        set: (c) => c.copyWith(onTap: nextTap),
        next: nextTap,
      ),
    ]) {
      test('${c.name}: omitted keeps, null clears, a value sets', () {
        check(c.read(full)).isNotNull();
        check(c.read(full.copyWith())).equals(c.read(full));
        check(c.read(c.clear(full))).isNull();
        check(c.read(c.set(full))).equals(c.next);
      });
    }

    test('equality ignores closures; consumeTapEvents is state', () {
      check(full.copyWith(onTap: nextTap)).equals(full);
      check(full.copyWith(onTap: nextTap).hashCode).equals(full.hashCode);
      check(full.copyWith(onTap: null)).equals(full);
      check(full.copyWith(onTap: null, consumeTapEvents: false) == full)
          .isFalse();
    });
  });

  group('MKPolygon.copyWith', () {
    final full = polygon('z').copyWith(consumeTapEvents: true, onTap: tap);

    for (final c in <_Case<MKPolygon>>[
      (
        name: 'onTap',
        read: (p) => p.onTap,
        clear: (p) => p.copyWith(onTap: null),
        set: (p) => p.copyWith(onTap: nextTap),
        next: nextTap,
      ),
    ]) {
      test('${c.name}: omitted keeps, null clears, a value sets', () {
        check(c.read(full)).isNotNull();
        check(c.read(full.copyWith())).equals(c.read(full));
        check(c.read(c.clear(full))).isNull();
        check(c.read(c.set(full))).equals(c.next);
      });
    }

    test('equality ignores closures; consumeTapEvents is state', () {
      check(full.copyWith(onTap: nextTap)).equals(full);
      check(full.copyWith(onTap: nextTap).hashCode).equals(full.hashCode);
      check(full.copyWith(onTap: null)).equals(full);
      check(full.copyWith(onTap: null, consumeTapEvents: false) == full)
          .isFalse();
    });
  });
}
