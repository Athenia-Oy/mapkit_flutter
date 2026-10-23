import 'package:checks/checks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';
import 'package:mapkit_flutter/src/messages.g.dart';

import '_helpers/controller_harness.dart';
import '_helpers/fixtures.dart';
import '_helpers/platform_fixtures.dart';
import '_helpers/recorded_call.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ControllerHarness buildHarness() => .autoTearDown();

  group('outbound — camera', () {
    test('setCamera forwards the camera and the animated flag', () async {
      final harness = buildHarness();
      await harness.controller.setCamera(sampleCamera, animated: false);
      final (camera, animated) = harness.expectSetCamera();
      check(camera.distance).equals(1200);
      check(animated).isFalse();
    });

    test('setCamera animates by default', () async {
      final harness = buildHarness();
      await harness.controller.setCamera(sampleCamera);
      check(harness.expectSetCamera().$2).isTrue();
    });

    test('setRegion forwards center and span', () async {
      final harness = buildHarness();
      await harness.controller.setRegion(sampleRegion, animated: false);
      final (region, _) = harness.expectSetRegion();
      check(region.center.latitude).equals(applePark.latitude);
      check(region.span.latitudeDelta).equals(0.05);
    });

    test('setCenter forwards the coordinate', () async {
      final harness = buildHarness();
      await harness.controller.setCenter(applePark);
      final (coordinate, animated) = harness.expectSetCenter();
      check(coordinate.longitude).equals(applePark.longitude);
      check(animated).isTrue();
    });

    test('camera getter parses the host camera', () async {
      final harness = buildHarness();
      harness.host.camera = platformCamera(
        latitude: 10,
        longitude: 20,
        distance: 4321,
        heading: 90,
        pitch: 15,
      );
      final camera = (await harness.controller.camera)!;
      final target = CLLocationCoordinate2D(latitude: 10, longitude: 20);
      check(camera.centerCoordinate).equals(target);
      check(camera.distance).equals(4321);
      check(camera.heading).equals(90);
      check(camera.pitch).equals(15);
    });

    test('camera is null before the first layout', () async {
      final harness = buildHarness();
      harness.host.camera = null;
      check(await harness.controller.camera).isNull();
    });

    test('region getter parses center + span', () async {
      final harness = buildHarness();
      harness.host.region = platformRegion(
        latitude: 10,
        longitude: 20,
        latitudeDelta: 1,
        longitudeDelta: 2,
      );
      final region = (await harness.controller.region)!;
      final center = CLLocationCoordinate2D(latitude: 10, longitude: 20);
      final span = MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 2);
      check(region.center).equals(center);
      check(region.span).equals(span);
    });

    test('region is null before the first layout', () async {
      final harness = buildHarness();
      harness.host.region = null;
      check(await harness.controller.region).isNull();
    });
  });

  group('outbound — coordinate conversion', () {
    test('convertToPoint returns an Offset when the host has layout', () async {
      final harness = buildHarness();
      harness.host.point = platformPoint(100, 200);
      final p = await harness.controller.convertToPoint(applePark);
      check(p).isNotNull()
        ..has((o) => o.dx, 'dx').equals(100)
        ..has((o) => o.dy, 'dy').equals(200);
    });

    test('convertToPoint returns null without layout', () async {
      final harness = buildHarness();
      harness.host.point = null;
      check(await harness.controller.convertToPoint(applePark)).isNull();
    });

    test('convertToCoordinate returns the coordinate under a point', () async {
      final harness = buildHarness();
      harness.host.coordinate = platformCoord(1, 2);
      final c = await harness.controller.convertToCoordinate(const .new(5, 5));
      check(c).equals(.new(latitude: 1, longitude: 2));
      check(harness.host.calls.lastRecorded().name)
          .equals('convertToCoordinate');
    });

    test('convertToCoordinate returns null without layout', () async {
      final harness = buildHarness();
      harness.host.coordinate = null;
      check(await harness.controller.convertToCoordinate(.zero)).isNull();
    });
  });

  group('outbound — selection', () {
    test('selectAnnotation forwards the id and reports the outcome', () async {
      final harness = buildHarness();
      check(await harness.controller.selectAnnotation(const .new('a')))
          .isTrue();
      check(harness.expectLast<String>('selectAnnotation')).equals('a');
      harness.host.selectResult = false;
      check(await harness.controller.selectAnnotation(const .new('x')))
          .isFalse();
    });

    test('deselectAnnotation reports an id that is not on the map', () async {
      final harness = buildHarness();
      harness.host.deselectResult = false;
      check(await harness.controller.deselectAnnotation(const .new('a')))
          .isFalse();
      harness.expectLastCall('deselectAnnotation');
    });

    test('isAnnotationSelected returns host bool', () async {
      final harness = buildHarness();
      harness.host.annotationSelected = true;
      const annotationId = MKAnnotationId('a');
      check(await harness.controller.isAnnotationSelected(annotationId))
          .isTrue();
    });
  });

  group('outbound — polish features', () {
    test('takeSnapshot forwards the options', () async {
      final harness = buildHarness();
      await harness.controller.takeSnapshot(const .new(showsOverlays: false));
      final options = harness.expectLast<PlatformSnapshotOptions>(
        'takeSnapshot',
      );
      check(options.showsPointsOfInterest).isTrue();
      check(options.showsAnnotations).isTrue();
      check(options.showsOverlays).isFalse();
    });

    test(
      'openLookAround forwards the coordinate and returns the native bool',
      () async {
        final harness = buildHarness();
        harness.host.lookAroundResult = true;
        final ok = await harness.controller.openLookAround(
          .new(latitude: 37, longitude: -122),
        );
        check(ok).isTrue();
        final sent = harness.expectLast<PlatformCoordinate>('openLookAround');
        check(sent.latitude).equals(37);
      },
    );

    test('addTileOverlay forwards a typed overlay', () async {
      final harness = buildHarness();
      await harness.controller.addTileOverlay(
        .new(
          id: const .new('osm'),
          urlTemplate: 'https://t/{z}/{x}/{y}.png',
          minimumZ: 3,
          maximumZ: 17,
          canReplaceMapContent: true,
        ),
      );
      final o = harness.expectLast<PlatformTileOverlay>('addTileOverlay');
      check(o.id).equals('osm');
      check(o.minimumZ).equals(3);
      check(o.canReplaceMapContent).isTrue();
    });

    test(
      'removeTileOverlay forwards id only and reports the outcome',
      () async {
        final harness = buildHarness();
        check(await harness.controller.removeTileOverlay(const .new('osm')))
            .isTrue();
        check(harness.expectLast<String>('removeTileOverlay')).equals('osm');
        harness.host.removeTileOverlayResult = false;
        check(await harness.controller.removeTileOverlay(const .new('gone')))
            .isFalse();
      },
    );
  });

  group('outbound — diff updates', () {
    test('updateAnnotations forwards mapped platform lists', () async {
      final harness = buildHarness();
      final before = {annotation('a')};
      final after = {annotation('a', coordinate: infiniteLoop)};
      await harness.controller.updateAnnotations(
        .between(before, after, idOf: (a) => a.id.value),
      );
      final args = harness.expectLast<AnnotationUpdate>('updateAnnotations');
      check(args.$2).length.equals(1); // toChange
    });
  });

  group('inbound — handler routes to sink', () {
    test('onCameraMoveStarted', () {
      final harness = buildHarness();
      harness.controller.eventHandler.onCameraMoveStarted();
      harness.sink.events.expectOnlyEvent('cameraMoveStarted');
    });

    test('onCameraMove delivers an MKMapCamera', () {
      final harness = buildHarness();
      harness.controller.eventHandler.onCameraMove(
        platformCamera(latitude: 1, longitude: 2, distance: 900),
      );
      check(harness.expectSink<MKMapCamera>('cameraMove').distance).equals(900);
    });

    test('onAnnotationSelect', () {
      final harness = buildHarness();
      harness.controller.eventHandler.onAnnotationSelect('a');
      final sunk = harness.expectSink<MKAnnotationId>('annotationSelect');
      check(sunk).equals(const .new('a'));
    });

    test('onUserTrackingModeChanged delivers the new mode', () {
      final harness = buildHarness();
      harness.controller.eventHandler.onUserTrackingModeChanged(.none);
      check(harness.expectSink<MKUserTrackingMode>('userTrackingModeChanged'))
          .equals(.none);
    });

    test('annotation drag lifecycle', () {
      final harness = buildHarness();
      harness.controller.eventHandler
        ..onAnnotationDragStart('a', platformCoord(1, 2))
        ..onAnnotationDragEnd('a', platformCoord(2, 3));
      harness.sink.events.expectEventNames([
        'annotationDragStart',
        'annotationDragEnd',
      ]);
    });

    test('onMapTap delivers a coordinate', () {
      final harness = buildHarness();
      harness.controller.eventHandler.onMapTap(platformCoord(10, 20));
      final target = CLLocationCoordinate2D(latitude: 10, longitude: 20);
      final sunk = harness.expectSink<CLLocationCoordinate2D>('mapTap');
      check(sunk).equals(target);
    });

    test('onDidFailLoadingMap delivers the error description', () {
      final harness = buildHarness();
      harness.controller.eventHandler.onDidFailLoadingMap('offline');
      final event = harness.sink.events.single;
      check(event).equals(('didFailLoadingMap', 'offline'));
    });

    test('onDidFailToLocateUser delivers the error description', () {
      final harness = buildHarness();
      harness.controller.eventHandler.onDidFailToLocateUser('denied');
      final event = harness.sink.events.single;
      check(event).equals(('didFailToLocateUser', 'denied'));
    });
  });

  group('errors', () {
    test('disposed controller throws MapKitDisposedException', () async {
      final harness = buildHarness();
      await harness.dispose();
      final setCamera = harness.controller.setCamera(sampleCamera);
      await check(setCamera).throws<MapKitDisposedException>();
    });

    for (final code in ['look-around-failed', 'unsupported-platform']) {
      test('openLookAround failure surfaces $code', () async {
        final harness = buildHarness();
        harness.host.errorToThrow = PlatformException(code: code);
        check(
          await catchMapKit<MapKitPlatformException>(
            () => harness.controller.openLookAround(applePark),
          ),
        ).has((e) => e.code, 'code').equals(code);
      });
    }

    test('addTileOverlay with a duplicate id surfaces duplicate-id', () async {
      final harness = buildHarness();
      harness.host.errorToThrow = PlatformException(code: 'duplicate-id');
      check(
        await catchMapKit<MapKitPlatformException>(
          () => harness.controller.addTileOverlay(
            .new(id: const .new('osm'), urlTemplate: 'u'),
          ),
        ),
      ).has((e) => e.code, 'code').equals('duplicate-id');
    });

    test('snapshot failure surfaces its stable code', () async {
      final harness = buildHarness();
      harness.host.errorToThrow = PlatformException(
        code: 'snapshot-failed',
        message: 'Snapshot produced no image data.',
      );
      check(
        await catchMapKit<MapKitPlatformException>(
          harness.controller.takeSnapshot,
        ),
      ).has((e) => e.code, 'code').equals('snapshot-failed');
    });

    test('generic platform error maps to MapKitPlatformException', () async {
      final harness = buildHarness();
      harness.host.errorToThrow = PlatformException(
        code: 'boom',
        message: 'kaboom',
      );
      check(
        await catchMapKit<MapKitPlatformException>(
          () => harness.controller.setCamera(sampleCamera),
        ),
      ).has((e) => e.code, 'code').equals('boom');
    });

    test('non-platform error propagates unwrapped', () async {
      final harness = buildHarness();
      final exception = Exception('custom host error');
      harness.host.errorToThrow = exception;

      Object? caughtError;
      StackTrace? caughtTrace;
      try {
        await harness.controller.setCamera(sampleCamera);
      } on Object catch (e, st) {
        caughtError = e;
        caughtTrace = st;
      }
      check(caughtError).identicalTo(exception);
      check(caughtTrace.toString()).contains('FakeHostApi._record');
    });

    test(
      'Error subtype propagates unwrapped through the generic catch',
      () async {
        final harness = buildHarness();
        final error = StateError('host invariant violated');
        harness.host.errorToThrow = error;

        Object? caughtError;
        StackTrace? caughtTrace;
        try {
          await harness.controller.setCamera(sampleCamera);
        } on Object catch (e, st) {
          caughtError = e;
          caughtTrace = st;
        }
        check(caughtError).identicalTo(error);
        check(caughtTrace.toString()).contains('FakeHostApi._record');
      },
    );

    test('queued calls after a failure still run', () async {
      final harness = buildHarness();
      harness.host.errorToThrow = PlatformException(code: 'boom');
      final failing = harness.controller.setCamera(sampleCamera);
      final following = harness.controller.setCenter(applePark);
      await check(failing).throws<MapKitPlatformException>();
      await following;
      harness.expectLastCall('setCenter');
    });
  });
}
