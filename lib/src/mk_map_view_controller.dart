import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mapkit_flutter/src/_internal/map_object_updates.dart';
import 'package:mapkit_flutter/src/cl_location_coordinate_2d.dart';
import 'package:mapkit_flutter/src/exceptions.dart';
import 'package:mapkit_flutter/src/messages.g.dart';
import 'package:mapkit_flutter/src/mk_circle.dart';
import 'package:mapkit_flutter/src/mk_coordinate_region.dart';
import 'package:mapkit_flutter/src/mk_enums.dart';
import 'package:mapkit_flutter/src/mk_map_camera.dart';
import 'package:mapkit_flutter/src/mk_map_feature.dart';
import 'package:mapkit_flutter/src/mk_map_snapshot_options.dart';
import 'package:mapkit_flutter/src/mk_point_annotation.dart';
import 'package:mapkit_flutter/src/mk_polygon.dart';
import 'package:mapkit_flutter/src/mk_polyline.dart';
import 'package:mapkit_flutter/src/mk_tile_overlay.dart';

/// Callbacks the widget hands to the controller for routing platform events
/// back to the widget API.
@internal
abstract interface class MKMapViewEventSink {
  void onCameraMoveStarted();
  void onCameraMove(MKMapCamera camera);
  void onCameraIdle();
  void onUserTrackingModeChanged(MKUserTrackingMode mode);
  void onAnnotationSelect(MKAnnotationId id);
  void onAnnotationDeselect(MKAnnotationId id);
  void onMapFeatureSelected(MKMapFeature feature);
  void onAnnotationDragStart(
    MKAnnotationId id,
    CLLocationCoordinate2D coordinate,
  );
  void onAnnotationDragEnd(
    MKAnnotationId id,
    CLLocationCoordinate2D coordinate,
  );
  void onCalloutTap(MKAnnotationId id);
  void onPolylineTap(MKPolylineId id);
  void onPolygonTap(MKPolygonId id);
  void onCircleTap(MKCircleId id);
  void onMapTap(CLLocationCoordinate2D coordinate);
  void onMapLongPress(CLLocationCoordinate2D coordinate);
  void onDidFailLoadingMap(String error);
  void onDidFailToLocateUser(String error);
}

/// Controller for a single `MKMapView` platform view, mirroring the
/// imperative half of `MKMapView`: [camera] / [region] state plus
/// [setCamera], [setRegion], [setCenter], and coordinate conversion.
///
/// Instances arrive through `MKMapView.onMapCreated`; the concrete
/// implementation is owned by the widget. The type is an interface so code
/// that drives a map can be unit-tested against a mock or fake — every member
/// below is the whole surface a test double has to cover, and none of it
/// touches platform channels.
///
/// ```dart
/// @GenerateNiceMocks([MockSpec<MKMapViewController>()])
/// void main() {
///   // Nice mocks need a dummy for each non-nullable return type.
///   setUpAll(() => provideDummy<MKMapCamera>(someCamera));
///
///   final controller = MockMKMapViewController();
///   when(controller.camera).thenAnswer((_) async => someCamera);
/// }
/// ```
///
/// All platform calls run through a type-safe Pigeon channel and are
/// serialized onto an internal queue, so concurrent calls execute in source
/// order. Failures surface as [MapKitException]s.
abstract interface class MKMapViewController {
  /// The current camera (`MKMapView.camera`), or `null` while the view has no
  /// layout (before the first frame) — MapKit has no meaningful camera for a
  /// zero-sized view.
  Future<MKMapCamera?> get camera;

  /// The currently visible region (`MKMapView.region`), or `null` while the
  /// view has no layout (before the first frame).
  Future<MKCoordinateRegion?> get region;

  /// `MKMapView.setCamera(_:animated:)`.
  Future<void> setCamera(MKMapCamera camera, {bool animated = true});

  /// `MKMapView.setRegion(_:animated:)`.
  Future<void> setRegion(MKCoordinateRegion region, {bool animated = true});

  /// `MKMapView.setCenter(_:animated:)` — pans without changing distance,
  /// heading, or pitch.
  Future<void> setCenter(
    CLLocationCoordinate2D coordinate, {
    bool animated = true,
  });

  /// Screen point for a coordinate (`MKMapView.convert(_:toPointTo:)`).
  /// Returns null while the view has no layout.
  Future<Offset?> convertToPoint(CLLocationCoordinate2D coordinate);

  /// Coordinate under a screen point
  /// (`MKMapView.convert(_:toCoordinateFrom:)`). Returns null while the view
  /// has no layout.
  Future<CLLocationCoordinate2D?> convertToCoordinate(Offset point);

  /// `MKMapView.selectAnnotation(_:animated:)` — selects the annotation,
  /// showing its callout when it has a `title`.
  ///
  /// Returns whether the annotation is now selected: `false` when the id is
  /// not on the map (e.g. a call racing a rebuild that removed it) or the
  /// annotation is hidden. Nothing happens in that case; check the result
  /// instead of assuming the selection took.
  Future<bool> selectAnnotation(MKAnnotationId id);

  /// `MKMapView.deselectAnnotation(_:animated:)`.
  ///
  /// Returns `false` when the id is not on the map (nothing happens);
  /// otherwise the annotation is deselected and the result is `true`.
  Future<bool> deselectAnnotation(MKAnnotationId id);

  /// Whether the annotation is selected (`MKMapView.selectedAnnotations`).
  /// An id that is not on the map is not selected, so the result is `false`.
  Future<bool> isAnnotationSelected(MKAnnotationId id);

  /// Render the current map to a PNG via `MKMapSnapshotter`.
  ///
  /// Throws a [MapKitPlatformException] with code `snapshot-failed` when the
  /// snapshotter fails or produces no image data, when a tile overlay's tile
  /// fails to load or isn't an image, a server's 404 page included, when tiles
  /// take more than 60 seconds, when the view needs more than 1024 tiles or
  /// can't project a tile, or when the map is disposed before the snapshot
  /// finishes. `MKMapSnapshotter`
  /// bakes labels and 3D buildings into its base map, so an overlay at
  /// `aboveRoads` covers them here, unlike on the live map.
  Future<Uint8List> takeSnapshot([MKMapSnapshotOptions options = const .new()]);

  /// Open the Look Around (street-view) experience for a coordinate (iOS).
  ///
  /// Returns `true` once the scene is presented and `false` when no Look
  /// Around scene exists for the coordinate. Throws a
  /// [MapKitPlatformException] with code `look-around-failed` when the scene
  /// request fails (e.g. offline) or there is no view controller to present
  /// from, and code `unsupported-platform` on macOS.
  Future<bool> openLookAround(CLLocationCoordinate2D coordinate);

  /// Add a custom raster tile overlay backed by a URL template. [takeSnapshot]
  /// includes it.
  ///
  /// The template uses `{x}`, `{y}`, `{z}` placeholders, e.g.
  /// `https://tile.openstreetmap.org/{z}/{x}/{y}.png`. Throws a
  /// [MapKitPlatformException] with code `duplicate-id` when a tile overlay
  /// with the same id is already on the map — remove it first to replace it.
  Future<void> addTileOverlay(MKTileOverlay overlay);

  /// Remove a previously-added tile overlay. Returns `false` when no tile
  /// overlay with this id is on the map.
  Future<bool> removeTileOverlay(MKTileOverlayId id);

  /// Release platform resources. Called automatically when the owning
  /// `MKMapView` widget unmounts.
  Future<void> dispose();
}

/// Pigeon-backed implementation of [MKMapViewController], plus the
/// state-driven mutations the `MKMapView` diff pipeline pushes over the
/// channel.
///
/// Those mutations stay off [MKMapViewController] so a test double only has
/// to cover the public API, and so their signatures can change without
/// breaking mocks.
@internal
final class MKMapViewControllerImpl implements MKMapViewController {
  /// Creates the controller for a platform view.
  ///
  /// [hostApi] is injectable for tests; in production it defaults to a Pigeon
  /// host API bound to this view's id.
  factory({
    required int viewId,
    required MKMapViewEventSink sink,
    @visibleForTesting MapKitHostApi? hostApi,
  }) {
    final suffix = '$viewId';
    final host = hostApi ?? .new(messageChannelSuffix: suffix);
    return ._(host, sink, suffix);
  }

  new _(this._host, MKMapViewEventSink sink, this._channelSuffix)
    : _eventHandler = _MKMapViewFlutterApi(sink) {
    MapKitFlutterApi.setUp(_eventHandler, messageChannelSuffix: _channelSuffix);
  }

  final MapKitHostApi _host;
  final String _channelSuffix;
  final MapKitFlutterApi _eventHandler;
  bool _disposed = false;

  /// The host→Flutter event handler, exposed for unit tests to simulate
  /// inbound platform callbacks without a live channel.
  @visibleForTesting
  MapKitFlutterApi get eventHandler => _eventHandler;

  // Serial queue: each public mutation enqueues onto _tail so platform
  // messages always land in source order.
  Future<void> _tail = .value();

  /// A caller's request: reaching a disposed map is the caller's misuse.
  Future<T> _enqueue<T>(Future<T> Function() task) => _enqueueOr(
    task,
    whenDisposed: (completer) =>
        completer.completeError(const MapKitDisposedException()),
  );

  /// The widget's own state push: nobody is left to want it once the map is
  /// disposed, so it is dropped. A native rejection still surfaces.
  Future<void> _enqueuePush(Future<void> Function() push) =>
      _enqueueOr(push, whenDisposed: (completer) => completer.complete());

  Future<T> _enqueueOr<T>(
    Future<T> Function() task, {
    required void Function(Completer<T> completer) whenDisposed,
  }) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      if (_disposed) {
        whenDisposed(completer);
        return;
      }
      try {
        completer.complete(await task());
      } on PlatformException catch (e, st) {
        completer.completeError(MapKitException.fromPlatform(e), st);
      } on Object catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  // ------------------------- Public API -------------------------

  @override
  Future<MKMapCamera?> get camera => _enqueue(
    () async => switch (await _host.getCamera()) {
      null => null,
      final camera => .fromPlatform(camera),
    },
  );

  @override
  Future<MKCoordinateRegion?> get region => _enqueue(
    () async => switch (await _host.getRegion()) {
      null => null,
      final region => .fromPlatform(region),
    },
  );

  @override
  Future<void> setCamera(MKMapCamera camera, {bool animated = true}) =>
      _enqueue(() async {
        await _host.setCamera(camera.toPlatform(), animated);
        _dropInitialCamera();
      });

  @override
  Future<void> setRegion(MKCoordinateRegion region, {bool animated = true}) =>
      _enqueue(() async {
        await _host.setRegion(region.toPlatform(), animated);
        _dropInitialCamera();
      });

  @override
  Future<void> setCenter(
    CLLocationCoordinate2D coordinate, {
    bool animated = true,
  }) => _enqueue(() async {
    await _host.setCenter(coordinate.toPlatform(), animated);
    _recenterInitialCamera(coordinate.toPlatform());
  });

  @override
  Future<Offset?> convertToPoint(CLLocationCoordinate2D coordinate) => _enqueue(
    () async => switch (await _host.convertToPoint(coordinate.toPlatform())) {
      null => null,
      final point => .new(point.x, point.y),
    },
  );

  @override
  Future<CLLocationCoordinate2D?> convertToCoordinate(Offset point) => _enqueue(
    () async => switch (await _host.convertToCoordinate(
      .new(x: point.dx, y: point.dy),
    )) {
      null => null,
      final coordinate => .fromPlatform(coordinate),
    },
  );

  @override
  Future<bool> selectAnnotation(MKAnnotationId id) =>
      _enqueue(() => _host.selectAnnotation(id.value));

  @override
  Future<bool> deselectAnnotation(MKAnnotationId id) =>
      _enqueue(() => _host.deselectAnnotation(id.value));

  @override
  Future<bool> isAnnotationSelected(MKAnnotationId id) =>
      _enqueue(() => _host.isAnnotationSelected(id.value));

  @override
  Future<Uint8List> takeSnapshot([
    MKMapSnapshotOptions options = const .new(),
  ]) => _enqueue(() => _host.takeSnapshot(options.toPlatform()));

  @override
  Future<bool> openLookAround(CLLocationCoordinate2D coordinate) =>
      _enqueue(() => _host.openLookAround(coordinate.toPlatform()));

  @override
  Future<void> addTileOverlay(MKTileOverlay overlay) =>
      _enqueue(() => _host.addTileOverlay(overlay.toPlatform()));

  @override
  Future<bool> removeTileOverlay(MKTileOverlayId id) =>
      _enqueue(() => _host.removeTileOverlay(id.value));

  // ------------------------- Widget-driven mutations -------------------------

  /// Non-null until native accepts `initialize`. A rejected one leaves the map
  /// untouched, so the next push retries the whole state.
  _InitialState? _pendingInitialState;

  final _ObjectSync<MKPointAnnotation> _annotations = .new((a) => a.id.value);
  final _ObjectSync<MKPolyline> _polylines = .new((p) => p.id.value);
  final _ObjectSync<MKPolygon> _polygons = .new((p) => p.id.value);
  final _ObjectSync<MKCircle> _circles = .new((c) => c.id.value);

  /// Pushes the initial map state now that the platform view exists. Ids are
  /// unique per kind — `MKMapView` rejects duplicates before calling this.
  Future<void> initialize({
    required MKMapCamera initialCamera,
    required PlatformMapConfiguration configuration,
    required Set<MKPointAnnotation> annotations,
    required Set<MKPolyline> polylines,
    required Set<MKPolygon> polygons,
    required Set<MKCircle> circles,
  }) {
    // Copied now, not when the queue drains: the Sets are the caller's, and
    // onMapCreated may mutate them in place before then.
    _pendingInitialState = (
      camera: initialCamera.toPlatform(),
      configuration: configuration,
    );
    _annotations.queued = {...annotations};
    _polylines.queued = {...polylines};
    _polygons.queued = {...polygons};
    _circles.queued = {...circles};
    return _enqueuePush(_pushInitialState);
  }

  Future<void> _pushInitialState() async {
    final pending = _pendingInitialState;
    if (pending == null) return;
    final annotations = _annotations.queued;
    final polylines = _polylines.queued;
    final polygons = _polygons.queued;
    final circles = _circles.queued;
    await _host.initialize(
      .new(
        initialCamera: pending.camera,
        configuration: pending.configuration,
        annotations: [for (final a in annotations) a.toPlatform()],
        polylines: [for (final p in polylines) p.toPlatform()],
        polygons: [for (final p in polygons) p.toPlatform()],
        circles: [for (final c in circles) c.toPlatform()],
      ),
    );
    _pendingInitialState = null;
    _annotations.accepted = annotations;
    _polylines.accepted = polylines;
    _polygons.accepted = polygons;
    _circles.accepted = circles;
  }

  /// A retried `initialize` must not undo a move native accepted after the
  /// rejected one.
  void _dropInitialCamera() {
    if (_pendingInitialState case (:final configuration, camera: _)) {
      _pendingInitialState = (camera: null, configuration: configuration);
    }
  }

  /// A center move leaves distance, heading and pitch to the initial camera,
  /// which then still has to apply them.
  void _recenterInitialCamera(PlatformCoordinate center) {
    if (_pendingInitialState case (
      :final configuration,
      camera: final camera?,
    )) {
      _pendingInitialState = (
        camera: .new(
          centerCoordinate: center,
          distance: camera.distance,
          heading: camera.heading,
          pitch: camera.pitch,
        ),
        configuration: configuration,
      );
    }
  }

  Future<void> updateMapConfiguration(PlatformMapConfiguration configuration) {
    if (_pendingInitialState case final pending?) {
      _pendingInitialState = (
        camera: pending.camera,
        configuration: configuration,
      );
    }
    return _enqueuePush(
      () => _pendingInitialState == null
          ? _host.updateMapConfiguration(configuration)
          : _pushInitialState(),
    );
  }

  /// Brings native to [target], diffing when the queue reaches this push and
  /// against what native accepted: a rejected batch stays undone, so the next
  /// different [target] resends everything it held.
  Future<void> _sync<T extends Object>(
    _ObjectSync<T> sync,
    Set<T> target,
    Future<void> Function(MapObjectUpdates<T> updates) send,
  ) {
    if (setEquals(target, sync.queued)) return .value();
    sync.queued = {...target};
    return _enqueuePush(() async {
      if (_pendingInitialState != null) {
        await _pushInitialState();
        return;
      }
      final latest = sync.queued;
      final updates = MapObjectUpdates.between(
        sync.accepted,
        latest,
        idOf: sync.idOf,
      );
      if (updates.isEmpty()) return;
      await send(updates);
      sync.accepted = latest;
    });
  }

  Future<void> syncAnnotations(Set<MKPointAnnotation> target) => _sync(
    _annotations,
    target,
    (updates) => _host.updateAnnotations(
      updates.toAdd.map((a) => a.toPlatform()).toList(),
      updates.toChange.map((a) => a.toPlatform()).toList(),
      updates.idsToRemove.toList(),
    ),
  );

  Future<void> syncPolylines(Set<MKPolyline> target) => _sync(
    _polylines,
    target,
    (updates) => _host.updatePolylines(
      updates.toAdd.map((p) => p.toPlatform()).toList(),
      updates.toChange.map((p) => p.toPlatform()).toList(),
      updates.idsToRemove.toList(),
    ),
  );

  Future<void> syncPolygons(Set<MKPolygon> target) => _sync(
    _polygons,
    target,
    (updates) => _host.updatePolygons(
      updates.toAdd.map((p) => p.toPlatform()).toList(),
      updates.toChange.map((p) => p.toPlatform()).toList(),
      updates.idsToRemove.toList(),
    ),
  );

  Future<void> syncCircles(Set<MKCircle> target) => _sync(
    _circles,
    target,
    (updates) => _host.updateCircles(
      updates.toAdd.map((c) => c.toPlatform()).toList(),
      updates.toChange.map((c) => c.toPlatform()).toList(),
      updates.idsToRemove.toList(),
    ),
  );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    MapKitFlutterApi.setUp(null, messageChannelSuffix: _channelSuffix);
    try {
      await _host.dispose();
    } on PlatformException {
      // The native view is already gone; nothing left to release.
    }
  }
}

typedef _InitialState = ({
  PlatformMapCamera? camera,
  PlatformMapConfiguration configuration,
});

/// One kind of map object: the set last queued for native, which a rebuild
/// compares against, and the set native accepted, which a diff starts from.
final class _ObjectSync<T extends Object>(final String Function(T) idOf) {
  Set<T> queued = const {};
  Set<T> accepted = const {};
}

/// Adapts the generated [MapKitFlutterApi] onto the widget's
/// [MKMapViewEventSink], converting `Platform*` payloads back to the public
/// model types.
///
/// Generated handlers turn a throw into an error reply, which only reaches the
/// native sender, so every path reports it here instead. Payload conversion
/// runs inside the guard too: it validates.
final class _MKMapViewFlutterApi(final MKMapViewEventSink _sink)
    implements MapKitFlutterApi {
  void _deliver(String event, void Function() call) {
    try {
      call();
    } on Object catch (exception, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'mapkit_flutter',
          context: ErrorDescription('while delivering $event'),
        ),
      );
    }
  }

  @override
  void onCameraMoveStarted() =>
      _deliver('onCameraMoveStarted', _sink.onCameraMoveStarted);

  @override
  void onCameraMove(PlatformMapCamera camera) =>
      _deliver('onCameraMove', () => _sink.onCameraMove(.fromPlatform(camera)));

  @override
  void onCameraIdle() => _deliver('onCameraIdle', _sink.onCameraIdle);

  @override
  void onUserTrackingModeChanged(PlatformUserTrackingMode mode) => _deliver(
    'onUserTrackingModeChanged',
    () => _sink.onUserTrackingModeChanged(mode),
  );

  @override
  void onAnnotationSelect(String annotationId) => _deliver(
    'onAnnotationSelect',
    () => _sink.onAnnotationSelect(.new(annotationId)),
  );

  @override
  void onAnnotationDeselect(String annotationId) => _deliver(
    'onAnnotationDeselect',
    () => _sink.onAnnotationDeselect(.new(annotationId)),
  );

  @override
  void onMapFeatureSelected(PlatformMapFeature feature) => _deliver(
    'onMapFeatureSelected',
    () => _sink.onMapFeatureSelected(.fromPlatform(feature)),
  );

  @override
  void onAnnotationDragStart(
    String annotationId,
    PlatformCoordinate coordinate,
  ) => _deliver(
    'onAnnotationDragStart',
    () => _sink.onAnnotationDragStart(
      .new(annotationId),
      .fromPlatform(coordinate),
    ),
  );

  @override
  void onAnnotationDragEnd(
    String annotationId,
    PlatformCoordinate coordinate,
  ) => _deliver(
    'onAnnotationDragEnd',
    () => _sink.onAnnotationDragEnd(
      .new(annotationId),
      .fromPlatform(coordinate),
    ),
  );

  @override
  void onCalloutTap(String annotationId) =>
      _deliver('onCalloutTap', () => _sink.onCalloutTap(.new(annotationId)));

  @override
  void onPolylineTap(String polylineId) =>
      _deliver('onPolylineTap', () => _sink.onPolylineTap(.new(polylineId)));

  @override
  void onPolygonTap(String polygonId) =>
      _deliver('onPolygonTap', () => _sink.onPolygonTap(.new(polygonId)));

  @override
  void onCircleTap(String circleId) =>
      _deliver('onCircleTap', () => _sink.onCircleTap(.new(circleId)));

  @override
  void onMapTap(PlatformCoordinate coordinate) =>
      _deliver('onMapTap', () => _sink.onMapTap(.fromPlatform(coordinate)));

  @override
  void onMapLongPress(PlatformCoordinate coordinate) => _deliver(
    'onMapLongPress',
    () => _sink.onMapLongPress(.fromPlatform(coordinate)),
  );

  @override
  void onDidFailLoadingMap(String error) =>
      _deliver('onDidFailLoadingMap', () => _sink.onDidFailLoadingMap(error));

  @override
  void onDidFailToLocateUser(String error) => _deliver(
    'onDidFailToLocateUser',
    () => _sink.onDidFailToLocateUser(error),
  );
}
