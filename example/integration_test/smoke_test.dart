import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

/// End-to-end check of the pigeon channel against a real MKMapView: the only
/// automated coverage of the Swift wiring (per-view channel suffix, host
/// handler registration, camera/region marshaling).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final applePark = CLLocationCoordinate2D(
    latitude: 37.334922,
    longitude: -122.009033,
  );

  testWidgets('map initializes and the camera round-trips', (tester) async {
    MKMapViewController? controller;
    await tester.pumpWidget(
      MaterialApp(
        home: MKMapView(
          initialCamera: .new(centerCoordinate: applePark, distance: 1500),
          onMapCreated: (c) => controller = c,
        ),
      ),
    );

    final deadline = DateTime.now().add(const .new(seconds: 15));
    while (controller == null && DateTime.now().isBefore(deadline)) {
      await tester.pump(const .new(milliseconds: 100));
    }
    final ctrl = controller;
    if (ctrl == null) {
      fail('platform view never reached onMapCreated');
    }

    // The visible region exists once the view has layout (null before).
    var maybeRegion = await ctrl.region;
    while (maybeRegion == null && DateTime.now().isBefore(deadline)) {
      await tester.pump(const .new(milliseconds: 250));
      maybeRegion = await ctrl.region;
    }
    final region = maybeRegion;
    if (region == null) fail('map never got a layout');
    check(region.span.latitudeDelta).isGreaterThan(0);
    check(region.center.latitude).isCloseTo(applePark.latitude, 0.05);

    // setCamera → camera round-trip through the host API. MapKit may adjust
    // the exact distance, so assertions stay tolerant.
    await ctrl.setCamera(
      .new(centerCoordinate: applePark, distance: 5000),
      animated: false,
    );
    await tester.pump(const .new(seconds: 1));
    final camera = await ctrl.camera;
    if (camera == null) fail('camera lost its layout');
    final center = camera.centerCoordinate;
    check(center.latitude).isCloseTo(applePark.latitude, 0.05);
    check(center.longitude).isCloseTo(applePark.longitude, 0.05);
    check(camera.distance).isGreaterThan(0);
  });
}
