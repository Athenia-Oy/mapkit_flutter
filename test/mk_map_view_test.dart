import 'dart:async';

import 'package:checks/checks.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';
import 'package:mapkit_flutter/src/messages.g.dart';
import 'package:mapkit_flutter/src/mk_map_view_controller.dart';

import '_helpers/fake_host_api.dart';
import '_helpers/fixtures.dart';
import '_helpers/platform_fixtures.dart';
import '_helpers/recorded_call.dart';

void main() {
  var host = FakeHostApi();
  var nextViewId = 0;

  MKMapViewControllerImpl? createdController;

  setUp(() {
    host = .new();
    createdController = null;
    nextViewId++;
  });

  MKMapViewControllerImpl requireCreated() {
    final c = createdController;
    if (c == null) {
      fail('Expected MKMapViewControllerImpl to have been created');
    }
    return c;
  }

  MKMapViewControllerImpl controllerFactory(MKMapViewEventSink sink) =>
      createdController = .new(viewId: nextViewId, sink: sink, hostApi: host);

  Widget map({
    Set<MKPointAnnotation> annotations = const {},
    Set<MKPolyline> polylines = const {},
    Set<MKPolygon> polygons = const {},
    Set<MKCircle> circles = const {},
    MKMapConfiguration preferredConfiguration =
        const MKStandardMapConfiguration(),
    bool isZoomEnabled = true,
    bool showsUserLocation = false,
    MKCameraZoomRange cameraZoomRange = .unbounded,
    Set<MKMapFeatureOptions> selectableMapFeatures = const {},
    void Function(MKMapViewController)? onMapCreated,
    VoidCallback? onCameraMoveStarted,
    ValueChanged<MKMapCamera>? onCameraMove,
    VoidCallback? onCameraIdle,
    void Function(CLLocationCoordinate2D)? onTap,
    void Function(CLLocationCoordinate2D)? onLongPress,
    ValueChanged<String>? onDidFailLoadingMap,
    ValueChanged<String>? onDidFailToLocateUser,
    ValueChanged<MKMapFeature>? onMapFeatureSelected,
  }) {
    return MKMapView(
      initialCamera: sampleCamera,
      annotations: annotations,
      polylines: polylines,
      polygons: polygons,
      circles: circles,
      preferredConfiguration: preferredConfiguration,
      isZoomEnabled: isZoomEnabled,
      showsUserLocation: showsUserLocation,
      cameraZoomRange: cameraZoomRange,
      selectableMapFeatures: selectableMapFeatures,
      onMapCreated: onMapCreated,
      onCameraMoveStarted: onCameraMoveStarted,
      onCameraMove: onCameraMove,
      onCameraIdle: onCameraIdle,
      onTap: onTap,
      onLongPress: onLongPress,
      onDidFailLoadingMap: onDidFailLoadingMap,
      onDidFailToLocateUser: onDidFailToLocateUser,
      onMapFeatureSelected: onMapFeatureSelected,
      debugControllerFactory: controllerFactory,
    );
  }

  group('platform guard', () {
    testWidgets(
      'throws MapKitUnsupportedPlatformException off Apple platforms',
      (tester) async {
        await tester.pumpWidget(MKMapView(initialCamera: sampleCamera));
        check(tester.takeException()).isA<MapKitUnsupportedPlatformException>();
      },
    );
  });

  group('initialize', () {
    testWidgets('pushes camera, configuration, and content once', (
      tester,
    ) async {
      MKMapViewController? fromCallback;
      await tester.pumpWidget(
        map(
          annotations: {annotation('a')},
          polylines: {polyline('p')},
          onMapCreated: (c) => fromCallback = c,
        ),
      );
      await tester.pump();

      check(fromCallback).isNotNull();
      check(host.callNames).deepEquals(['initialize']);
      final params = host.initializeParams();
      check(params.initialCamera?.distance).equals(sampleCamera.distance);
      check(params.annotations).length.equals(1);
      check(params.polylines).length.equals(1);
      check(params.polygons).isEmpty();
    });

    testWidgets('assembles MKMapView defaults onto the wire', (tester) async {
      await tester.pumpWidget(map());
      await tester.pump();

      final config = host.initializeParams().configuration;
      check(config.kind).equals(.standard);
      check(config.emphasisStyle).equals(.standard);
      check(config.elevationStyle).equals(.flat);
      check(config.isZoomEnabled).isTrue();
      check(config.isScrollEnabled).isTrue();
      check(config.showsCompass).isTrue();
      check(config.showsScale).isFalse();
      check(config.showsUserLocation).isFalse();
      check(config.showsUserTrackingButton).isFalse();
      check(config.userTrackingMode).equals(.none);
      check(config.selectableMapFeatures).isEmpty();
      check(config.pointOfInterestFilter)
          .isNotNull()
          .has((f) => f.mode, 'mode')
          .equals(.all);
      check(config.cameraZoomRange)
          .isNotNull()
          .has(
            (r) => r.minCenterCoordinateDistance,
            'minCenterCoordinateDistance',
          )
          .isNull();
      check(config.cameraBoundary).isNull();
    });

    testWidgets('flattens hybrid and imagery configurations', (tester) async {
      await tester.pumpWidget(
        map(
          preferredConfiguration: const MKHybridMapConfiguration(
            showsTraffic: true,
            pointOfInterestFilter: .excludingAll,
          ),
        ),
      );
      await tester.pump();

      final config = host.initializeParams().configuration;
      check(config.kind).equals(.hybrid);
      check(config.showsTraffic).isTrue();
      check(config.pointOfInterestFilter)
          .isNotNull()
          .has((f) => f.mode, 'mode')
          .equals(.none);
    });
  });

  group('didUpdateWidget', () {
    testWidgets('diffs annotation sets into update calls', (tester) async {
      await tester.pumpWidget(map(annotations: {annotation('a')}));
      await tester.pump();

      await tester.pumpWidget(
        map(
          annotations: {
            annotation('a', coordinate: infiniteLoop),
            annotation('b'),
          },
        ),
      );
      await tester.pump();

      host.expectCalls(['initialize', 'updateAnnotations']);
      final (toAdd, toChange, idsToRemove) = host.calls
          .expectLastArgs<AnnotationUpdate>('updateAnnotations');
      check(toAdd).length.equals(1);
      check(toAdd.single.id).equals('b');
      check(toChange).length.equals(1);
      check(toChange.single.id).equals('a');
      check(idsToRemove).isEmpty();
    });

    testWidgets('an icon-only restyle routes to toChange with the new tint', (
      tester,
    ) async {
      MKPointAnnotation marker(Color tint) => .new(
        id: const .new('a'),
        coordinate: applePark,
        icon: .marker(markerTintColor: tint),
      );

      await tester.pumpWidget(
        map(annotations: {marker(const .new(0xFF3F51B5))}),
      );
      await tester.pump();

      // Same id and coordinate; only the marker tint changes — the in-place
      // update path the 0.2.2 marker-restyle fix depends on.
      await tester.pumpWidget(
        map(annotations: {marker(const .new(0xFFFF5722))}),
      );
      await tester.pump();

      host.expectCalls(['initialize', 'updateAnnotations']);
      final (toAdd, toChange, idsToRemove) = host.calls
          .expectLastArgs<AnnotationUpdate>('updateAnnotations');
      check(toAdd).isEmpty();
      check(idsToRemove).isEmpty();
      check(toChange).length.equals(1);
      check(toChange.single.id).equals('a');
      check(toChange.single.icon.markerTintArgb).equals(0xFFFF5722);
    });

    testWidgets('routes each overlay kind to its own update call', (
      tester,
    ) async {
      await tester.pumpWidget(map(polylines: {polyline('p')}));
      await tester.pump();

      await tester.pumpWidget(
        map(polylines: {}, polygons: {polygon('g')}, circles: {circle('c')}),
      );
      await tester.pump();

      host.expectCalls([
        'initialize',
        'updatePolylines',
        'updatePolygons',
        'updateCircles',
      ]);
      final (_, _, removedPolylines) = host.calls.requireArgsAt<PolylineUpdate>(
        1,
      );
      check(removedPolylines).deepEquals(['p']);
    });

    testWidgets('Sets mutated in place diff against what was sent', (
      tester,
    ) async {
      final annotations = {annotation('a')};
      final polylines = <MKPolyline>{};
      final polygons = <MKPolygon>{};
      final circles = <MKCircle>{};
      final features = <MKMapFeatureOptions>{};
      Widget build() => map(
        annotations: annotations,
        polylines: polylines,
        polygons: polygons,
        circles: circles,
        selectableMapFeatures: features,
      );
      await tester.pumpWidget(build());
      await tester.pump();

      annotations.add(annotation('b'));
      polylines.add(polyline('p'));
      polygons.add(polygon('g'));
      circles.add(circle('c'));
      features.add(.pointsOfInterest);
      await tester.pumpWidget(build());
      await tester.pump();

      host.expectCalls([
        'initialize',
        'updateMapConfiguration',
        'updateAnnotations',
        'updatePolylines',
        'updatePolygons',
        'updateCircles',
      ]);
      final (added, _, _) = host.calls.requireArgsAt<AnnotationUpdate>(2);
      check(added.map((a) => a.id)).deepEquals(['b']);
    });

    testWidgets('initialize ignores Sets mutated in onMapCreated', (
      tester,
    ) async {
      final annotations = {annotation('a')};
      final polylines = <MKPolyline>{};
      final polygons = <MKPolygon>{};
      final circles = <MKCircle>{};
      Widget build() => map(
        annotations: annotations,
        polylines: polylines,
        polygons: polygons,
        circles: circles,
        onMapCreated: (_) {
          annotations.add(annotation('b'));
          polylines.add(polyline('p'));
          polygons.add(polygon('g'));
          circles.add(circle('c'));
        },
      );
      await tester.pumpWidget(build());
      await tester.pump();

      final params = host.initializeParams();
      check(params.annotations.map((a) => a.id)).deepEquals(['a']);
      check(params.polylines).isEmpty();
      check(params.polygons).isEmpty();
      check(params.circles).isEmpty();

      await tester.pumpWidget(build());
      await tester.pump();

      host.expectCalls([
        'initialize',
        'updateAnnotations',
        'updatePolylines',
        'updatePolygons',
        'updateCircles',
      ]);
      final (added, _, _) = host.calls.requireArgsAt<AnnotationUpdate>(1);
      check(added.map((a) => a.id)).deepEquals(['b']);
    });

    testWidgets('pushes one configuration update when a view prop changes', (
      tester,
    ) async {
      await tester.pumpWidget(map());
      await tester.pump();

      await tester.pumpWidget(
        map(
          isZoomEnabled: false,
          showsUserLocation: true,
          cameraZoomRange: .new(minCenterCoordinateDistance: 500),
        ),
      );
      await tester.pump();

      host.expectCalls(['initialize', 'updateMapConfiguration']);
      final config = host.calls.expectLastArgs<PlatformMapConfiguration>(
        'updateMapConfiguration',
      );
      check(config.isZoomEnabled).isFalse();
      check(config.showsUserLocation).isTrue();
      check(config.cameraZoomRange)
          .isNotNull()
          .has(
            (r) => r.minCenterCoordinateDistance,
            'minCenterCoordinateDistance',
          )
          .equals(500);
    });

    testWidgets('pushes a configuration update when the base style changes', (
      tester,
    ) async {
      await tester.pumpWidget(map());
      await tester.pump();

      await tester.pumpWidget(
        map(preferredConfiguration: const MKImageryMapConfiguration()),
      );
      await tester.pump();

      final config = host.calls.expectLastArgs<PlatformMapConfiguration>(
        'updateMapConfiguration',
      );
      check(config.kind).equals(.imagery);
      check(config.pointOfInterestFilter).isNull();
    });

    testWidgets('identical rebuild sends nothing', (tester) async {
      await tester.pumpWidget(map(annotations: {annotation('a')}));
      await tester.pump();

      await tester.pumpWidget(map(annotations: {annotation('a')}));
      await tester.pump();

      check(host.callNames).deepEquals(['initialize']);
    });
  });

  group('updates native rejects', () {
    final rejected = PlatformException(code: 'invalid-icon');

    // A rejected widget-driven push has no caller: it surfaces as an uncaught
    // error in the zone that built the widget.
    Future<void> pumpRejected(WidgetTester tester, Widget widget) async {
      final uncaught = <Object>[];
      host.errorToThrow = rejected;
      await runZonedGuarded(() async {
        await tester.pumpWidget(widget);
        await tester.pump();
      }, (error, _) => uncaught.add(error));
      check(uncaught).single.isA<MapKitPlatformException>();
    }

    MKPointAnnotation badThenGood(String title) =>
        .new(id: const .new('b'), coordinate: applePark, title: title);

    testWidgets('a fixed annotation arrives with the batch it failed in', (
      tester,
    ) async {
      await tester.pumpWidget(map());
      await tester.pump();

      await pumpRejected(
        tester,
        map(annotations: {annotation('a'), badThenGood('bad')}),
      );

      await tester.pumpWidget(
        map(annotations: {annotation('a'), badThenGood('good')}),
      );
      await tester.pump();

      final AnnotationUpdate(:$1, :$2, :$3) = host.calls.expectLastArgs(
        'updateAnnotations',
      );
      check($1.map((a) => a.id)).deepEquals(['a', 'b']);
      check($1.last.title).equals('good');
      check($2).isEmpty();
      check($3).isEmpty();
    });

    testWidgets('a rebuild that changes nothing does not resend a rejection', (
      tester,
    ) async {
      await tester.pumpWidget(map());
      await tester.pump();
      await pumpRejected(tester, map(annotations: {annotation('a')}));

      await tester.pumpWidget(map(annotations: {annotation('a')}));
      await tester.pump();

      check(host.callNames).deepEquals(['initialize']);
    });

    testWidgets('reverting a rejected change sends nothing', (tester) async {
      await tester.pumpWidget(map(annotations: {annotation('a')}));
      await tester.pump();
      await pumpRejected(
        tester,
        map(annotations: {annotation('a', title: 'x')}),
      );

      await tester.pumpWidget(map(annotations: {annotation('a')}));
      await tester.pump();

      check(host.callNames).deepEquals(['initialize']);
    });

    testWidgets('an accepted update is not resent after a later rejection', (
      tester,
    ) async {
      await tester.pumpWidget(map(annotations: {annotation('a')}));
      await tester.pump();
      await pumpRejected(
        tester,
        map(annotations: {annotation('a'), annotation('b')}),
      );

      await tester.pumpWidget(
        map(annotations: {annotation('a'), annotation('c')}),
      );
      await tester.pump();

      final AnnotationUpdate(:$1) = host.calls.expectLastArgs(
        'updateAnnotations',
      );
      check($1.map((a) => a.id)).deepEquals(['c']);
    });

    testWidgets('a rejected batch keeps its removals for the next one', (
      tester,
    ) async {
      await tester.pumpWidget(
        map(annotations: {annotation('a'), annotation('gone')}),
      );
      await tester.pump();
      await pumpRejected(tester, map(annotations: {annotation('a')}));

      await tester.pumpWidget(
        map(annotations: {annotation('a', title: 'fixed')}),
      );
      await tester.pump();

      final AnnotationUpdate(:$2, :$3) = host.calls.expectLastArgs(
        'updateAnnotations',
      );
      check($2.single.title).equals('fixed');
      check($3).deepEquals(['gone']);
    });

    for (final (name, method, Widget Function(String) build) in [
      (
        'polylines',
        'updatePolylines',
        (String id) => map(polylines: {polyline('kept'), polyline(id)}),
      ),
      (
        'polygons',
        'updatePolygons',
        (String id) => map(polygons: {polygon('kept'), polygon(id)}),
      ),
      (
        'circles',
        'updateCircles',
        (String id) => map(circles: {circle('kept'), circle(id)}),
      ),
    ]) {
      testWidgets('rejected $name arrive with the next batch', (tester) async {
        await tester.pumpWidget(map());
        await tester.pump();
        await pumpRejected(tester, build('first'));

        await tester.pumpWidget(build('second'));
        await tester.pump();

        final (
          List<Object?> toAdd,
          List<Object?> _,
          List<String> _,
        ) = switch (host.calls.lastRecorded()) {
          (name: final called, :final args) when called == method =>
            _overlayUpdate(args),
          final other => fail('expected $method, got $other'),
        };
        check(toAdd.length).equals(2);
      });
    }

    testWidgets('a rejected initialize is retried whole', (tester) async {
      await pumpRejected(
        tester,
        map(annotations: {annotation('a'), badThenGood('bad')}),
      );
      check(host.callNames).isEmpty();

      await tester.pumpWidget(
        map(
          annotations: {annotation('a'), badThenGood('good')},
          isZoomEnabled: false,
        ),
      );
      await tester.pump();

      final params = host.initializeParams();
      check(params.initialCamera?.distance).equals(sampleCamera.distance);
      check(params.configuration.isZoomEnabled).isFalse();
      check(params.annotations.map((a) => a.title)).deepEquals([null, 'good']);

      await tester.pumpWidget(
        map(
          annotations: {annotation('a'), badThenGood('good')},
          isZoomEnabled: false,
        ),
      );
      await tester.pump();
      check(host.callNames).deepEquals(['initialize']);
    });

    testWidgets(
      'a multi-slice rebuild after a rejected initialize retries once',
      (tester) async {
        await pumpRejected(tester, map(annotations: {badThenGood('bad')}));

        host
          ..attemptedCallNames.clear()
          ..errorToThrow = rejected
          ..keepThrowing = true;
        final uncaught = <Object>[];
        await runZonedGuarded(() async {
          await tester.pumpWidget(
            map(
              isZoomEnabled: false,
              annotations: {badThenGood('still-bad')},
              polylines: {polyline('p')},
              polygons: {polygon('g')},
              circles: {circle('c')},
            ),
          );
          await tester.pump();
        }, (error, _) => uncaught.add(error));

        check(host.attemptedCallNames).deepEquals(['initialize']);
        check(uncaught).single.isA<MapKitPlatformException>();

        host
          ..keepThrowing = false
          ..errorToThrow = null;
        await tester.pumpWidget(
          map(
            isZoomEnabled: false,
            annotations: {badThenGood('good')},
            polylines: {polyline('p')},
            polygons: {polygon('g')},
            circles: {circle('c')},
          ),
        );
        await tester.pump();

        check(host.callNames).deepEquals(['initialize']);
        final params = host.initializeParams();
        check(params.configuration.isZoomEnabled).isFalse();
        check(params.annotations.single.title).equals('good');
        check(params.polylines.single.id).equals('p');
        check(params.polygons.single.id).equals('g');
        check(params.circles.single.id).equals('c');
      },
    );

    group('a move accepted after a rejected initialize', () {
      Future<void> mountRejected(
        WidgetTester tester,
        void Function(MKMapViewController) onMapCreated,
      ) => pumpRejected(
        tester,
        map(annotations: {badThenGood('bad')}, onMapCreated: onMapCreated),
      );

      Future<PlatformMapViewCreationParams> retry(WidgetTester tester) async {
        await tester.pumpWidget(map(annotations: {badThenGood('good')}));
        await tester.pump();
        return host.calls.expectLastArgs<PlatformMapViewCreationParams>(
          'initialize',
        );
      }

      final moved = CLLocationCoordinate2D(latitude: 1, longitude: 2);

      testWidgets('setCamera survives the retry', (tester) async {
        await mountRejected(
          tester,
          (c) => c.setCamera(.new(centerCoordinate: moved, distance: 5)),
        );
        check(host.callNames).deepEquals(['setCamera']);

        check((await retry(tester)).initialCamera).isNull();
      });

      testWidgets('setRegion survives the retry', (tester) async {
        await mountRejected(
          tester,
          (c) => c.setRegion(
            .new(
              center: moved,
              span: .new(latitudeDelta: 1, longitudeDelta: 1),
            ),
          ),
        );

        check((await retry(tester)).initialCamera).isNull();
      });

      testWidgets('setCenter keeps the rest of the initial camera', (
        tester,
      ) async {
        final tilted = MKMapCamera(
          centerCoordinate: applePark,
          distance: 900,
          heading: 45,
          pitch: 30,
        );
        Widget tiltedMap(
          String title, {
          void Function(MKMapViewController)? onMapCreated,
        }) => MKMapView(
          initialCamera: tilted,
          annotations: {badThenGood(title)},
          onMapCreated: onMapCreated,
          debugControllerFactory: controllerFactory,
        );
        await pumpRejected(
          tester,
          tiltedMap('bad', onMapCreated: (c) => c.setCenter(moved)),
        );

        await tester.pumpWidget(tiltedMap('good'));
        await tester.pump();

        final camera = host.calls
            .expectLastArgs<PlatformMapViewCreationParams>('initialize')
            .initialCamera;
        check(camera?.centerCoordinate.latitude).equals(1);
        check(camera?.centerCoordinate.longitude).equals(2);
        check(camera?.distance).equals(900);
        check(camera?.heading).equals(45);
        check(camera?.pitch).equals(30);
      });

      testWidgets('a move native rejected leaves the initial camera', (
        tester,
      ) async {
        MKMapViewController? controller;
        await mountRejected(tester, (c) => controller = c);
        final created = controller;
        if (created == null) fail('onMapCreated never ran');

        host.errorToThrow = rejected;
        await check(
          created.setCamera(.new(centerCoordinate: moved, distance: 5)),
        ).throws<MapKitPlatformException>();

        check((await retry(tester)).initialCamera?.distance)
            .equals(sampleCamera.distance);
      });
    });

    testWidgets('rebuilds queued behind a call diff against what it accepted', (
      tester,
    ) async {
      await tester.pumpWidget(map());
      await tester.pump();
      final gate = Completer<void>();
      host.snapshotGate = gate.future;
      final snapshot = requireCreated().takeSnapshot();
      await tester.pumpWidget(map(annotations: {annotation('a')}));
      await tester.pumpWidget(
        map(annotations: {annotation('a'), annotation('b')}),
      );

      gate.complete();
      await snapshot;
      await tester.pump();

      check(host.callNames)
          .deepEquals(['initialize', 'takeSnapshot', 'updateAnnotations']);
    });
  });

  group('unmounting with widget-driven updates queued', () {
    testWidgets('drops them without an error', (tester) async {
      await tester.pumpWidget(map());
      await tester.pump();
      final gate = Completer<void>();
      host.snapshotGate = gate.future;
      final snapshot = requireCreated().takeSnapshot();

      await tester.pumpWidget(
        map(
          annotations: {annotation('a')},
          polylines: {polyline('p')},
          polygons: {polygon('g')},
          circles: {circle('c')},
          isZoomEnabled: false,
        ),
      );
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await snapshot;
      await tester.pump();

      check(tester.takeException()).isNull();
      check(host.callNames)
          .deepEquals(['initialize', 'dispose', 'takeSnapshot']);
    });

    testWidgets('user-called methods still throw', (tester) async {
      await tester.pumpWidget(map());
      await tester.pump();
      final controller = requireCreated();
      await tester.pumpWidget(const SizedBox());

      await check(controller.setCamera(sampleCamera))
          .throws<MapKitDisposedException>();
    });
  });

  group('inbound events', () {
    testWidgets('map taps and long presses reach the widget callbacks', (
      tester,
    ) async {
      CLLocationCoordinate2D? tapped;
      CLLocationCoordinate2D? longPressed;
      await tester.pumpWidget(
        map(onTap: (c) => tapped = c, onLongPress: (c) => longPressed = c),
      );
      await tester.pump();

      requireCreated().eventHandler
        ..onMapTap(platformCoord(1, 2))
        ..onMapLongPress(platformCoord(3, 4));
      check(tapped).equals(.new(latitude: 1, longitude: 2));
      check(longPressed).equals(.new(latitude: 3, longitude: 4));
    });

    testWidgets('camera lifecycle events reach the widget callbacks', (
      tester,
    ) async {
      final events = <String>[];
      MKMapCamera? movedCamera;
      await tester.pumpWidget(
        map(
          onCameraMoveStarted: () => events.add('started'),
          onCameraMove: (c) {
            events.add('move');
            movedCamera = c;
          },
          onCameraIdle: () => events.add('idle'),
        ),
      );
      await tester.pump();

      requireCreated().eventHandler
        ..onCameraMoveStarted()
        ..onCameraMove(platformCamera(latitude: 5, longitude: 6, distance: 700))
        ..onCameraIdle();
      check(events).deepEquals(['started', 'move', 'idle']);
      check(movedCamera).equals(
        .new(centerCoordinate: .new(latitude: 5, longitude: 6), distance: 700),
      );
    });

    testWidgets('annotation selection reaches the matching annotation', (
      tester,
    ) async {
      var selectCount = 0;
      final selectable = MKPointAnnotation(
        id: const .new('a'),
        coordinate: applePark,
        onSelect: () => selectCount++,
      );
      await tester.pumpWidget(map(annotations: {selectable}));
      await tester.pump();

      requireCreated().eventHandler
        ..onAnnotationSelect('a')
        ..onAnnotationSelect('missing');
      check(selectCount).equals(1);
    });

    testWidgets('annotation select fires the latest closure after a rebuild', (
      tester,
    ) async {
      var fired = '';
      MKPointAnnotation tappable(String tag) => .new(
        id: const .new('a'),
        coordinate: applePark,
        onSelect: () => fired = tag,
      );

      await tester.pumpWidget(map(annotations: {tappable('first')}));
      await tester.pump();

      // Visually identical annotation (same id/coordinate/icon), fresh
      // onSelect.
      // The two are `==`-equal, so `setEquals` skips the native update — proven
      // by no updateAnnotations call — yet the dispatch table must still adopt
      // the new closure, or the tap would fire stale captured state.
      await tester.pumpWidget(map(annotations: {tappable('second')}));
      await tester.pump();

      check(host.callNames).deepEquals(['initialize']);
      requireCreated().eventHandler.onAnnotationSelect('a');
      check(fired).equals('second');
    });

    testWidgets(
      'callout tap and drag callbacks fire the latest closures after a rebuild',
      (tester) async {
        final events = <String>[];
        MKPointAnnotation interactive(String tag) => .new(
          id: const .new('a'),
          coordinate: applePark,
          title: 'title',
          isDraggable: true,
          calloutConsumesTapEvents: true,
          onCalloutTap: () => events.add('callout-$tag'),
          onDragStart: (c) => events.add('start-$tag:${c.latitude}'),
          onDragEnd: (c) => events.add('end-$tag:${c.latitude}'),
        );

        await tester.pumpWidget(map(annotations: {interactive('first')}));
        await tester.pump();
        await tester.pumpWidget(map(annotations: {interactive('second')}));
        await tester.pump();

        requireCreated().eventHandler
          ..onCalloutTap('a')
          ..onAnnotationDragStart('a', platformCoord(1, 2))
          ..onAnnotationDragEnd('a', platformCoord(3, 4));
        check(
          events,
        ).deepEquals(['callout-second', 'start-second:1.0', 'end-second:3.0']);
      },
    );

    testWidgets(
      'overlay tap callbacks fire the latest closures after a rebuild',
      (tester) async {
        final events = <String>[];
        Widget buildOverlays(String tag) => map(
          polylines: {
            polyline('line').copyWith(
              consumeTapEvents: true,
              onTap: () => events.add('line-$tag'),
            ),
          },
          polygons: {
            polygon('poly').copyWith(
              consumeTapEvents: true,
              onTap: () => events.add('poly-$tag'),
            ),
          },
          circles: {
            circle('circ').copyWith(
              consumeTapEvents: true,
              onTap: () => events.add('circ-$tag'),
            ),
          },
        );

        await tester.pumpWidget(buildOverlays('first'));
        await tester.pump();
        await tester.pumpWidget(buildOverlays('second'));
        await tester.pump();

        requireCreated().eventHandler
          ..onPolylineTap('line')
          ..onPolygonTap('poly')
          ..onCircleTap('circ');
        check(events).deepEquals(['line-second', 'poly-second', 'circ-second']);
      },
    );

    testWidgets('failure events reach the widget callbacks', (tester) async {
      String? loadError;
      String? locateError;
      await tester.pumpWidget(
        map(
          onDidFailLoadingMap: (e) => loadError = e,
          onDidFailToLocateUser: (e) => locateError = e,
        ),
      );
      await tester.pump();

      requireCreated().eventHandler
        ..onDidFailLoadingMap('offline')
        ..onDidFailToLocateUser('denied');
      check(loadError).equals('offline');
      check(locateError).equals('denied');
    });

    testWidgets('select and deselect reach the latest closures', (
      tester,
    ) async {
      final events = <String>[];
      MKPointAnnotation selectable(String tag) => .new(
        id: const .new('a'),
        coordinate: applePark,
        onSelect: () => events.add('select-$tag'),
        onDeselect: () => events.add('deselect-$tag'),
      );
      await tester.pumpWidget(map(annotations: {selectable('first')}));
      await tester.pump();
      await tester.pumpWidget(map(annotations: {selectable('second')}));
      await tester.pump();

      requireCreated().eventHandler
        ..onAnnotationSelect('a')
        ..onAnnotationDeselect('a')
        ..onAnnotationSelect('missing');
      check(events).deepEquals(['select-second', 'deselect-second']);
    });

    testWidgets('a tracking-mode change reaches onUserTrackingModeChanged', (
      tester,
    ) async {
      final modes = <MKUserTrackingMode>[];
      await tester.pumpWidget(
        MKMapView(
          initialCamera: sampleCamera,
          userTrackingMode: .follow,
          onUserTrackingModeChanged: modes.add,
          debugControllerFactory: controllerFactory,
        ),
      );
      await tester.pump();

      requireCreated().eventHandler.onUserTrackingModeChanged(.none);
      check(modes).deepEquals([MKUserTrackingMode.none]);
    });

    testWidgets('a selected map feature reaches onMapFeatureSelected', (
      tester,
    ) async {
      MKMapFeature? selected;
      await tester.pumpWidget(
        map(
          selectableMapFeatures: const {.pointsOfInterest},
          onMapFeatureSelected: (f) => selected = f,
        ),
      );
      await tester.pump();

      requireCreated().eventHandler.onMapFeatureSelected(
        .new(
          featureType: .territory,
          coordinate: platformCoord(1, 2),
          title: 'Cupertino',
          pointOfInterestCategory: .evCharger,
        ),
      );
      check(selected).equals(
        .new(
          featureType: .territory,
          coordinate: .new(latitude: 1, longitude: 2),
          title: 'Cupertino',
          pointOfInterestCategory: .evCharger,
        ),
      );
    });
  });

  group('callbacks that could never fire', () {
    testWidgets('onMapFeatureSelected needs selectableMapFeatures', (
      tester,
    ) async {
      await tester.pumpWidget(map(onMapFeatureSelected: (_) {}));
      check(tester.takeException())
          .isA<ArgumentError>()
          .has((e) => e.name, 'name')
          .equals('onMapFeatureSelected');
    });

    testWidgets('a rebuild that empties selectableMapFeatures throws', (
      tester,
    ) async {
      await tester.pumpWidget(
        map(
          selectableMapFeatures: const {.pointsOfInterest},
          onMapFeatureSelected: (_) {},
        ),
      );
      check(tester.takeException()).isNull();
      await tester.pumpWidget(map(onMapFeatureSelected: (_) {}));
      check(tester.takeException()).isA<ArgumentError>();
    });

    testWidgets('onDidFailToLocateUser stays valid when a gesture drops the '
        'tracking mode', (tester) async {
      Widget tracking(MKUserTrackingMode mode) => MKMapView(
        initialCamera: sampleCamera,
        userTrackingMode: mode,
        onUserTrackingModeChanged: (_) {},
        onDidFailToLocateUser: (_) {},
        debugControllerFactory: controllerFactory,
      );
      await tester.pumpWidget(tracking(.follow));
      await tester.pump();

      await tester.pumpWidget(tracking(.none));

      check(tester.takeException()).isNull();
    });
  });

  group('iOS-only settings on macOS', () {
    final cases = <String, MKMapView Function(MKMapViewEventSinkFactory)>{
      'followWithHeading': (f) => .new(
        initialCamera: sampleCamera,
        userTrackingMode: .followWithHeading,
        debugControllerFactory: f,
      ),
      'selectableMapFeatures': (f) => .new(
        initialCamera: sampleCamera,
        selectableMapFeatures: const {.pointsOfInterest},
        debugControllerFactory: f,
      ),
      'onMapFeatureSelected': (f) => .new(
        initialCamera: sampleCamera,
        selectableMapFeatures: const {.pointsOfInterest},
        onMapFeatureSelected: (_) {},
        debugControllerFactory: f,
      ),
      'insetsLayoutMarginsFromSafeArea': (f) => .new(
        initialCamera: sampleCamera,
        insetsLayoutMarginsFromSafeArea: false,
        debugControllerFactory: f,
      ),
      'calloutConsumesTapEvents': (f) => .new(
        initialCamera: sampleCamera,
        annotations: {
          .new(
            id: const .new('a'),
            coordinate: applePark,
            calloutConsumesTapEvents: true,
          ),
        },
        debugControllerFactory: f,
      ),
    };

    for (final MapEntry(key: name, value: build) in cases.entries) {
      testWidgets('$name throws on macOS instead of being ignored', (
        tester,
      ) async {
        await tester.pumpWidget(build(controllerFactory));
        check(tester.takeException())
            .isA<MapKitUnsupportedPlatformException>()
            .has((e) => e.feature, 'feature')
            .isNotNull()
            .contains(name);
        check(host.callNames).isEmpty();
      }, variant: TargetPlatformVariant.only(.macOS));

      testWidgets('$name is accepted on iOS', (tester) async {
        await tester.pumpWidget(build(controllerFactory));
        check(tester.takeException()).isNull();
      }, variant: TargetPlatformVariant.only(.iOS));
    }

    testWidgets('a rebuild that adds an iOS-only setting throws on macOS', (
      tester,
    ) async {
      await tester.pumpWidget(
        MKMapView(
          initialCamera: sampleCamera,
          debugControllerFactory: controllerFactory,
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        MKMapView(
          initialCamera: sampleCamera,
          userTrackingMode: .followWithHeading,
          debugControllerFactory: controllerFactory,
        ),
      );
      check(tester.takeException()).isA<MapKitUnsupportedPlatformException>();
    }, variant: TargetPlatformVariant.only(.macOS));
  });
}

(List<Object?>, List<Object?>, List<String>) _overlayUpdate(Object? args) =>
    switch (args) {
      (
        final List<Object?> toAdd,
        final List<Object?> toChange,
        final List<String> idsToRemove,
      ) =>
        (toAdd, toChange, idsToRemove),
      _ => fail('expected an overlay update, got $args'),
    };

typedef MKMapViewEventSinkFactory = MKMapViewControllerImpl Function(
  MKMapViewEventSink sink,
);
