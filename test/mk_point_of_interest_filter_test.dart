import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

void main() {
  group('MKPointOfInterestFilter wire mapping', () {
    test('includingAll maps to the all mode with no categories', () {
      final platform = MKPointOfInterestFilter.includingAll.toPlatform();
      check(platform.mode).equals(.all);
      check(platform.categories).isEmpty();
    });

    test('excludingAll maps to the none mode', () {
      final platform = MKPointOfInterestFilter.excludingAll.toPlatform();
      check(platform.mode).equals(.none);
      check(platform.categories).isEmpty();
    });

    test('including carries its categories', () {
      final filter = MKPointOfInterestFilter.including(const [.cafe, .museum]);
      final platform = filter.toPlatform();
      check(platform.mode).equals(.including);
      check(platform.categories).deepEquals([
        MKPointOfInterestCategory.cafe,
        MKPointOfInterestCategory.museum,
      ]);
    });

    test('excluding carries its categories', () {
      final filter = MKPointOfInterestFilter.excluding(const [.nightlife]);
      final platform = filter.toPlatform();
      check(platform.mode).equals(.excluding);
      const expected = [MKPointOfInterestCategory.nightlife];
      check(platform.categories).deepEquals(expected);
    });
  });

  group('MKPointOfInterestCategory', () {
    test('covers the 40 original and 33 iOS 18 / macOS 15 categories', () {
      check(MKPointOfInterestCategory.values).length.equals(73);
    });

    test('an iOS 18 category round-trips through a filter', () {
      final filter = MKPointOfInterestFilter.including(const [.golf]);
      check(filter.toPlatform().categories)
          .deepEquals([MKPointOfInterestCategory.golf]);
    });
  });

  group('caller-owned category lists', () {
    for (final (name, make) in [
      ('including', MKPointOfInterestFilter.including),
      ('excluding', MKPointOfInterestFilter.excluding),
    ]) {
      test('$name snapshots its categories, so a later mutation is a new '
          'value', () {
        final categories = [MKPointOfInterestCategory.cafe];
        final before = make(categories);
        categories.add(.museum);
        check(before == make(categories)).isFalse();
        check(before.toPlatform().categories)
            .deepEquals([MKPointOfInterestCategory.cafe]);
      });
    }

    test('exposes unmodifiable categories', () {
      final categories = [MKPointOfInterestCategory.cafe];
      check(() => IncludingPointsOfInterest(categories).categories.add(.museum))
          .throws<UnsupportedError>();
      check(() => ExcludingPointsOfInterest(categories).categories.add(.museum))
          .throws<UnsupportedError>();
    });
  });

  group('MKPointOfInterestFilter equality', () {
    test('same categories compare equal', () {
      final cafe = MKPointOfInterestFilter.including(const [.cafe]);
      check(cafe).equals(cafe);
    });

    test('including and excluding never compare equal', () {
      check(
        MKPointOfInterestFilter.including(const [.cafe]) ==
            .excluding(const [.cafe]),
      ).isFalse();
    });

    test('toString describes each filter variant', () {
      check(MKPointOfInterestFilter.includingAll.toString())
          .equals('MKPointOfInterestFilter.includingAll');
      check(MKPointOfInterestFilter.excludingAll.toString())
          .equals('MKPointOfInterestFilter.excludingAll');
      check(MKPointOfInterestFilter.including(const [.cafe]).toString()).equals(
        'MKPointOfInterestFilter.including('
        '${const [MKPointOfInterestCategory.cafe]})',
      );
      check(MKPointOfInterestFilter.excluding(const [.nightlife]).toString())
          .equals(
            'MKPointOfInterestFilter.excluding('
            '${const [MKPointOfInterestCategory.nightlife]})',
          );
    });
  });
}
