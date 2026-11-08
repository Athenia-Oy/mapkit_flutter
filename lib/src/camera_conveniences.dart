import 'dart:math' show max, pow;

import 'package:mapkit_flutter/src/_internal/validate.dart';
import 'package:mapkit_flutter/src/cl_location_coordinate_2d.dart';
import 'package:mapkit_flutter/src/mk_coordinate_region.dart';
import 'package:mapkit_flutter/src/mk_map_camera.dart';
import 'package:mapkit_flutter/src/mk_map_view_controller.dart';

/// google_maps_flutter-dialect camera helpers layered over the canonical
/// MapKit surface. Every method composes [MKMapViewController.camera] with
/// `setCamera` / `setRegion` / `setCenter` — no extra platform calls exist
/// behind them.
///
/// Each call performs a read-then-write round trip, so during an active
/// user gesture the result may lag the live camera.
extension CameraConveniences on MKMapViewController {
  /// Approximate Web-Mercator zoom level of the current camera.
  ///
  /// google_maps_flutter dialect; canonical: `(await camera)?.zoomLevel`.
  /// Like every camera-relative helper here, throws [StateError] while the
  /// view has no layout.
  Future<double> getZoomLevel() async =>
      (await _laidOutCamera('getZoomLevel')).zoomLevel;

  /// Move to an absolute zoom level, preserving center, heading, and pitch.
  ///
  /// google_maps_flutter dialect; canonical: `setCamera` with
  /// `MKMapCamera.withZoomLevel`.
  Future<void> zoomTo(double zoomLevel, {bool animated = true}) async {
    final current = await _laidOutCamera('zoomTo');
    await setCamera(
      .withZoomLevel(
        centerCoordinate: current.centerCoordinate,
        zoomLevel: zoomLevel,
        heading: current.heading,
        pitch: current.pitch,
      ),
      animated: animated,
    );
  }

  /// Zoom by [amount] levels (positive zooms in), preserving center,
  /// heading, and pitch.
  ///
  /// google_maps_flutter dialect; canonical: `setCamera` with a scaled
  /// `MKMapCamera.distance`.
  Future<void> zoomBy(double amount, {bool animated = true}) async {
    final current = await _laidOutCamera('zoomBy');
    await setCamera(
      current.copyWith(distance: current.distance / pow(2.0, amount)),
      animated: animated,
    );
  }

  /// Zoom in one level. google_maps_flutter dialect.
  Future<void> zoomIn({bool animated = true}) => zoomBy(1, animated: animated);

  /// Zoom out one level. google_maps_flutter dialect.
  Future<void> zoomOut({bool animated = true}) =>
      zoomBy(-1, animated: animated);

  /// Pan the camera by a screen-pixel offset.
  ///
  /// google_maps_flutter dialect; canonical: the `convertToPoint` /
  /// `convertToCoordinate` pair plus `setCenter`. Throws [StateError] while
  /// the view has no layout — there is no screen to scroll yet.
  Future<void> scrollBy(double dx, double dy, {bool animated = true}) async {
    final current = await _laidOutCamera('scrollBy');
    final centerPoint = await convertToPoint(current.centerCoordinate);
    if (centerPoint == null) throw _noLayout('scrollBy');
    final target = await convertToCoordinate(centerPoint + .new(dx, dy));
    if (target == null) throw _noLayout('scrollBy');
    await setCenter(target, animated: animated);
  }

  /// Move the camera so all [coordinates] are visible.
  ///
  /// [padding] adds that fraction of the span on each side; [minimumSpan]
  /// (degrees) keeps a single coordinate or a tight cluster from zooming
  /// fully in.
  ///
  /// google_maps_flutter dialect (`CameraUpdate.newLatLngBounds`); canonical:
  /// `setRegion(MKCoordinateRegion.containing(coordinates))`. Throws
  /// [ArgumentError] when [coordinates] is empty (nothing to fit),
  /// [padding] / [minimumSpan] is negative or non-finite, or they widen a span
  /// past what `MKCoordinateSpan` allows (180° latitude, 360° longitude).
  Future<void> fitCoordinates(
    Iterable<CLLocationCoordinate2D> coordinates, {
    bool animated = true,
    double padding = 0,
    double minimumSpan = 0.005,
  }) async {
    checkNonNegative(padding, 'padding');
    checkNonNegative(minimumSpan, 'minimumSpan');
    final region = MKCoordinateRegion.containing(coordinates);
    if (region == null) {
      throw ArgumentError.value(
        coordinates,
        'coordinates',
        'must not be empty',
      );
    }
    double fit(double delta) => max(delta * (1 + 2 * padding), minimumSpan);
    await setRegion(
      .new(
        center: region.center,
        span: .new(
          latitudeDelta: fit(region.span.latitudeDelta),
          longitudeDelta: fit(region.span.longitudeDelta),
        ),
      ),
      animated: animated,
    );
  }

  Future<MKMapCamera> _laidOutCamera(String method) async =>
      await camera ?? (throw _noLayout(method));

  StateError _noLayout(String method) =>
      .new('$method needs a laid-out map view (no layout yet).');
}
