# mapkit_flutter

[![pub package](https://img.shields.io/pub/v/mapkit_flutter.svg)](https://pub.dev/packages/mapkit_flutter)
[![pub points](https://img.shields.io/pub/points/mapkit_flutter)](https://pub.dev/packages/mapkit_flutter/score)
[![CI](https://github.com/esenmx/mapkit_flutter/actions/workflows/ci.yaml/badge.svg)](https://github.com/esenmx/mapkit_flutter/actions/workflows/ci.yaml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Apple Maps in your Flutter app on iOS and macOS. `mapkit_flutter` shows Apple's
own `MKMapView` as a widget, with pins, clustering, lines and shapes, tile
overlays, snapshots and (on iOS) Look Around.

## Why use it

- **No API key, no extra SDK.** MapKit ships with iOS and macOS.
  `google_maps_flutter` needs a Google Maps API key and bundles Google's Maps
  SDK on iOS, and has no macOS support.
- **No platform view to write.** Doing it yourself means a `UiKitView` /
  `AppKitView`, a platform channel and Swift delegate code. Here, pins and
  shapes are plain Dart sets that the package diffs onto the native map on every
  rebuild, and the controller is an interface you can mock in unit tests.
- **Apple's names.** Types are named after their MapKit counterparts
  (`MKMapCamera`, `MKPolyline`, `CLLocationCoordinate2D`), so Apple's
  documentation applies as-is, and they don't clash with `google_maps_flutter`,
  `mapbox_maps_flutter` or `flutter_map` types in a cross-platform app.
- **Mistakes fail loudly.** Invalid values, and iOS-only settings used on macOS
  ([differences](#ios-and-macos-differences)), throw in every build mode instead
  of being silently ignored.

MapKit doesn't exist on Android: building `MKMapView` there throws a
`MapKitUnsupportedPlatformException`. For a cross-platform app, pair this
package with `google_maps_flutter` behind a platform check.

## Quick start

```bash
flutter pub add mapkit_flutter
```

Your app must target at least **iOS 17** and **macOS 14**, higher than Flutter's
defaults ([Setup](#setup) shows where). Then put a map on screen:

```dart
import 'package:flutter/material.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

void main() {
  runApp(
    MaterialApp(
      home: MKMapView(
        initialCamera: MKMapCamera(
          centerCoordinate: CLLocationCoordinate2D(
            latitude: 37.334922,
            longitude: -122.009033,
          ),
          distance: 1500, // meters from the camera to the center
        ),
      ),
    ),
  );
}
```

## Setup

### Requirements

| | Minimum |
| --- | --- |
| iOS | 17.0 |
| macOS | 14.0 |
| Xcode | 16 (the native code is Swift 6 language mode — data-race safety is compiler-enforced) |

Raise the app's deployment targets to the plugin's floor:

- **iOS 17.0** — `IPHONEOS_DEPLOYMENT_TARGET` on the Runner target (or Podfile
  `platform :ios, '17.0'`).
- **macOS 14.0** — `MACOSX_DEPLOYMENT_TARGET` on the Runner target (or Podfile
  `platform :osx, '14.0'`).

A Swift Package Manager app left on Flutter's default macOS 12.0 fails to build
with "requires minimum platform version 14.0".

### Showing the user's location

If you set `showsUserLocation: true`, add this to `ios/Runner/Info.plist` (on
macOS, to `macos/Runner/Info.plist`, plus the Location sandbox entitlement):

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Used to show your current location on the map.</string>
```

Like `MKMapView`, the map never asks for location permission itself: request
when-in-use authorization in your app (e.g. with `permission_handler` or a
`CLLocationManager` channel) at the moment that makes sense for your UI. Without
it, `onDidFailToLocateUser` reports the failure.

## A page with a pin

A real page usually keeps the controller that `onMapCreated` hands over, for
imperative calls such as moving the camera:

```dart
import 'package:flutter/material.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

class const MapPage({super.key}) extends StatefulWidget {
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static final _applePark = CLLocationCoordinate2D(
    latitude: 37.334922,
    longitude: -122.009033,
  );

  MKMapViewController? _controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apple Park')),
      body: MKMapView(
        initialCamera: MKMapCamera(
          centerCoordinate: _applePark,
          distance: 1500, // MKMapCamera.centerCoordinateDistance, meters
        ),
        annotations: {
          MKPointAnnotation(
            id: const MKAnnotationId('apple-park'),
            coordinate: _applePark,
            title: 'Apple Park',
            subtitle: 'One Apple Park Way',
          ),
        },
        onMapCreated: (controller) => _controller = controller,
        // Recenter on the tapped point.
        onTap: (coordinate) => _controller?.setCenter(coordinate),
      ),
    );
  }
}
```

## Values, ids and updates

Value types validate in every build mode and throw an `ArgumentError` for input
MapKit can't represent — a latitude outside `[-90, 90]` (swapped arguments), a
non-finite number, a negative `lineWidth`, `alpha` outside `[0, 1]`, a camera
`pitch` outside `[0, 90)`, a zoom range whose minimum exceeds its maximum. That
is why those types have no `const` constructor; ids, marker icons, regions, map
configurations and snapshot options do. Polylines, polygons and
point-of-interest filters keep their own unmodifiable copy of the lists you
pass, so changing a list later never changes the value. Longitude wraps into
`[-180, 180)` like MapKit. `Coordinate` is an exported alias for
`CLLocationCoordinate2D`; if another package also exports a `Coordinate`, `hide`
it on import.

Content is declarative: on every rebuild, `MKMapView` diffs each set by id. A
new id is added, a changed object with the same id is updated, and an id that
left the set is removed from the map. The diff runs against what the map last
accepted, so you can build a new set on every rebuild or change one in place and
call `setState`. A batch MapKit rejects, say for an undecodable icon, fails as a
whole; once you change the set, everything it held goes out again. Ids must be
unique per kind; two annotations (or two polylines…) sharing an id throw when
`MKMapView` builds.

Models override `==`, so they can't be used in `const {…}` set literals — build
the set without `const`. `copyWith` clears a nullable field when you pass `null`
explicitly:

```dart
MKPointAnnotation untitled(MKPointAnnotation annotation) =>
    annotation.copyWith(title: null);
```

## Map style and controls

The widget mirrors `MKMapView`. The base style is a sealed
`preferredConfiguration` (exactly `MKMapView.preferredConfiguration`);
view-level switches are direct parameters with their `MKMapView` property names.
Here the function's parameters stand in for your app's state:

```dart
MKMapView campusMap({
  required MKMapCamera camera,
  required MKCoordinateRegion campus,
  required MKUserTrackingMode trackingMode,
  required ValueChanged<MKUserTrackingMode> onTrackingModeChanged,
}) {
  return MKMapView(
    initialCamera: camera,
    preferredConfiguration: MKStandardMapConfiguration(
      elevationStyle: MKMapElevationStyle.realistic,
      // `standard` is Apple's `.default`, a reserved word in Dart.
      emphasisStyle: MKMapEmphasisStyle.muted,
      pointOfInterestFilter: MKPointOfInterestFilter.including(const [
        MKPointOfInterestCategory.cafe,
        MKPointOfInterestCategory.park,
      ]),
      showsTraffic: true,
    ),
    // MKHybridMapConfiguration() / MKImageryMapConfiguration() likewise.
    isRotateEnabled: false,
    isPitchEnabled: false,
    showsCompass: false,
    showsScale: true,
    showsUserLocation: true,
    showsUserTrackingButton: true,
    // Applied when it changes. MapKit drops back to `none` when the user
    // pans: store the reported mode so the next rebuild matches.
    userTrackingMode: trackingMode,
    onUserTrackingModeChanged: onTrackingModeChanged,
    cameraZoomRange: MKCameraZoomRange(
      minCenterCoordinateDistance: 500, // meters
      maxCenterCoordinateDistance: 100000,
    ),
    cameraBoundary: campus, // keeps the camera center inside
    // iOS only: both throw on macOS.
    selectableMapFeatures: const {MKMapFeatureOptions.pointsOfInterest},
    onMapFeatureSelected: (feature) => debugPrint('Selected ${feature.title}'),
  );
}
```

By default all four gestures (zoom, scroll, rotate, pitch) are enabled and the
compass is shown; the scale, the user's location and the tracking button are
hidden.

## Annotations

`MKPointAnnotation` merges the annotation (`coordinate`, `title`, `subtitle`)
with its `MKAnnotationView` presentation (`alpha`, `isDraggable`, `zPriority`,
`clusteringIdentifier`…) — Flutter is declarative, so there is no separate view
object.

```dart
Future<Set<MKPointAnnotation>> places({
  required BuildContext context,
  required Coordinate home,
  required Coordinate cafe,
  required Coordinate shop,
  required Coordinate friend,
  required Coordinate applePark,
  required Uint8List avatarPng,
}) async {
  final pin = await MKAnnotationIcon.asset('assets/pin.png');
  return {
    // System balloon marker (MKMarkerAnnotationView).
    MKPointAnnotation(id: const MKAnnotationId('home'), coordinate: home),

    // Tinted marker with an SF Symbol glyph.
    MKPointAnnotation(
      id: const MKAnnotationId('cafe'),
      coordinate: cafe,
      icon: const MKAnnotationIcon.marker(
        markerTintColor: Colors.brown,
        systemImage: 'cup.and.saucer.fill',
        glyphTintColor: Colors.white,
      ),
    ),

    // Custom image from an asset, loaded above.
    MKPointAnnotation(
      id: const MKAnnotationId('shop'),
      coordinate: shop,
      icon: pin,
    ),

    // Fully custom marker: the PNG bytes of a rendered Flutter widget
    // (e.g. captured with RenderRepaintBoundary.toImage).
    MKPointAnnotation(
      id: const MKAnnotationId('friend'),
      coordinate: friend,
      icon: MKAnnotationIcon.image(avatarPng),
    ),

    // Callout, selection and drag.
    MKPointAnnotation(
      id: const MKAnnotationId('apple-park'),
      coordinate: applePark,
      title: 'Apple Park',
      subtitle: 'One Apple Park Way',
      calloutConsumesTapEvents: true, // iOS only; onCalloutTap needs it
      onCalloutTap: () => Navigator.pushNamed(context, '/details'),
      onSelect: () => debugPrint('selected'), // tap or selectAnnotation
      onDeselect: () => debugPrint('deselected'),
      isDraggable: true,
      onDragEnd: (coordinate) => debugPrint('dropped at $coordinate'),
    ),
  };
}
```

Annotations sharing a `clusteringIdentifier` cluster natively when they crowd.
Image bytes the platform can't decode, or an SF Symbol name it doesn't know,
fail the map update with a `MapKitPlatformException` (`invalid-icon`) instead of
rendering an invisible or plain pin.

## Overlays

`MKPolyline`, `MKPolygon` and `MKCircle` each merge in their renderer's
properties: `strokeColor` and `lineWidth` on all three, `fillColor` on polygons
and circles, `lineCap`, `lineJoin`, `lineDashPattern` and `gradientColors` on
polylines. Caps and joins (`CGLineCap`, `CGLineJoin`) default to round, as in
MapKit's path renderers.

```dart
MKMapView overlays({
  required MKMapCamera camera,
  required List<Coordinate> route,
  required Coordinate sfo,
  required Coordinate nrt,
  required List<Coordinate> zone,
  required List<Coordinate> courtyard,
  required Coordinate store,
}) {
  return MKMapView(
    initialCamera: camera,
    polylines: {
      MKPolyline(
        id: const MKPolylineId('route'),
        coordinates: route,
        strokeColor: Colors.blue,
        lineWidth: 6,
        lineDashPattern: const [6, 3], // dash and gap lengths in points
        lineCap: CGLineCap.butt, // flat dash ends
        level: MKOverlayLevel.aboveLabels,
        consumeTapEvents: true, // capture taps…
        onTap: () => debugPrint('route'), // …to receive them
      ),
      // Great-circle path, densified natively by MKGeodesicPolyline.
      MKPolyline.geodesic(
        id: const MKPolylineId('sfo-nrt'),
        coordinates: [sfo, nrt],
        lineWidth: 4,
        // Two or more colors; replaces strokeColor.
        gradientColors: const [Colors.green, Colors.red],
      ),
    },
    polygons: {
      MKPolygon(
        id: const MKPolygonId('zone'),
        coordinates: zone,
        interiorPolygons: [courtyard], // holes, as in MKPolygon
        fillColor: Colors.red.withValues(alpha: 0.3),
        strokeColor: Colors.red,
        lineWidth: 2,
      ),
    },
    circles: {
      MKCircle(
        id: const MKCircleId('radius'),
        center: store,
        radius: 500, // meters
      ),
    },
  );
}
```

Only overlays with `consumeTapEvents: true` capture taps; the top-most capturing
overlay under a tap fires its `onTap`, and the tap doesn't reach the map's
`onTap`. Setting `onTap` without `consumeTapEvents` throws an `ArgumentError` —
it could never fire. Polyline hit-testing covers the visible stroke (half the
`lineWidth`, at least 8 points).

### Tile overlays

Tile overlays go through the controller (`MKTileOverlay(urlTemplate:)`
semantics, with the renderer's `alpha` merged in):

```dart
Future<void> addOsm(MKMapViewController controller) async {
  await controller.addTileOverlay(
    MKTileOverlay(
      id: const MKTileOverlayId('osm'),
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    ),
  );
  final removed = await controller.removeTileOverlay(
    const MKTileOverlayId('osm'),
  );
}
```

Adding an id that is already on the map throws (`duplicate-id`); remove it first
to replace it. `removeTileOverlay` returns `false` when the id isn't on the map.

Snapshots include tile overlays. `takeSnapshot` fetches the visible tiles with
the overlay's own `MKTileOverlay.loadTile`, each at the zoom its on-screen size
calls for, then draws them in the map's overlay order with their `alpha`. A
snapshot fails with `snapshot-failed` when a tile can't be fetched or isn't an
image, and that includes a server's 404 page, so give sparse sources a blank
tile instead. It also fails when tiles don't arrive within 60 seconds, and when
a view needs more than 1024 tiles across its overlays. At the default `tileSize`
of 256, MapKit's steepest camera takes about 50 tiles on a phone and 300 on a
2560-point window, so that takes a very small `tileSize` or several overlays on
a large window.

What a snapshot can't match on the live map:

- `MKMapSnapshotter` bakes Apple's labels and 3D buildings into its base map, so
  even an `aboveRoads` overlay lies flat on top of them.
- With `canReplaceMapContent`, the snapshot leaves out the base map and is
  transparent where no opaque tile covers it.
- A steep camera asks your source for low zooms toward the horizon, down to zoom
  0, and distant tiles look softer than near ones. MapKit's pitch cap puts the
  ground's horizon at the top of the view, so tiles reach it, covering the band
  where Apple's own base map has already faded into sky.
- Tile grids end at the Mercator world's edge, about 85.05° north and south.
  Past that the base map shows through, which a steep camera at high latitudes
  can bring into view.
- Past `maximumZ` the highest tiles are upscaled, however close the camera
  comes. Where a tile would fall below `minimumZ` the overlay has nothing to
  draw and the base map shows through, which under a steep camera means the far
  part of the view.

## Controller

`MKMapViewController` is `MKMapView`'s imperative surface. You get it from
`onMapCreated`, and every member returns a `Future`:

```dart
Future<void> tour(
  MKMapViewController controller,
  Coordinate coordinate,
  Offset offset,
) async {
  if (await controller.camera case final camera?) {
    await controller.setCamera(camera.copyWith(distance: camera.distance / 2));
  }
  if (await controller.region case final region?) {
    await controller.setRegion(region, animated: false);
  }
  await controller.setCenter(coordinate);
  final point = await controller.convertToPoint(coordinate);
  final tapped = await controller.convertToCoordinate(offset);
  const id = MKAnnotationId('apple-park');
  final selected = await controller.selectAnnotation(id);
  await controller.deselectAnnotation(id);
  final isSelected = await controller.isAnnotationSelected(id);
  final opened = await controller.openLookAround(coordinate);
  final png = await controller.takeSnapshot(
    const MKMapSnapshotOptions(showsPointsOfInterest: false),
  );
}
```

| Member | MapKit |
| --- | --- |
| `camera` | `MKMapView.camera` |
| `region` | `MKMapView.region` |
| `setCamera(camera, animated:)` | `setCamera(_:animated:)` |
| `setRegion(region, animated:)` | `setRegion(_:animated:)` |
| `setCenter(coordinate, animated:)` | `setCenter(_:animated:)` |
| `convertToPoint(coordinate)` | `convert(_:toPointTo:)` |
| `convertToCoordinate(offset)` | `convert(_:toCoordinateFrom:)` |
| `selectAnnotation(id)` | `selectAnnotation(_:animated:)` |
| `deselectAnnotation(id)` | `deselectAnnotation(_:animated:)` |
| `isAnnotationSelected(id)` | `selectedAnnotations` |
| `openLookAround(coordinate)` | `MKLookAroundViewController` |
| `takeSnapshot([options])` | `MKMapSnapshotter` |
| `addTileOverlay(overlay)` | `addOverlay(_:level:)` |
| `removeTileOverlay(id)` | `removeOverlay(_:)` |
| `dispose()` | — |

`animated` defaults to `true`. `camera`, `region` and the conversions return
`null` before the view's first layout — there is no meaningful camera for a
zero-sized view yet. `selectAnnotation` / `deselectAnnotation` return `false`
when the id isn't on the map (e.g. racing a rebuild that removed it) and
`selectAnnotation` also for a hidden annotation, so you can tell whether
anything happened. `openLookAround` returns `false` when no Look Around scene
exists for the coordinate, and `removeTileOverlay` when the id isn't on the map.
`takeSnapshot` returns PNG bytes; its `options` mirror
`MKMapSnapshotter.Options`.

Calls run on an internal serial queue — concurrent calls execute in source
order. `controller.dispose()` runs automatically when the owning `MKMapView`
widget unmounts.

### Testing code that uses the controller

`MKMapViewController` is an interface, so the code you write against it is
unit-testable without a platform view. With mockito, where `MapPresenter` stands
for your own code and `dart run build_runner build` generates the mock:

<!-- no-compile -->

```dart
@GenerateNiceMocks([MockSpec<MKMapViewController>()])
void main() {
  test('recenters on the selected stop', () async {
    final controller = MockMKMapViewController();
    when(controller.camera).thenAnswer((_) async => someCamera);

    await MapPresenter(controller).select(stop);

    verify(controller.setCenter(stop.coordinate)).called(1);
  });
}
```

## google_maps_flutter-style helpers

The canonical API is the MapKit mirror above. If you think in
google_maps_flutter terms, the exported `CameraConveniences` extension layers
that dialect on top — implemented purely over the canonical calls, no extra
platform surface:

```dart
Future<void> frame(
  MKMapViewController controller,
  Set<MKPointAnnotation> annotations,
) async {
  await controller.zoomTo(14);
  await controller.zoomBy(2);
  await controller.zoomIn();
  await controller.scrollBy(80, -40);
  await controller.fitCoordinates(
    annotations.map((a) => a.coordinate),
    padding: 0.1, // 10% of the span on each side
  );
  final zoom = await controller.getZoomLevel();
}
```

Zoom levels are a Web-Mercator convenience (`MKMapCamera.withZoomLevel` /
`camera.zoomLevel`); MapKit's native unit is `distance` in meters. The
camera-relative helpers throw a `StateError` before the view's first layout, and
`fitCoordinates` throws an `ArgumentError` for an empty list, a negative
`padding` / `minimumSpan`, or a span they widen past what `MKCoordinateSpan`
allows (180° latitude, 360° longitude).

## iOS and macOS differences

| | iOS | macOS |
| --- | --- | --- |
| `calloutConsumesTapEvents` / `onCalloutTap` | ✓ | throws (default callout) |
| Image-icon `anchorPoint` | ✓ | ✓ |
| `userTrackingMode: followWithHeading` | ✓ | throws |
| Snapshot annotation/overlay compositing | ✓ | ✓ |
| `selectableMapFeatures` + `onMapFeatureSelected` | ✓ | throws |
| `insetsLayoutMarginsFromSafeArea: false` | ✓ | throws |
| `openLookAround` | ✓ | throws `unsupported-platform` |
| `showsUserTrackingButton` | ✓ | ✓ |
| `onCameraMove` | continuous | continuous |

"Throws" means building `MKMapView` with that setting on macOS throws a
`MapKitUnsupportedPlatformException` naming it. `openLookAround` is a controller
call instead: on macOS it fails with a `MapKitPlatformException` whose code is
`unsupported-platform`.

## Errors

Misuse fails loudly, in debug and release alike, close to its cause:

- **Invalid values** throw an `ArgumentError` from the constructor (see
  [Values, ids and updates](#values-ids-and-updates)).
- **Callbacks that could never fire** throw an `ArgumentError`: `onTap` without
  `consumeTapEvents`; `onDragStart` / `onDragEnd` without `isDraggable`;
  `onCalloutTap` without `calloutConsumesTapEvents` or without a `title` or
  `subtitle`; `onMapFeatureSelected` without `selectableMapFeatures`.
- **Duplicate ids** in one of `MKMapView`'s sets throw an `ArgumentError` when
  the widget builds or updates.
- **iOS-only settings on macOS** throw a `MapKitUnsupportedPlatformException`
  whose `feature` names the setting.
- **Use after dispose** throws a `MapKitDisposedException` from the controller
  methods you call. Updates `MKMapView` itself had queued are simply dropped.
- **Building on the web**, Safari on an iPhone included, throws a
  `MapKitUnsupportedPlatformException`.

Native failures surface as a `MapKitPlatformException` with a stable `code` plus
the native `message` / `details`:

| Code | When |
| --- | --- |
| `snapshot-failed` | `takeSnapshot` produced no image: a tile overlay's tile failed to load, isn't an image or missed the 60-second deadline, the view needs more than 1024 tiles, a tile can't be projected onto the view, base map loading failed, the view has zero size, or the map was disposed during the snapshot |
| `look-around-failed` | the Look Around scene request failed (e.g. offline) or there is no view controller to present from |
| `unsupported-platform` | `openLookAround` on macOS |
| `duplicate-id` | `addTileOverlay` with an id already on the map |
| `invalid-icon` | annotation image bytes that don't decode, or an unknown SF Symbol |
| `unavailable-poi-category` | a `MKPointOfInterestFilter` naming a category newer than the running OS (iOS 18 / macOS 15 values) |
| `invalid-argument` | a zoom range or camera boundary MapKit rejects |

```dart
Future<void> snapshot(MKMapViewController controller) async {
  try {
    final png = await controller.takeSnapshot();
  } on MapKitPlatformException catch (e) {
    debugPrint('${e.code}: ${e.message}');
  }
}
```

Errors from declarative content (annotations, overlays, configuration) happen
while `MKMapView` pushes an update, outside any call you await, so they surface
as uncaught errors in the zone — they don't vanish. An exception thrown
synchronously by a callback for a map event (`onTap`, `onSelect`,
`onCameraMove`…) goes to `FlutterError.onError`, in every build mode; an `async`
callback's error goes to the zone like any other unawaited future.

What isn't an error is reported as a value: `openLookAround` returns `false`
when no Look Around scene exists for the coordinate, `selectAnnotation` /
`deselectAnnotation` / `removeTileOverlay` return `false` when the id isn't on
the map, and `camera` / `region` / conversions return `null` before the first
layout. Failures MKMapView reports through its delegate surface as widget
callbacks: `onDidFailToLocateUser` (most commonly missing location permission)
and `onDidFailLoadingMap` (map content failed to load, e.g. offline).

## Under the hood

The Dart↔Swift boundary is generated by
[Pigeon](https://pub.dev/packages/pigeon) from
[`pigeons/messages.dart`](pigeons/messages.dart), so every message is
type-checked on both sides. Wire types keep a `Platform` prefix so the generated
Swift never shadows real MapKit symbols; public Dart names are restored via
`typedef` (e.g. `MKUserTrackingMode`). Regenerating the channel is covered in
[CONTRIBUTING.md](CONTRIBUTING.md).

## Agent skill

This package ships an agent skill in `skills/mapkit-flutter-scaffold/`. Install
it into your project's agent config with:

```sh
dart run skills@ get --package mapkit_flutter --all
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [`LICENSE`](LICENSE).
