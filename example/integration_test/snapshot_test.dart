import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

/// Pixel-level oracle for the iOS snapshot compositor — the only automated
/// coverage of the Swift `drawAnnotations` culling guard and the
/// single-subpath polyline stroke. Each behavior is pinned by diffing a
/// snapshot with the layer enabled against one with it disabled and counting
/// differing pixels inside projected regions (loose thresholds, no exact
/// colors):
///
/// - Culling: a centered marker and an edge-straddling marker must produce
///   diffs in their projected regions; a far off-image marker must not
///   produce diffs in the strip nearest to where it would project. An
///   inverted `frame.intersects(bounds)` guard omits every visible marker
///   and fails the positive assertions.
/// - Polyline: a 2-point polyline must produce diffs along the segment
///   (a move-only path, e.g. `dropFirst(2)`, draws nothing); a 1-point
///   polyline must produce none — the documented draws-nothing behavior,
///   matching `MKPolylineRenderer` (no round-cap dot).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final applePark = CLLocationCoordinate2D(
    latitude: 37.334922,
    longitude: -122.009033,
  );

  /// Pixels whose max channel delta exceeds 32, counted inside [rect]
  /// (clamped to the image). Both images must have identical dimensions.
  int countDiffs(_Rgba a, _Rgba b, Rect rect) {
    final left = rect.left.floor().clamp(0, a.width);
    final right = rect.right.ceil().clamp(0, a.width);
    final top = rect.top.floor().clamp(0, a.height);
    final bottom = rect.bottom.ceil().clamp(0, a.height);
    var count = 0;
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final i = (y * a.width + x) * 4;
        for (var c = 0; c < 4; c++) {
          if ((a.bytes[i + c] - b.bytes[i + c]).abs() > 32) {
            count++;
            break;
          }
        }
      }
    }
    return count;
  }

  int measured(String label, _Rgba a, _Rgba b, Rect rect) {
    final count = countDiffs(a, b, rect);
    debugPrint('snapshot-oracle: $label diff=$count rect=$rect');
    return count;
  }

  testWidgets('snapshot composites culled annotations and polyline strokes', (
    tester,
  ) async {
    MKMapViewController? controller;

    Widget map({
      Set<MKPointAnnotation> annotations = const {},
      Set<MKPolyline> polylines = const {},
    }) => MaterialApp(
      home: MKMapView(
        initialCamera: .new(centerCoordinate: applePark, distance: 1500),
        annotations: annotations,
        polylines: polylines,
        onMapCreated: (c) => controller ??= c,
      ),
    );

    Future<void> pump({
      Set<MKPointAnnotation> annotations = const {},
      Set<MKPolyline> polylines = const {},
    }) async {
      await tester.pumpWidget(
        map(annotations: annotations, polylines: polylines),
      );
      await tester.pump(const .new(milliseconds: 500));
    }

    await pump();
    final deadline = DateTime.now().add(const .new(seconds: 30));
    while (controller == null && DateTime.now().isBefore(deadline)) {
      await tester.pump(const .new(milliseconds: 100));
    }
    final ctrl = controller;
    if (ctrl == null) {
      fail('platform view never reached onMapCreated');
    }

    // The visible region becomes meaningful once the view has layout; a cold
    // simulator can take a while, so this wait gets its own deadline.
    final regionDeadline = DateTime.now().add(const .new(seconds: 45));
    var maybeRegion = await ctrl.region;
    while (maybeRegion == null && DateTime.now().isBefore(regionDeadline)) {
      await tester.pump(const .new(milliseconds: 250));
      maybeRegion = await ctrl.region;
    }
    final region = maybeRegion;
    if (region == null) fail('map region never became meaningful');
    check(region.span.latitudeDelta).isGreaterThan(0);

    // Let tiles settle so paired snapshots share a stable base map.
    await tester.pump(const .new(seconds: 4));

    final viewSize = tester.getSize(find.byType(MKMapView));
    final center = region.center;
    final lonSpan = region.span.longitudeDelta;
    // Straddles the left image edge: projects to x ≈ 0, half the marker
    // frame in-image, so culling must keep it.
    final edgeCoordinate = CLLocationCoordinate2D(
      latitude: center.latitude,
      longitude: center.longitude - lonSpan / 2,
    );
    // Fully off-image: projects 60 logical pt past the right edge, so the
    // drawn frame cannot intersect the image.
    final farCoordinate = CLLocationCoordinate2D(
      latitude: center.latitude,
      longitude: center.longitude + lonSpan * (0.5 + 60 / viewSize.width),
    );

    Future<_Rgba> snap({
      required bool annotations,
      required bool overlays,
    }) async {
      final bytes = await ctrl.takeSnapshot(
        .new(
          showsPointsOfInterest: false,
          showsAnnotations: annotations,
          showsOverlays: overlays,
        ),
      );
      return await .decode(bytes);
    }

    // --- Annotation culling -------------------------------------------------
    await pump(
      annotations: {
        .new(id: const .new('center'), coordinate: center),
        .new(id: const .new('edge'), coordinate: edgeCoordinate),
        .new(id: const .new('far'), coordinate: farCoordinate),
      },
    );

    final annotationsOn = await snap(annotations: true, overlays: false);
    final annotationsOff = await snap(annotations: false, overlays: false);
    check(annotationsOn.width).equals(annotationsOff.width);
    check(annotationsOn.height).equals(annotationsOff.height);
    final pxPerPt = annotationsOn.width / viewSize.width;

    // Projects a coordinate into snapshot pixel space via the live view
    // (same region and size as the snapshotter) and a pt→px scale factor.
    Future<Offset> project(CLLocationCoordinate2D coordinate) async {
      final pt = await ctrl.convertToPoint(coordinate);
      if (pt == null) {
        fail('coordinate failed to project');
      }
      return pt * pxPerPt;
    }

    Rect around(Offset px, double radiusPt) =>
        .fromCircle(center: px, radius: radiusPt * pxPerPt);

    final centerPx = await project(center);
    final edgePx = await project(edgeCoordinate);
    final farPx = await project(farCoordinate);

    check(
      measured(
        'center-marker',
        annotationsOn,
        annotationsOff,
        around(centerPx, 40),
      ),
      because: 'centered marker missing from the snapshot',
    ).isGreaterThan(1000);
    check(
      measured(
        'edge-marker',
        annotationsOn,
        annotationsOff,
        around(edgePx, 40),
      ),
      because: 'edge-straddling marker was culled',
    ).isGreaterThan(500);
    // The rect around the off-image projection clamps to the strip inside
    // the right edge; a marker leaking there means culling (or placement)
    // regressed. A drawn marker diffs in the thousands (center: >5000);
    // the allowance absorbs base-map label/tile noise between the two
    // independent snapshotter runs (observed warm: 20).
    check(
      measured(
        'far-marker-strip',
        annotationsOn,
        annotationsOff,
        around(farPx, 80),
      ),
      because: 'off-image marker leaked pixels near the right edge',
    ).isLessThan(400);

    // --- Polyline strokes ---------------------------------------------------
    final lineStart = CLLocationCoordinate2D(
      latitude: center.latitude,
      longitude: center.longitude - lonSpan / 4,
    );
    final lineEnd = CLLocationCoordinate2D(
      latitude: center.latitude,
      longitude: center.longitude + lonSpan / 4,
    );
    await pump(
      polylines: {
        .new(
          id: const .new('segment'),
          coordinates: [lineStart, lineEnd],
          strokeColor: const .new(0xFFFF00FF),
          lineWidth: 12,
        ),
      },
    );

    final lineOn = await snap(annotations: false, overlays: true);
    final lineOff = await snap(annotations: false, overlays: false);
    final quarterPx = await project(
      .new(
        latitude: center.latitude,
        longitude: center.longitude - lonSpan / 8,
      ),
    );
    check(
      measured('polyline-midpoint', lineOn, lineOff, around(centerPx, 40)),
      because: 'polyline stroke missing at the segment midpoint',
    ).isGreaterThan(1000);
    check(
      measured('polyline-quarter', lineOn, lineOff, around(quarterPx, 40)),
      because: 'polyline stroke missing along the segment',
    ).isGreaterThan(1000);

    // A 1-point polyline draws nothing — no round-cap dot at the vertex
    // (a 12pt dot at 3x would be >1000 px; observed noise stays <100).
    await pump(
      polylines: {
        .new(
          id: const .new('dot'),
          coordinates: [center],
          strokeColor: const .new(0xFFFF00FF),
          lineWidth: 12,
        ),
      },
    );
    final dotOn = await snap(annotations: false, overlays: true);
    final dotOff = await snap(annotations: false, overlays: false);
    check(
      measured('one-point-dot', dotOn, dotOff, around(centerPx, 60)),
      because: 'single-coordinate polyline drew pixels',
    ).isLessThan(400);

    check(tester.takeException()).isNull();
  }, skip: !Platform.isIOS);
}

/// A decoded snapshot: raw RGBA bytes plus dimensions.
final class _Rgba {
  const new(this.bytes, this.width, this.height);

  static Future<_Rgba> decode(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData();
    if (data == null) {
      throw StateError('Failed to decode snapshot RGBA bytes');
    }
    final rgba = _Rgba(.sublistView(data), image.width, image.height);
    image.dispose();
    codec.dispose();
    return rgba;
  }

  final Uint8List bytes;
  final int width;
  final int height;
}
