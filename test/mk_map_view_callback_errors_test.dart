// A throwing callback must reach FlutterError, through the real Pigeon
// channel: an error reply would be dropped by the native side, so a callback
// exception would otherwise vanish in every build mode.
import 'package:checks/checks.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';
import 'package:mapkit_flutter/src/messages.g.dart';

import '_helpers/fixtures.dart';

const MessageCodec<Object?> _codec = MapKitHostApi.pigeonChannelCodec;

void main() {
  void boom(String name) => throw StateError('boom:$name');

  Widget map() => Directionality(
    textDirection: .ltr,
    child: MKMapView(
      initialCamera: sampleCamera,
      showsUserLocation: true,
      selectableMapFeatures: const {.pointsOfInterest},
      annotations: {
        .new(
          id: const .new('a'),
          coordinate: applePark,
          title: 'title',
          isDraggable: true,
          calloutConsumesTapEvents: true,
          onSelect: () => boom('onAnnotationSelect'),
          onDeselect: () => boom('onAnnotationDeselect'),
          onDragStart: (_) => boom('onAnnotationDragStart'),
          onDragEnd: (_) => boom('onAnnotationDragEnd'),
          onCalloutTap: () => boom('onCalloutTap'),
        ),
      },
      polylines: {
        .new(
          id: const .new('l'),
          coordinates: [applePark, infiniteLoop],
          consumeTapEvents: true,
          onTap: () => boom('onPolylineTap'),
        ),
      },
      polygons: {
        .new(
          id: const .new('g'),
          coordinates: [applePark, infiniteLoop, sampleCamera.centerCoordinate],
          consumeTapEvents: true,
          onTap: () => boom('onPolygonTap'),
        ),
      },
      circles: {
        .new(
          id: const .new('c'),
          center: applePark,
          radius: 10,
          consumeTapEvents: true,
          onTap: () => boom('onCircleTap'),
        ),
      },
      onCameraMoveStarted: () => boom('onCameraMoveStarted'),
      onCameraMove: (_) => boom('onCameraMove'),
      onCameraIdle: () => boom('onCameraIdle'),
      onUserTrackingModeChanged: (_) => boom('onUserTrackingModeChanged'),
      onTap: (_) => boom('onMapTap'),
      onLongPress: (_) => boom('onMapLongPress'),
      onDidFailLoadingMap: (_) => boom('onDidFailLoadingMap'),
      onDidFailToLocateUser: (_) => boom('onDidFailToLocateUser'),
      onMapFeatureSelected: (_) => boom('onMapFeatureSelected'),
    ),
  );

  final coordinate = PlatformCoordinate(latitude: 1, longitude: 2);
  PlatformMapCamera camera({double distance = 100}) => .new(
    centerCoordinate: coordinate,
    distance: distance,
    heading: 0,
    pitch: 0,
  );

  var viewId = 0;

  Future<void> mount(WidgetTester tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        viewId = (call.arguments as Map)['id'] as int;
        messenger.setMockMessageHandler(
          'dev.flutter.pigeon.mapkit_flutter.MapKitHostApi.initialize.$viewId',
          (_) async => _codec.encodeMessage(<Object?>[null]),
        );
      }
      return null;
    });
    await tester.pumpWidget(map());
    await tester.pumpAndSettle();
  }

  Future<List<Object?>?> deliver(
    WidgetTester tester,
    String method,
    List<Object?> args,
  ) async {
    Object? reply;
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'dev.flutter.pigeon.mapkit_flutter.MapKitFlutterApi.$method.$viewId',
      args.isEmpty ? null : _codec.encodeMessage(args),
      (data) => reply = data == null ? null : _codec.decodeMessage(data),
    );
    await tester.pump();
    return switch (reply) {
      final List<Object?> list => list,
      _ => null,
    };
  }

  final events = <String, List<Object?> Function()>{
    'onCameraMoveStarted': () => [],
    'onCameraMove': () => [camera()],
    'onCameraIdle': () => [],
    'onUserTrackingModeChanged': () => [PlatformUserTrackingMode.follow],
    'onAnnotationSelect': () => ['a'],
    'onAnnotationDeselect': () => ['a'],
    'onMapFeatureSelected': () => [
      PlatformMapFeature(featureType: .territory, coordinate: coordinate),
    ],
    'onAnnotationDragStart': () => ['a', coordinate],
    'onAnnotationDragEnd': () => ['a', coordinate],
    'onCalloutTap': () => ['a'],
    'onPolylineTap': () => ['l'],
    'onPolygonTap': () => ['g'],
    'onCircleTap': () => ['c'],
    'onMapTap': () => [coordinate],
    'onMapLongPress': () => [coordinate],
    'onDidFailLoadingMap': () => ['offline'],
    'onDidFailToLocateUser': () => ['denied'],
  };

  for (final MapEntry(key: method, value: args) in events.entries) {
    testWidgets('$method: a throw reaches FlutterError, not the reply', (
      tester,
    ) async {
      await mount(tester);

      final reply = await deliver(tester, method, args());

      check(tester.takeException())
          .isA<StateError>()
          .has((e) => e.message, 'message')
          .equals('boom:$method');
      check(reply).isNotNull().isEmpty();
    }, variant: TargetPlatformVariant.only(.iOS));
  }

  testWidgets('the details name the plugin and the callback', (tester) async {
    await mount(tester);
    final reported = <FlutterErrorDetails>[];
    final original = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = original);

    await deliver(tester, 'onMapTap', [coordinate]);
    FlutterError.onError = original;

    final details = reported.single;
    check(details.library).equals('mapkit_flutter');
    check(details.context.toString()).contains('onMapTap');
    check(details.stack.toString()).contains('boom');
  }, variant: TargetPlatformVariant.only(.iOS));

  testWidgets('a payload the models reject reaches FlutterError too', (
    tester,
  ) async {
    await mount(tester);

    final reply = await deliver(tester, 'onCameraMove', [camera(distance: 0)]);

    check(tester.takeException()).isA<ArgumentError>();
    check(reply).isNotNull().isEmpty();
  }, variant: TargetPlatformVariant.only(.iOS));
}
