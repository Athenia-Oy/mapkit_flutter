import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';
import 'package:mapkit_flutter/src/messages.g.dart';

import '_helpers/controller_harness.dart';
import '_helpers/fixtures.dart';
import '_helpers/platform_fixtures.dart';
import '_helpers/recorded_call.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ControllerHarness buildHarness() => .autoTearDown(viewId: 2);

  group('getZoomLevel', () {
    test('derives the level from the host camera distance', () async {
      final harness = buildHarness();
      harness.host.camera = platformCamera(distance: 591657550.5);
      check(await harness.controller.getZoomLevel()).isCloseTo(1, 1e-9);
      harness.expectCalls(['getCamera']);
    });
  });

  group('zoomTo', () {
    test('reads the camera, then sets it at the requested level', () async {
      final harness = buildHarness();
      await harness.controller.zoomTo(10, animated: false);
      harness.expectCalls(['getCamera', 'setCamera']);
      final (camera, animated) = harness.expectSetCamera();
      check(camera.distance).isCloseTo(591657550.5 / 512, 1e-6);
      check(animated).isFalse();
    });

    test('preserves center, heading, and pitch', () async {
      final harness = buildHarness();
      harness.host.camera = platformCamera(
        latitude: 10,
        longitude: 20,
        distance: 5000,
        heading: 45,
        pitch: 30,
      );
      await harness.controller.zoomTo(12);
      final (camera, _) = harness.expectSetCamera();
      check(camera.centerCoordinate.latitude).equals(10);
      check(camera.heading).equals(45);
      check(camera.pitch).equals(30);
    });
  });

  group('zoomBy', () {
    test('halves the distance per level zoomed in', () async {
      final harness = buildHarness();
      await harness.controller.zoomBy(1);
      harness.expectCalls(['getCamera', 'setCamera']);
      check(harness.expectSetCamera().$1.distance).isCloseTo(500, 1e-9);
    });

    test('zoomIn and zoomOut are one level each way', () async {
      final harness = buildHarness();
      await harness.controller.zoomIn();
      check(harness.expectSetCamera().$1.distance).isCloseTo(500, 1e-9);

      harness.host.calls.clear();
      await harness.controller.zoomOut();
      check(harness.expectSetCamera().$1.distance).isCloseTo(2000, 1e-9);
    });
  });

  group('scrollBy', () {
    test('converts the shifted center point back to a coordinate', () async {
      final harness = buildHarness();
      harness.host
        ..point = platformPoint(100, 200)
        ..coordinate = platformCoord(5, 6);

      await harness.controller.scrollBy(50, -30, animated: false);

      harness.expectCalls([
        'getCamera',
        'convertToPoint',
        'convertToCoordinate',
        'setCenter',
      ]);
      final shifted = harness.host.calls.requireArgsAt<PlatformPoint>(2);
      check(shifted.x).equals(150);
      check(shifted.y).equals(170);
      final (center, animated) = harness.expectSetCenter();
      check(center.latitude).equals(5);
      check(animated).isFalse();
    });
  });

  group('fitCoordinates', () {
    test('sets the containing region', () async {
      final harness = buildHarness();
      await harness.controller.fitCoordinates([
        .new(latitude: 10, longitude: 20),
        .new(latitude: 30, longitude: 40),
      ], animated: false);
      harness.expectCalls(['setRegion']);
      final (region, _) = harness.expectSetRegion();
      check(region.center.latitude).equals(20);
      check(region.span.longitudeDelta).equals(20);
    });

    test('pads each side by a fraction of the span', () async {
      final harness = buildHarness();
      await harness.controller.fitCoordinates(
        [.new(latitude: 10, longitude: 20), .new(latitude: 30, longitude: 40)],
        animated: false,
        padding: 0.1,
      );
      final (region, _) = harness.expectSetRegion();
      check(region.center.latitude).equals(20);
      check(region.center.longitude).equals(30);
      check(region.span.latitudeDelta).isCloseTo(24, 1e-9);
      check(region.span.longitudeDelta).isCloseTo(24, 1e-9);
    });

    test('frames a single coordinate at the minimum span', () async {
      final harness = buildHarness();
      await harness.controller.fitCoordinates([
        .new(latitude: 10, longitude: 20),
      ], animated: false);
      final (region, _) = harness.expectSetRegion();
      check(region.span.latitudeDelta).equals(0.005);
      check(region.span.longitudeDelta).equals(0.005);
    });

    test('spans that overflow what MapKit can show throw', () async {
      final harness = buildHarness();
      await check(
        harness.controller.fitCoordinates([
          .new(latitude: -40, longitude: -80),
          .new(latitude: 40, longitude: 80),
        ], padding: 2),
      ).throws<ArgumentError>();
      await check(
        harness.controller.fitCoordinates([applePark], minimumSpan: 200),
      ).throws<ArgumentError>();
      harness.expectCalls([]);
    });

    test('a span of exactly the limit is still accepted', () async {
      final harness = buildHarness();
      await harness.controller.fitCoordinates([
        .new(latitude: -45, longitude: -90),
        .new(latitude: 45, longitude: 90),
      ], padding: 0.5);
      final (region, _) = harness.expectSetRegion();
      check(region.span.latitudeDelta).equals(180);
      check(region.span.longitudeDelta).equals(360);
    });

    group('misuse fails loudly', () {
      test('fitCoordinates with no coordinates throws', () async {
        final harness = buildHarness();
        await check(
          harness.controller.fitCoordinates(const [], animated: false),
        ).throws<ArgumentError>();
        check(harness.host.callNames).not((it) => it.contains('setRegion'));
      });

      test('fitCoordinates rejects negative padding or minimumSpan', () async {
        final harness = buildHarness();
        await check(
          harness.controller.fitCoordinates([applePark], padding: -0.1),
        ).throws<ArgumentError>();
        await check(
          harness.controller.fitCoordinates([applePark], minimumSpan: -1),
        ).throws<ArgumentError>();
      });

      test('camera helpers before layout throw a StateError', () async {
        final harness = buildHarness();
        harness.host.camera = null;
        await check(harness.controller.getZoomLevel()).throws<StateError>();
        await check(harness.controller.zoomTo(10)).throws<StateError>();
        await check(harness.controller.zoomIn()).throws<StateError>();
        await check(harness.controller.scrollBy(1, 1)).throws<StateError>();
        check(harness.host.callNames).not((it) => it.contains('setCamera'));
      });

      test('scrollBy before layout throws instead of doing nothing', () async {
        final harness = buildHarness();
        harness.host.point = null;
        await check(harness.controller.scrollBy(10, 10)).throws<StateError>();
      });
    });
  });
}
