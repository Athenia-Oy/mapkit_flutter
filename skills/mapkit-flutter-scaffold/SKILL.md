---
name: mapkit-flutter-scaffold
description: 'Scaffold or extend an Apple Maps screen in Flutter on iOS and macOS via `package:mapkit_flutter/mapkit_flutter.dart` — MKMapView widget, pins and custom markers, clustering, polylines, polygons, circles, tile overlays, camera and region control, snapshots, Look Around, mocking MKMapViewController. Use for any map in an Apple-only Flutter app or its MapKit code. Skip for Android or web maps (`google_maps_flutter`, `flutter_map`), Mapbox (`mapbox_maps_flutter`).'
license: MIT
---

# mapkit-flutter-scaffold

One import: `package:mapkit_flutter/mapkit_flutter.dart`. **Every public type
uses Apple's exact MapKit symbol name** — `MKMapView`, `MKMapCamera`,
`MKCoordinateRegion(center:span:)`, `MKPointAnnotation`, `MKPolyline` /
`MKPolygon` / `MKCircle` / `MKTileOverlay`, `MKPointOfInterestFilter`,
`MKStandardMapConfiguration`, `CLLocationCoordinate2D(latitude:longitude:)`,
`CGLineCap`… Predict the API from Swift MapKit knowledge; only the divergences
below need stating. iOS 17 / macOS 14 floor; iOS + macOS (throws
`MapKitUnsupportedPlatformException` on non-Apple platforms) — a handful of
settings are iOS-only and throw the same exception (with `feature` naming the
setting) when used on macOS.

## Divergences from raw MapKit

- `MKMapView` is a declarative StatefulWidget: content is
  `Set<MKPointAnnotation>` / `Set<MKPolyline>` / … params, diffed on rebuild
  against what the map last accepted (a new set per build and an in-place
  mutation + `setState` both work). Same id + changed fields → update; removed
  from set → removed from map.
- No view/renderer objects: presentation props are merged onto the models —
  `MKPointAnnotation`'s `icon:`, `alpha:`, `isDraggable:`, `zPriority:`,
  `clusteringIdentifier:`; `MKPolyline`'s `strokeColor:`, `lineWidth:`,
  `lineDashPattern:`.
- Ids are required phantom-typed values: `MKAnnotationId('x')`,
  `MKPolylineId('x')`, … — not interchangeable, and unique per kind (a duplicate
  throws `ArgumentError` when the map builds).
- Value types validate in every build mode and throw `ArgumentError` (latitude
  outside `[-90, 90]` — no clamping, non-finite numbers, negative widths/radii,
  alpha outside `[0, 1]`, camera `pitch` outside `[0, 90)`, zoom range min >
  max, a single gradient color, `imagePixelRatio` ≤ 0), so they have no `const`
  constructors. Longitude wraps into `[-180, 180)`.
  `MKCameraZoomRange.unbounded` is the const default.
  `MKPolyline`/`MKPolygon`/`MKPointOfInterestFilter.including`/`.excluding`
  store unmodifiable copies of their lists, so the filters aren't `const`
  either: `MKPointOfInterestFilter.including(const [...])`.
- The imperative half lives on `MKMapViewController` (from `onMapCreated`;
  non-null only inside/after it): `camera`/`region` getters (`null` before the
  first layout), `setCamera`/`setRegion`/`setCenter(animated:)`,
  `convertToPoint`/`convertToCoordinate` (`null` pre-layout),
  `selectAnnotation`/`deselectAnnotation` (return `false` when the id isn't on
  the map; select also for a hidden annotation), `isAnnotationSelected`,
  `takeSnapshot(MKMapSnapshotOptions(...))` (annotations and overlays are drawn
  on both platforms), `openLookAround(coordinate)` (`false` only when no scene
  exists; throws `look-around-failed`, and `unsupported-platform` on macOS),
  `addTileOverlay` (throws `duplicate-id`) / `removeTileOverlay` (returns
  `false` for an unknown id). Calls run on an internal serial queue — don't
  coordinate; failures throw `MapKitException` subtypes. `dispose()` is
  automatic on unmount. It's an interface → mock it directly
  (`MockSpec<MKMapViewController>`) instead of hiding it behind a wrapper.
- Callbacks: `onSelect`/`onDeselect` per annotation (`onSelect` = user tap or
  `selectAnnotation`; there is no `onTap` on annotations);
  `onMapFeatureSelected` (iOS, needs `selectableMapFeatures`);
  `onDragStart`/`onDragEnd` need `isDraggable: true`; a callback that could
  never fire throws `ArgumentError`. `onCameraMove` is continuous (every
  visible-region change); `onUserTrackingModeChanged` reports MapKit's own mode
  changes (e.g. `none` after a pan) — keep `userTrackingMode` in sync through
  it. A synchronous throw inside a map-event callback reaches
  `FlutterError.onError`; an `async` callback's error goes to the zone.
  `copyWith(x: null)` clears a nullable field.
- Error contract: misuse throws in every build mode — `ArgumentError` for
  invalid values/duplicate ids, `MapKitUnsupportedPlatformException` for
  iOS-only settings on macOS and any build on the web, `MapKitDisposedException`
  from controller calls after dispose. Native failures are
  `MapKitPlatformException` with a stable `code`: `snapshot-failed`,
  `look-around-failed`, `unsupported-platform`, `duplicate-id`, `invalid-icon`
  (undecodable image bytes / unknown SF Symbol), `unavailable-poi-category` (iOS
  18 / macOS 15 category on an older OS), `invalid-argument`. `snapshot-failed`
  includes a tile overlay tile that fails to load or isn't an image (a 404 page
  counts), tiles missing the 60-second deadline, a view needing more than 1024
  tiles, a tile that can't be projected onto the view, and a map disposed during
  the snapshot. Errors from declarative content surface as uncaught zone errors;
  a rejected batch stays unapplied, and the next change to the set resends all
  of it. Delegate failures surface as widget callbacks `onDidFailToLocateUser`
  (e.g. no location permission) / `onDidFailLoadingMap`, payload = error
  description.
- Tap capture is explicit: overlays need `consumeTapEvents: true` for `onTap`
  (setting `onTap` without it throws), annotations need
  `calloutConsumesTapEvents: true` and a `title` or `subtitle` for
  `onCalloutTap` (iOS only; fires on the bubble, not the pin). Only the top-most
  capturing overlay fires; polyline hit area = half the `lineWidth`, at least 8
  points.
- Style config (`preferredConfiguration:`) carries only
  elevation/emphasis/POI/traffic; `MKMapView` properties (`isZoomEnabled`,
  `showsCompass`, `showsUserTrackingButton`, `cameraZoomRange`,
  `cameraBoundary`, `selectableMapFeatures`…) are direct widget params.
  `selectableMapFeatures`, `onMapFeatureSelected`,
  `insetsLayoutMarginsFromSafeArea: false` and
  `userTrackingMode: followWithHeading` are iOS-only (throw on macOS);
  `showsUserTrackingButton` and image `anchorPoint` work on both.
- google_maps_flutter dialect available via the exported `CameraConveniences`
  extension: `zoomTo/zoomBy/zoomIn/zoomOut/scrollBy/fitCoordinates/getZoomLevel`
  — pure Dart over the canonical calls; they throw `StateError` before the first
  layout, and `fitCoordinates([])` or a padded span past 180°/360° throws
  `ArgumentError`.
- `MKMapCamera.distance` is meters (`centerCoordinateDistance`);
  `MKMapCamera.withZoomLevel(...)` / `camera.zoomLevel` convert Web-Mercator
  zoom levels approximately.
- `MKMapEmphasisStyle.standard` ≙ Apple's `.default` (Dart reserved word).
  `isHidden` replaces `visible` everywhere. Geodesics:
  `MKPolyline.geodesic(...)` named constructor (maps to `MKGeodesicPolyline`).
- Custom marker imagery: `MKAnnotationIcon.marker(...)` with `markerTintColor:`
  / `glyphText:` / `systemImage:` / `glyphTintColor:`, `.image(pngBytes)`, or
  `await MKAnnotationIcon.asset('assets/pin.png')`.
- `Coordinate` is a typedef for `CLLocationCoordinate2D`; enum typedefs point at
  generated `Platform*` enums — cosmetic only.
- `showsUserLocation: true` → add `NSLocationWhenInUseUsageDescription` to
  `ios/Runner/Info.plist` (macOS: `macos/Runner/Info.plist`, plus the Location
  sandbox entitlement) and request when-in-use authorization in the app — the
  map never prompts.
