// Run with `flutter test --platform chrome test/mk_map_view_web_test.dart`.
// `kIsWeb` is const, so only a browser build can exercise the web branch; this
// run also proves the library still compiles for the web.
@TestOn('browser')
library;

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

import '_helpers/fixtures.dart';

void main() {
  testWidgets('a browser gets the unsupported exception', (tester) async {
    await tester.pumpWidget(MKMapView(initialCamera: sampleCamera));
    final exception = tester.takeException();

    check(exception)
        .isA<MapKitUnsupportedPlatformException>()
        .has((e) => e.toString(), 'toString')
        .contains('the web');
  }, variant: const TargetPlatformVariant({.iOS, .macOS}));

  testWidgets('a macOS browser does not report iOS-only settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      MKMapView(
        initialCamera: sampleCamera,
        selectableMapFeatures: const {.pointsOfInterest},
      ),
    );
    final exception = tester.takeException();

    check(exception)
        .isA<MapKitUnsupportedPlatformException>()
        .has((e) => e.feature, 'feature')
        .isNull();
  }, variant: TargetPlatformVariant.only(.macOS));
}
