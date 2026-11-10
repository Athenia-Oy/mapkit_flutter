import 'dart:typed_data';

import 'package:mapkit_flutter/src/messages.g.dart';

/// Records every host call and returns canned responses, standing in for the
/// generated Pigeon channel. Set [errorToThrow] to make the next call fail.
final class FakeHostApi extends MapKitHostApi {
  new() : super();

  final List<(String, Object?)> calls = [];

  /// Names of every call that reached the host, whether it succeeded or threw.
  final List<String> attemptedCallNames = [];

  /// Names of all recorded calls, in order.
  List<String> get callNames => [for (final c in calls) c.$1];

  PlatformMapCamera? camera = .new(
    centerCoordinate: .new(latitude: 0, longitude: 0),
    distance: 1000,
    heading: 0,
    pitch: 0,
  );
  PlatformCoordinateRegion? region = .new(
    center: .new(latitude: 0, longitude: 0),
    span: .new(latitudeDelta: 0, longitudeDelta: 0),
  );
  PlatformPoint? point;
  PlatformCoordinate? coordinate;
  bool annotationSelected = false;
  bool selectResult = true;
  bool deselectResult = true;
  bool removeTileOverlayResult = true;
  bool lookAroundResult = false;
  Object? errorToThrow;
  bool keepThrowing = false;

  /// Holds [takeSnapshot] in flight, keeping the controller's queue busy.
  Future<void>? snapshotGate;

  void _record(String name, Object? args) {
    attemptedCallNames.add(name);
    final e = errorToThrow;
    if (e case final error?) {
      if (!keepThrowing) errorToThrow = null;
      // Rethrows whatever the test staged — Exception or Error — so both
      // halves of _enqueue's generic catch are reachable.
      // ignore: only_throw_errors
      throw error;
    }
    calls.add((name, args));
  }

  @override
  Future<void> initialize(PlatformMapViewCreationParams params) async =>
      _record('initialize', params);

  @override
  Future<void> setCamera(PlatformMapCamera camera, bool animated) async =>
      _record('setCamera', (camera, animated));

  @override
  Future<void> setRegion(
    PlatformCoordinateRegion region,
    bool animated,
  ) async => _record('setRegion', (region, animated));

  @override
  Future<void> setCenter(PlatformCoordinate coordinate, bool animated) async =>
      _record('setCenter', (coordinate, animated));

  @override
  Future<PlatformMapCamera?> getCamera() async {
    _record('getCamera', null);
    return camera;
  }

  @override
  Future<PlatformCoordinateRegion?> getRegion() async {
    _record('getRegion', null);
    return region;
  }

  @override
  Future<PlatformPoint?> convertToPoint(PlatformCoordinate coordinate) async {
    _record('convertToPoint', coordinate);
    return point;
  }

  @override
  Future<PlatformCoordinate?> convertToCoordinate(PlatformPoint point) async {
    _record('convertToCoordinate', point);
    return coordinate;
  }

  @override
  Future<void> updateAnnotations(
    List<PlatformAnnotation> toAdd,
    List<PlatformAnnotation> toChange,
    List<String> idsToRemove,
  ) async => _record('updateAnnotations', (toAdd, toChange, idsToRemove));

  @override
  Future<void> updatePolylines(
    List<PlatformPolyline> toAdd,
    List<PlatformPolyline> toChange,
    List<String> idsToRemove,
  ) async => _record('updatePolylines', (toAdd, toChange, idsToRemove));

  @override
  Future<void> updatePolygons(
    List<PlatformPolygon> toAdd,
    List<PlatformPolygon> toChange,
    List<String> idsToRemove,
  ) async => _record('updatePolygons', (toAdd, toChange, idsToRemove));

  @override
  Future<void> updateCircles(
    List<PlatformCircle> toAdd,
    List<PlatformCircle> toChange,
    List<String> idsToRemove,
  ) async => _record('updateCircles', (toAdd, toChange, idsToRemove));

  @override
  Future<void> updateMapConfiguration(
    PlatformMapConfiguration configuration,
  ) async => _record('updateMapConfiguration', configuration);

  @override
  Future<bool> selectAnnotation(String annotationId) async {
    _record('selectAnnotation', annotationId);
    return selectResult;
  }

  @override
  Future<bool> deselectAnnotation(String annotationId) async {
    _record('deselectAnnotation', annotationId);
    return deselectResult;
  }

  @override
  Future<bool> isAnnotationSelected(String annotationId) async {
    _record('isAnnotationSelected', annotationId);
    return annotationSelected;
  }

  @override
  Future<Uint8List> takeSnapshot(PlatformSnapshotOptions options) async {
    await snapshotGate;
    _record('takeSnapshot', options);
    return .new(0);
  }

  @override
  Future<bool> openLookAround(PlatformCoordinate coordinate) async {
    _record('openLookAround', coordinate);
    return lookAroundResult;
  }

  @override
  Future<void> addTileOverlay(PlatformTileOverlay overlay) async =>
      _record('addTileOverlay', overlay);

  @override
  Future<bool> removeTileOverlay(String tileOverlayId) async {
    _record('removeTileOverlay', tileOverlayId);
    return removeTileOverlayResult;
  }

  @override
  Future<void> dispose() async => _record('dispose', null);
}
