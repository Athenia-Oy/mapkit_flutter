import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';
import 'package:mapkit_flutter/src/_internal/map_object_updates.dart';

void main() {
  // MKPointAnnotation stands in for every map object — the diff is keyed only
  // by the `idOf` string, so the same logic drives polylines/polygons/circles.
  MKPointAnnotation marker(String id, double lat, double lng) {
    return .new(
      id: .new(id),
      coordinate: .new(latitude: lat, longitude: lng),
    );
  }

  MapObjectUpdates<MKPointAnnotation> diff(
    Set<MKPointAnnotation> before,
    Set<MKPointAnnotation> after,
  ) {
    return .between(before, after, idOf: (a) => a.id.value);
  }

  group('MapObjectUpdates.between', () {
    test('detects additions', () {
      final updates = diff({}, {marker('a', 0, 0)});
      check(updates.toAdd).length.equals(1);
      check(updates.toChange).isEmpty();
      check(updates.idsToRemove).isEmpty();
    });

    test('detects removals by id', () {
      final updates = diff({marker('a', 0, 0)}, {});
      check(updates.idsToRemove).deepEquals({'a'});
      check(updates.toAdd).isEmpty();
    });

    test('detects changes (same id, different fields)', () {
      final updates = diff({marker('a', 0, 0)}, {marker('a', 1, 1)});
      check(updates.toChange).length.equals(1);
      check(updates.toAdd).isEmpty();
      check(updates.idsToRemove).isEmpty();
    });

    test('no diff for identical sets', () {
      final updates = diff({marker('a', 0, 0)}, {marker('a', 0, 0)});
      check(updates.toAdd).isEmpty();
      check(updates.toChange).isEmpty();
      check(updates.idsToRemove).isEmpty();
    });

    test('mixed add/change/remove', () {
      final updates = diff(
        {marker('keep', 0, 0), marker('change', 1, 1), marker('gone', 2, 2)},
        {marker('keep', 0, 0), marker('change', 9, 9), marker('new', 3, 3)},
      );
      check(updates.toAdd).length.equals(1);
      check(updates.toChange).length.equals(1);
      check(updates.idsToRemove).deepEquals({'gone'});
    });
  });
}
