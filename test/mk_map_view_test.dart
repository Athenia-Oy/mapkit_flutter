import 'package:checks/checks.dart';
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
      check(params.initialCamera.distance).equals(sampleCamera.distance);
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
      await tester.pumpWidget(map(onMapFeatureSelected: (f) => selected = f));
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

typedef MKMapViewEventSinkFactory = MKMapViewControllerImpl Function(
  MKMapViewEventSink sink,
);
