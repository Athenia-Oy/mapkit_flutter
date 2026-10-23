# Changelog

## Unreleased

### Breaking

- **Polylines, polygons and point-of-interest filters keep unmodifiable copies
  of the lists you pass.** Mutating a list after handing it over could hide the
  change from the map diff and slip past validation. `MKPolyline`
  (`coordinates`, `lineDashPattern`, `gradientColors`), `MKPolygon`
  (`coordinates`, `interiorPolygons` and each ring) and
  `MKPointOfInterestFilter.including` / `.excluding` (`categories`) now copy
  them, and their getters return unmodifiable lists. The two filter constructors
  lost `const`. Migration: drop `const` before
  `MKPointOfInterestFilter.including(...)` / `.excluding(...)` and any map
  configuration that holds one (`.including(const [...])` still works), and
  build a new list instead of mutating one read from a value.

### Fixed

- `MKMapView` diffs annotations, overlays and `selectableMapFeatures` against
  what it last sent to MapKit instead of the previous widget. Changing a `Set`
  in place and calling `setState` used to update nothing; it now updates the
  map.
- `MKAnnotationIcon.image` throws an `ArgumentError` for an `imagePixelRatio`
  that is not finite and `> 0`, and `MKPointAnnotation` throws one for a
  non-finite `zPriority` or `anchorPoint`. These used to reach MapKit as NaN or
  infinite sizes and offsets.

## 0.5.1 - 2026-10-16

### Fixed

- README: tile overlays take only `alpha`, not stroke or fill styling;
  `openLookAround` returns a `bool`; on macOS it throws a
  `MapKitPlatformException` with code `unsupported-platform`, not a
  `MapKitUnsupportedPlatformException`.

### Changed

- The README opens with what the package does, why to use it and a short
  example. Every Dart sample in the README and the agent skill is analyzed with
  the package's lints and fits pub.dev without scrolling sideways.
- Regenerated the platform channel code with Pigeon 29.0.10 (header only).

## 0.5.0 - 2026-10-15

Misuse now fails loudly in every build mode instead of being clamped, ignored or
degraded, and the controller reports outcomes instead of swallowing them.

### Breaking

- **Value types validate in all build modes and lost their `const`
  constructors.** `CLLocationCoordinate2D`, `MKCoordinateSpan`,
  `MKCameraZoomRange`, `MKMapCamera`, `MKPointAnnotation`, `MKPolyline`,
  `MKPolygon`, `MKCircle` and `MKTileOverlay` throw an `ArgumentError` for
  non-finite numbers, out-of-range spans/alpha/zoom levels, negative widths or
  radii, and a zoom range whose minimum exceeds its maximum — release builds no
  longer pass them through to MapKit. Migration: drop `const` from these
  constructor calls; `MKMapView(cameraZoomRange:)` defaults to the new
  `MKCameraZoomRange.unbounded` constant.
- `CLLocationCoordinate2D` rejects a latitude outside `[-90, 90]` instead of
  clamping it (swapped arguments used to land on a pole). Longitude still wraps
  into `[-180, 180)`.
- `MKPolyline` rejects a single `gradientColors` entry (it used to draw
  `strokeColor` silently); pass none or at least two.
- `MKPolyline` rejects a `lineDashPattern` with a negative or non-finite length,
  or with only zeros (CoreGraphics drew such a line as nothing). Dotted patterns
  like `[0, 15]` stay valid.
- Duplicate ids within one of `MKMapView`'s sets throw an `ArgumentError` in all
  build modes (release builds used to keep only the last object).
- Tap capture is explicit: overlays send `consumeTapEvents` as given (`onTap` no
  longer implies it) and `onTap` without `consumeTapEvents: true` throws.
  `MKPointAnnotation` gains `calloutConsumesTapEvents` (default `false`), and
  `onCalloutTap` requires it. Equality no longer tracks callback presence.
  Migration: add `consumeTapEvents: true` next to an overlay's `onTap`, and
  `calloutConsumesTapEvents: true` next to `onCalloutTap`.
- `MKPointAnnotation.onTap` is removed — it was `mapView(_:didSelect:)` minus
  programmatic selections. Use `onSelect`, which fires for a user tap and for
  `selectAnnotation`.
- `MKPointAnnotation.onDrag` is removed — MapKit reports drag-state changes, not
  movement, so it fired once per drag with the coordinate where the drag began,
  never while the pin moved. Use `onDragStart` for the start and `onDragEnd` for
  the dropped coordinate.
- `MKMapViewController.showCallout` / `hideCallout` / `isCalloutShown` are
  renamed to MapKit's `selectAnnotation` / `deselectAnnotation` /
  `isAnnotationSelected`. `selectAnnotation` and `deselectAnnotation` return
  `Future<bool>`: `false` when the id isn't on the map (and, for
  `selectAnnotation`, when the annotation is hidden) instead of silently doing
  nothing.
- `MKMapViewController.camera` and `region` return `null` before the view's
  first layout (they returned a zero region and a camera with distance 0).
  `CameraConveniences` helpers throw a `StateError` then, `scrollBy` included
  (it was a silent no-op), and `fitCoordinates([])` throws an `ArgumentError`
  (it was a no-op), as do a negative `padding` / `minimumSpan`.
- `openLookAround` returns `false` only when no scene exists. A failed scene
  request or a missing presenter throws `MapKitPlatformException`
  (`look-around-failed`), and macOS throws `unsupported-platform` (it returned
  `false` for all of these).
- `addTileOverlay` with an id already on the map throws
  `MapKitPlatformException` (`duplicate-id`) instead of replacing it;
  `removeTileOverlay` returns `Future<bool>` (`false` for an id that isn't on
  the map).
- iOS-only settings on macOS throw a `MapKitUnsupportedPlatformException` naming
  the setting (new `feature` field): `userTrackingMode: followWithHeading` (it
  fell back to `follow`), `selectableMapFeatures`, `onMapFeatureSelected`,
  `insetsLayoutMarginsFromSafeArea: false` and an annotation's
  `calloutConsumesTapEvents` (all silently ignored).
- `showsUserLocation: true` no longer prompts for location permission (neither
  `MKMapView` nor google_maps_flutter does). Request when-in-use authorization
  in your app; without it `onDidFailToLocateUser` reports the failure.
- Annotation image bytes that don't decode and unknown SF Symbol names fail the
  update with `MapKitPlatformException` (`invalid-icon`) instead of an invisible
  annotation or a plain marker. An invalid icon fails the whole update; nothing
  is half-applied.
- A point-of-interest filter naming a category newer than the running OS (the
  iOS 18 / macOS 15 values) fails with `MapKitPlatformException`
  (`unavailable-poi-category`) instead of being dropped — `including([.castle])`
  on iOS 17 used to hide every POI.
- MapKit rejecting a zoom range or camera boundary throws
  `MapKitPlatformException` (`invalid-argument`) instead of silently leaving the
  map unbounded.
- `MKMapSnapshotOptions.showsBuildings` is removed; it had no effect.

### Added

- `MKMapView.onUserTrackingModeChanged` reports MapKit's own tracking-mode
  changes (`mapView(_:didChange:animated:)`, e.g. dropping to `none` when the
  user pans), so the declared `userTrackingMode` can stay in sync.
- Image-icon `anchorPoint` works on macOS (via `centerOffset`); it used to be
  ignored there.
- macOS snapshots draw annotations and overlays when `showsAnnotations` /
  `showsOverlays` are on, as iOS does; they used to contain only the base map
  although both options default to `true`.
- Snapshots draw annotations above overlays, matching the live map (overlays
  used to cover annotations on both platforms).

### Changed

- `MKMapView` imports `package:flutter/widgets.dart` instead of
  `package:flutter/material.dart`.
- `MKStandardMapConfiguration.toString()` and
  `MKHybridMapConfiguration.toString()` include `pointOfInterestFilter`;
  `MKPointOfInterestFilter` subclasses override `toString()`.
- Polyline tap targets cover the visible stroke: half the `lineWidth`, at least
  8 points (it was a fixed 8 points).
- A tap or click on an annotation view selects the annotation without also
  firing the map's `onTap`.
- macOS: a click fires `onTap` once the double-click interval passes, and a
  double-click (which zooms) fires none, matching iOS taps (every click of a
  double-click used to fire `onTap`).

### Fixed

- Cross-type overlay ID collisions in `MapKitViewHost` so polylines, polygons,
  and circles have independent ID namespaces.
- `MKAnnotationIcon.asset` slices `ByteData` views via `Uint8List.sublistView`
  and loads from the resolved `AssetBundleKey.bundle`.
- `CLLocationCoordinate2D` wraps `-180.00000000000003` to `-180.0` instead of
  `180.0`.
- Native `AnnotationController`: gate `onCalloutTapped` on
  `calloutConsumesTapEvents`, suppress spurious selection callbacks during
  icon-type swap of a selected annotation, update `MKMarkerAnnotationView`
  callouts in place, and register cluster reuse identifier once on
  `FlutterMapView` init.
- Native `takeSnapshot`: guard against zero-size map view, project using the
  snapshot's camera/region options, honor custom annotation image `alpha` on
  iOS, and render interior polygon holes with `evenOdd` fill rule.
- `openLookAround` walks the full `presentedViewController` chain before
  presenting, waits out a running transition (UIKit postponed the presentation,
  so the future failed and Look Around appeared anyway), and throws
  `MapKitPlatformException` (`look-around-failed`) when UIKit rejects the
  presentation; its future used to never complete.
- A camera move made before the first layout (`setCamera` / `setRegion` /
  `setCenter`, e.g. from `onMapCreated`) is no longer overridden by
  `initialCamera` when the view gets its size, including a move that lands
  between the resize and the layout pass.
- Snapshots draw a polyline's `gradientColors` along its length, including the
  tips of sharp miter joins; they used to draw the plain `strokeColor`.

## 0.4.0 - 2026-10-04

### Breaking

- MKPointOfInterestCategory gained 33 values — exhaustive switches over it must
  handle them.
- `copyWith(x: null)` now clears a nullable field instead of keeping it, so code
  that passes a possibly-null variable changes behaviour. Parameter types are
  unchanged from 0.3.7; omitting the argument still keeps the field.
- The agent skill moved to skills/mapkit-flutter-scaffold/ (dart run skills@ get
  requires the package-name prefix).

### Added

- MKPointAnnotation.onSelect / onDeselect.
- MKMapView.onMapFeatureSelected (iOS) with MKMapFeature / MKMapFeatureType.
- 33 iOS 18 / macOS 15 MKPointOfInterestCategory values (ignored by filters on
  older OS versions).
- Apple privacy manifest (PrivacyInfo.xcprivacy) for SPM and CocoaPods.

### Changed

- Requires Dart 3.13 / Flutter 3.47 (was Dart 3.10 / Flutter 3.41).
- Platform channel regenerated with Pigeon 29; host→Dart events use its async
  Swift API.
- An overlay with onTap now consumes taps (onTap implies consumeTapEvents).
- fitCoordinates gains padding and minimumSpan; a single coordinate now frames
  0.005° instead of zooming fully in.
- Only the top-most visible consuming overlay receives a tap (was every overlay
  under the point).
- `userTrackingMode` is re-applied only when it changes, so unrelated rebuilds
  no longer snap a panned map back to tracking.
- `showsUserTrackingButton` works on macOS.
- MKMapSnapshotOptions.showsBuildings has no effect (MapKit dropped it).
- onCameraMove fires continuously (gestures, momentum, animations) on iOS and
  macOS via mapViewDidChangeVisibleRegion.
- Docs: Look Around and showsUserTrackingButton platform notes corrected;
  per-platform differences table; deployment-target setup.

### Fixed

- Package.swift declares the FlutterFramework dependency (silences the Flutter
  3.47 build warning).
- Unmounting a map now releases its native MKMapView, host and location manager
  (channel handlers were never removed).
- Geodesic polylines no longer corrupt memory on iOS/macOS 27
  (MKGeodesicPolyline is no longer subclassed).
- A rebuild that lands before the platform view finishes creating no longer
  leaves taps on stale callbacks.
- In-range longitudes are stored verbatim (normalisation used to perturb them,
  e.g. 10.1 → 10.099999999999994).
- `initialize` sends one object per id, last wins, like the rebuild diff;
  duplicate ids now assert in debug.
- Toggling `onCalloutTap` on an existing annotation now reaches native.
- The first annotation update after a drag is no longer dropped (Dart stays the
  source of truth: a drag the app ignores snaps back on the next changed
  rebuild).
- `MKPointOfInterestCategory.evCharger` works on iOS 17 (an `including` filter
  with it no longer hides every POI).
- Custom-image annotation callouts are no longer offset sideways.
- `onCalloutTap` fires once per tap after reselecting an annotation (iOS).
- Hidden overlays never take taps.
- Re-adding a tile overlay with the same id (including the empty id) replaces
  it.
- Snapshots now match the on-screen map: style
  (hybrid/imagery/muted/traffic/elevation/POI filter), rotated/pitched camera
  and dark mode.
- Snapshot polygon outlines start without a zero-length edge and draw the
  closing edge once (visible with dash patterns and translucent strokes).
- The podspec no longer forces -warnings-as-errors on CocoaPods consumers.

### Removed

- The hand-patched pigeon deepEquals dictionary branch (dead code — the schema
  has no Map fields) and the unused ios/ copy of the generated Swift file.

## 0.3.7

- Fix: iOS snapshot polylines now stroke as a single subpath, so `lineJoin`
  applies and dash patterns run continuously across vertices. A
  single-coordinate polyline now draws nothing instead of a round-cap dot,
  matching the live renderer.
- Performance: iOS snapshots skip annotations whose drawn frame lies entirely
  outside the image; partially visible edge annotations still draw.
- Fix: podspec version now tracks pubspec — CocoaPods had advertised 0.3.0 since
  v0.3.1. CI guards against drift (and fails closed if no podspec matches).
- CI: macOS example build job added alongside iOS; integration workflow bounds
  every `flutter test` invocation and recycles a wedged simulator between
  retries.

## 0.3.6

- Testing: `MKMapViewController` is now an interface
  (`abstract interface class`) instead of a `final class`, so code that drives a
  map can be mocked or faked in unit tests. The widget-only mutations
  (`initialize`, `update*`) moved to the internal `MKMapViewControllerImpl`,
  keeping the mockable surface to the public API.

## 0.3.5

- Fix: Marker annotation views dequeue with a safe cast and fallback instead of
  a forced downcast, hardening against a potential native crash.
- Performance: Hoisted the repeated `points()` accessor out of the polyline
  hit-testing loop.

## 0.3.4

- Performance: Refactored Pigeon deep equality checks for maps to O(N), speeding
  up Flutter configuration passes.
- Performance: Overhauled overlay updates to use a true O(1) class-level
  tracking dictionary (`overlaysById`), eliminating O(N) localized allocation
  overheads and massively improving performance when animating individual
  overlays in large collections.
- Fix: Addressed a Swift "ghost overlay" logic flaw where overlays being
  simultaneously removed and updated could fall out of sync with the underlying
  `MKMapView`.

## 0.3.3

- Fix: Per-object tap callbacks (annotation/polyline/polygon/circle) refresh on
  callback-only rebuilds.
- Fix: Toggling `onCalloutTap` propagates to the native callout.
- Fix: Guard polyline tap hit-testing against an empty coordinate list.

## 0.3.2

- Docs: Updated scaffolder skill (`skills/mapkit-flutter-scaffold/SKILL.md`) to
  document overlay tap interactions and macOS snapshot limitations.

## 0.3.1

- Performance: Refactored annotation dequeuing to use generic reuse identifiers,
  enabling proper MapKit view recycling.
- Fix: Preserved selection state (callouts) when swapping marker/image types
  in-place.
- Fix: Repaired overlay tap containment tests for circles and polygons which
  were failing on unrendered local paths.
- Build: Added strict compiler flags (`-warnings-as-errors`,
  `-strict-concurrency=complete`) and resolved iOS/macOS platform optionality
  discrepancies.
- Docs: Correct lingering iOS-only references to iOS + macOS; add `macos` topic.

## 0.3.0

- Added macOS support (Look Around stays iOS-only).
- Annotations now restyle correctly on in-place update and view reuse, including
  marker ↔ custom-image swaps.

## 0.2.1

- Silenced iOS build warnings for cleaner integration.

## 0.2.0

- Added Swift Package Manager support.

## 0.1.1

- Corrected supported platforms.

## 0.1.0

Initial release.
