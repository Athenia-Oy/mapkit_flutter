// Leak oracle (native): after an MKMapView widget unmounts, its native
// MapKitViewHost must stop answering Pigeon host calls. If the per-view
// channel still replies, the host (and its MKMapView + CLLocationManager) is
// still alive. On macOS this also catches a nil handler left registered on a
// channel: the next message to it crashes the app.
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
      for (var id = 0; id < 20; id++) {
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
}
