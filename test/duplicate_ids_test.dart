import 'package:checks/checks.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

import '_helpers/fake_host_api.dart';
import '_helpers/fixtures.dart';

void main() {
  final red = MKPolyline(
    id: const .new('route'),
    coordinates: [applePark, infiniteLoop],
    strokeColor: const .new(0xFFFF0000),
  );
  final blue = MKPolyline(
    id: const .new('route'),
    coordinates: [applePark, infiniteLoop],
    strokeColor: const .new(0xFF0000FF),
  );

  testWidgets('a rebuild introducing a duplicate id throws', (tester) async {
    final host = FakeHostApi();
    Widget map(Set<MKPolyline> polylines) => MKMapView(
      initialCamera: sampleCamera,
      polylines: polylines,
      debugControllerFactory: (sink) =>
          .new(viewId: 901, sink: sink, hostApi: host),
    );
    await tester.pumpWidget(map({red}));
    await tester.pump();
    await tester.pumpWidget(map({red, blue}));
    check(tester.takeException()).isA<ArgumentError>();
  });

  testWidgets('two objects of one kind sharing an id throw', (tester) async {
    final host = FakeHostApi();
    await tester.pumpWidget(
      MKMapView(
        initialCamera: sampleCamera,
        polylines: {red, blue},
        debugControllerFactory: (sink) =>
            .new(viewId: 900, sink: sink, hostApi: host),
      ),
    );
    check(tester.takeException())
        .isA<ArgumentError>()
        .has((e) => '${e.message}', 'message')
        .contains('route');
  });
}
