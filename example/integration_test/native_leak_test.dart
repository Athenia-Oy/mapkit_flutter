// Leak oracle (native): after an MKMapView widget unmounts, its native
// MapKitViewHost must stop answering Pigeon host calls. If the per-view
// channel still replies, the host (and its MKMapView + CLLocationManager) is
// still alive. On macOS this also catches a nil handler left registered on a
// channel: the next message to it crashes the app.
import 'dart:async';

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';
import 'package:mapkit_flutter/src/messages.g.dart';

Future<bool> answers(int id) async {
  try {
    await MapKitHostApi(messageChannelSuffix: '$id').getCamera();
    return true;
  } on PlatformException {
    return false;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('disposed maps stop answering host calls', (tester) async {
    check(await answers(999), because: 'control: unknown id').isFalse();

    final live = <int>[];
    for (var round = 0; round < 3; round++) {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 300,
            height: 300,
            child: MKMapView(
              initialCamera: .new(
                centerCoordinate: .new(latitude: 37.33, longitude: -122),
                distance: 2000,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const .new(milliseconds: 200));
      await Future<void>.delayed(const .new(milliseconds: 500));
      for (var id = 0; id < 100; id++) {
        if (!live.contains(id) && await answers(id)) live.add(id);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await Future<void>.delayed(const .new(milliseconds: 500));
    }
    debugPrint('leak-oracle map view ids seen alive while mounted: $live');
    check(live, because: 'probe found each mounted map').length.equals(3);

    final stillAnswering = [
      for (final id in live)
        if (await answers(id)) id,
    ];
    debugPrint(
      'leak-oracle ids still answering after unmount: $stillAnswering',
    );
    check(stillAnswering, because: 'native hosts leaked').isEmpty();
  });

  // Flutter skips onPlatformViewCreated for a view unmounted while its creation
  // is in flight, so Dart never sends `dispose`: only the engine dropping the
  // platform view can release the host. Holding the `create` reply back makes
  // the race deterministic; native has already built the view by then.
  testWidgets('a map unmounted before creation finishes stops answering', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = SystemChannels.platform_views;
    final releaseCreate = Completer<void>();
    final created = Completer<int>();
    messenger.setMockMessageHandler(channel.name, (message) async {
      final reply = await messenger.delegate.send(channel.name, message);
      if (message != null) {
        final call = channel.codec.decodeMethodCall(message);
        if (call.method == 'create' && !created.isCompleted) {
          created.complete((call.arguments as Map)['id'] as int);
          await releaseCreate.future;
        }
      }
      return reply;
    });
    addTearDown(() => messenger.setMockMessageHandler(channel.name, null));

    var mapCreated = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 300,
          child: MKMapView(
            initialCamera: .new(
              centerCoordinate: .new(latitude: 37.33, longitude: -122),
              distance: 2000,
            ),
            onMapCreated: (_) => mapCreated = true,
          ),
        ),
      ),
    );
    final id = await created.future;
    await tester.pumpWidget(const SizedBox());
    check(await answers(id), because: 'control: native built it').isTrue();

    releaseCreate.complete();
    // The iOS engine only releases a disposed view while submitting a frame
    // that composites a platform view, so one has to come along.
    MKMapViewController? next;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 300,
          child: MKMapView(
            initialCamera: .new(
              centerCoordinate: .new(latitude: 37.33, longitude: -122),
              distance: 2000,
            ),
            onMapCreated: (c) => next = c,
          ),
        ),
      ),
    );
    final deadline = DateTime.now().add(const .new(seconds: 60));
    var stillAnswering = true;
    while (stillAnswering && DateTime.now().isBefore(deadline)) {
      await tester.pump(const .new(milliseconds: 100));
      await Future<void>.delayed(const .new(milliseconds: 100));
      if (await next?.region == null) continue;
      stillAnswering = await answers(id);
    }

    check(mapCreated, because: 'the race must really be lost').isFalse();
    check(stillAnswering, because: 'native host leaked').isFalse();
  });
}
