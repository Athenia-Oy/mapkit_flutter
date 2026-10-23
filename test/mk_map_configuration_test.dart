import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

void main() {
  group('MKStandardMapConfiguration', () {
    test('defaults mirror MKStandardMapConfiguration', () {
      const config = MKStandardMapConfiguration();
      check(config.elevationStyle).equals(.flat);
      check(config.emphasisStyle).equals(.standard);
      final filter = config.pointOfInterestFilter;
      check(filter).equals(.includingAll);
      check(config.showsTraffic).isFalse();
    });

    test('equality covers every field', () {
      const traffic = MKStandardMapConfiguration(showsTraffic: true);
      check(traffic).equals(traffic);
      check(traffic == const .new()).isFalse();
      check(
        const MKStandardMapConfiguration(emphasisStyle: .muted) == const .new(),
      ).isFalse();
    });

    test('toString includes pointOfInterestFilter', () {
      const config = MKStandardMapConfiguration(
        pointOfInterestFilter: .excludingAll,
      );
      check(
        config.toString(),
      ).contains('pointOfInterestFilter: MKPointOfInterestFilter.excludingAll');
    });
  });

  group('MKHybridMapConfiguration', () {
    test('equality covers traffic and POI filter', () {
      check(
        const MKHybridMapConfiguration(pointOfInterestFilter: .excludingAll),
      ).equals(const .new(pointOfInterestFilter: .excludingAll));
      check(const MKHybridMapConfiguration(showsTraffic: true) == const .new())
          .isFalse();
    });

    test('toString includes pointOfInterestFilter', () {
      const config = MKHybridMapConfiguration();
      check(
        config.toString(),
      ).contains('pointOfInterestFilter: MKPointOfInterestFilter.includingAll');
    });
  });

  group('MKImageryMapConfiguration', () {
    test('equality covers elevation', () {
      const realistic = MKImageryMapConfiguration(elevationStyle: .realistic);
      check(realistic).equals(realistic);
      check(
        const MKImageryMapConfiguration() ==
            const .new(elevationStyle: .realistic),
      ).isFalse();
    });

    test('variants of different kinds never compare equal', () {
      const MKMapConfiguration standard = MKStandardMapConfiguration();
      const MKMapConfiguration imagery = MKImageryMapConfiguration();
      check(standard == imagery).isFalse();
    });
  });
}
