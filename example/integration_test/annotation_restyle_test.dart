import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';
import 'package:mapkit_flutter_example/custom_marker_image.dart';

/// Drives the marker-restyle fix against a real `MKMapView`: rapid in-place
/// restyles, an icon-type swap, and a remove→re-add (dequeue-reuse) cycle, then
/// confirms selection still round-trips. A Swift-side regression in the update
/// or reuse path would surface here as a thrown exception or a dead channel.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final applePark = CLLocationCoordinate2D(
    latitude: 37.334922,
    longitude: -122.009033,
  );
  const id = MKAnnotationId('restyle');

  const description =
      'in-place restyle, reuse, and callout stay healthy on a live map';

  testWidgets(description, (tester) async {
    MKMapViewController? controller;

    Widget mapWith(Set<MKPointAnnotation> annotations) => MaterialApp(
      home: MKMapView(
        initialCamera: .new(centerCoordinate: applePark, distance: 1500),
        annotations: annotations,
        onMapCreated: (c) => controller ??= c,
      ),
    );

    Future<void> pump(Set<MKPointAnnotation> annotations) async {
      await tester.pumpWidget(mapWith(annotations));
      await tester.pump(const .new(milliseconds: 300));
    }

    MKPointAnnotation marker({Color? tint, String? glyph, String? subtitle}) =>
        .new(
          id: id,
          coordinate: applePark,
          icon: .marker(markerTintColor: tint, systemImage: glyph),
          title: 'Restyle',
          subtitle: subtitle,
        );

    // Initial marker — wait for the platform view to reach onMapCreated.
    await pump({marker(tint: Colors.indigo, glyph: 'star.fill')});
    final deadline = DateTime.now().add(const .new(seconds: 15));
    while (controller == null && DateTime.now().isBefore(deadline)) {
      await tester.pump(const .new(milliseconds: 100));
    }
    final ctrl = controller;
    if (ctrl == null) {
      fail('platform view never reached onMapCreated');
    }

    // In-place restyle cycle: same id, new icon each frame. Includes clearing
    // tint and glyph back to null (reset to MapKit defaults).
    await pump({marker(tint: Colors.orange, glyph: 'flag.fill')});
    await pump({marker(glyph: 'bolt.fill')});
    await pump({marker(tint: Colors.green)});

    // Icon-type swap: marker → custom image → marker.
    final png = await renderCircleMarkerPng(Colors.purple);
    await pump({
      .new(id: id, coordinate: applePark, icon: .image(png), title: 'Restyle'),
    });
    await pump({marker(tint: Colors.teal)});

    // Remove, then re-add the same id with new styling — the dequeue-reuse
    // path.
    await pump(const {});
    await pump({
      marker(tint: Colors.pink, glyph: 'heart.fill', subtitle: 'reused'),
    });

    // Selection still round-trips on the reused, restyled annotation.
    check(await ctrl.selectAnnotation(id)).isTrue();
    var shown = false;
    while (!shown && DateTime.now().isBefore(deadline)) {
      await tester.pump(const .new(milliseconds: 150));
      shown = await ctrl.isAnnotationSelected(id);
    }
    check(shown, because: 'selection never took on the reused pin').isTrue();

    check(await ctrl.deselectAnnotation(id)).isTrue();
    await tester.pump(const .new(milliseconds: 300));
    check(await ctrl.isAnnotationSelected(id)).isFalse();

    // The channel is still responsive after every restyle.
    check(await ctrl.camera)
        .isNotNull()
        .has((c) => c.distance, 'distance')
        .isGreaterThan(0);
    check(tester.takeException()).isNull();
  });
}
