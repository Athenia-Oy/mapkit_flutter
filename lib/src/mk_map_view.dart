import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mapkit_flutter/src/_internal/map_object_updates.dart';
import 'package:mapkit_flutter/src/cl_location_coordinate_2d.dart';
import 'package:mapkit_flutter/src/exceptions.dart';
import 'package:mapkit_flutter/src/messages.g.dart';
import 'package:mapkit_flutter/src/mk_camera_zoom_range.dart';
import 'package:mapkit_flutter/src/mk_circle.dart';
import 'package:mapkit_flutter/src/mk_coordinate_region.dart';
import 'package:mapkit_flutter/src/mk_enums.dart';
import 'package:mapkit_flutter/src/mk_map_camera.dart';
import 'package:mapkit_flutter/src/mk_map_configuration.dart';
import 'package:mapkit_flutter/src/mk_map_feature.dart';
import 'package:mapkit_flutter/src/mk_map_view_controller.dart';
import 'package:mapkit_flutter/src/mk_point_annotation.dart';
import 'package:mapkit_flutter/src/mk_polygon.dart';
import 'package:mapkit_flutter/src/mk_polyline.dart';

/// Displays an Apple Maps `MKMapView` as a Flutter platform view.
///
/// Mirrors `MKMapView`'s own API shape: the base style is a sealed
/// [preferredConfiguration], while view-level switches ([showsUserLocation],
/// [isZoomEnabled], [cameraZoomRange]…) are direct parameters — exactly the
/// properties they are on `MKMapView`. Content is declarative: [annotations]
/// and overlay sets diff on rebuild.
///
/// iOS and macOS only. Building this widget on any other platform throws a
/// [MapKitUnsupportedPlatformException] rather than degrading silently; so
/// does an iOS-only setting on macOS (`followWithHeading`,
/// [selectableMapFeatures], [onMapFeatureSelected],
/// `insetsLayoutMarginsFromSafeArea: false`, an annotation's
/// `calloutConsumesTapEvents`).
///
/// Ids must be unique per kind: two annotations (or two polylines, …)
/// sharing an id throw an [ArgumentError] when the widget is built or
/// updated.
/// See: https://developer.apple.com/documentation/mapkit/mkmapview
final class const MKMapView({
  /// Where the camera starts (`MKMapCamera`).
  required final MKMapCamera initialCamera,
  super.key,

  /// The map's base style (`MKMapView.preferredConfiguration`).
  final MKMapConfiguration preferredConfiguration =
      const MKStandardMapConfiguration(),

  /// Whether pinch/scroll zoom gestures are enabled (`MKMapView.isZoomEnabled`).
  final bool isZoomEnabled = true,

  /// Whether pan/scroll gestures are enabled (`MKMapView.isScrollEnabled`).
  final bool isScrollEnabled = true,

  /// Whether two-finger rotation gestures are enabled
  /// (`MKMapView.isRotateEnabled`).
  final bool isRotateEnabled = true,

  /// Whether two-finger tilt gestures are enabled (`MKMapView.isPitchEnabled`).
  final bool isPitchEnabled = true,

  /// Shows the user's location (`MKMapView.showsUserLocation`).
  ///
  /// Like MapKit, the map never asks for location permission: request
  /// when-in-use authorization in your app first (and add
  /// `NSLocationWhenInUseUsageDescription` to `Info.plist`). Without it the
  /// map reports the failure through [onDidFailToLocateUser].
  final bool showsUserLocation = false,

  /// `MKMapView.showsUserTrackingButton` (iOS 17 / macOS 14).
  final bool showsUserTrackingButton = false,

  /// Whether the compass control appears when the map is rotated away from
  /// north (`MKMapView.showsCompass`).
  final bool showsCompass = true,

  /// Whether the distance scale indicator appears while zooming
  /// (`MKMapView.showsScale`).
  final bool showsScale = false,

  /// How the camera tracks the user's location (`MKMapView.userTrackingMode`).
  ///
  /// Applied when this value changes. MapKit itself changes the mode — it
  /// drops to `none` when the user pans — and reports it through
  /// [onUserTrackingModeChanged]; keep your state in sync there so a later
  /// rebuild with `follow` re-applies it. `followWithHeading` is iOS only.
  final MKUserTrackingMode userTrackingMode = .none,

  /// Called when MapKit changes [userTrackingMode] itself
  /// (`MKMapViewDelegate.mapView(_:didChange:animated:)`).
  final ValueChanged<MKUserTrackingMode>? onUserTrackingModeChanged,

  /// Camera distance limits in meters (`MKMapView.cameraZoomRange`).
  final MKCameraZoomRange cameraZoomRange = .unbounded,

  /// Region the camera center is constrained to
  /// (`MKMapView.cameraBoundary`).
  final MKCoordinateRegion? cameraBoundary,

  /// Map features the user can tap to select
  /// (`MKMapView.selectableMapFeatures`). iOS only — must stay empty on
  /// macOS.
  final Set<MKMapFeatureOptions> selectableMapFeatures = const {},

  /// Whether layout margins include the safe area insets
  /// (`UIView.insetsLayoutMarginsFromSafeArea`). iOS only — must stay `true`
  /// on macOS.
  final bool insetsLayoutMarginsFromSafeArea = true,

  /// Point annotations displayed on the map, diffed by [MKAnnotationId].
  final Set<MKPointAnnotation> annotations = const {},

  /// Polyline overlays displayed on the map, diffed by [MKPolylineId].
  final Set<MKPolyline> polylines = const {},

  /// Polygon overlays displayed on the map, diffed by [MKPolygonId].
  final Set<MKPolygon> polygons = const {},

  /// Circle overlays displayed on the map, diffed by [MKCircleId].
  final Set<MKCircle> circles = const {},

  /// Gesture recognizers that participate in the platform view's gesture
  /// arena.
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers =
      const {},

  /// Called once with the [MKMapViewController] when the native map view is
  /// ready.
  final void Function(MKMapViewController controller)? onMapCreated,

  /// Called when the camera begins moving
  /// (`MKMapViewDelegate.mapView(_:regionWillChangeAnimated:)`).
  final VoidCallback? onCameraMoveStarted,

  /// Fires every frame the visible region changes — gestures, momentum and
  /// animations, both platforms
  /// (`MKMapViewDelegate.mapViewDidChangeVisibleRegion(_:)`).
  final void Function(MKMapCamera camera)? onCameraMove,

  /// Called when the camera finishes moving
  /// (`MKMapViewDelegate.mapView(_:regionDidChangeAnimated:)`).
  final VoidCallback? onCameraIdle,

  /// Called when the user taps the map at `coordinate` (when not consumed by
  /// an annotation or overlay).
  final void Function(CLLocationCoordinate2D coordinate)? onTap,

  /// Called when the user long-presses the map at `coordinate`.
  final void Function(CLLocationCoordinate2D coordinate)? onLongPress,

  /// Map content failed to load, e.g. no network
  /// (`MKMapViewDelegate.mapViewDidFailLoadingMap(_:withError:)`).
  final ValueChanged<String>? onDidFailLoadingMap,

  /// The map could not determine the user's location — most commonly because
  /// location permission was denied — while [showsUserLocation] is enabled
  /// (`MKMapViewDelegate.mapView(_:didFailToLocateUserWithError:)`).
  final ValueChanged<String>? onDidFailToLocateUser,

  /// The user selected a map feature (`MKMapFeatureAnnotation`). iOS only
  /// (must be `null` on macOS); needs [selectableMapFeatures].
  final ValueChanged<MKMapFeature>? onMapFeatureSelected,

  /// Replaces the platform view with an injected controller so widget tests
  /// can drive the full diff pipeline against a fake host API. When set,
  /// `build` renders a plain box instead of a `UiKitView`/`AppKitView` and
  /// skips the platform check.
  @visibleForTesting
  final MKMapViewControllerImpl Function(MKMapViewEventSink sink)?
  debugControllerFactory,
}) extends StatefulWidget {
  /// Creates an Apple MapKit view widget.
  this;

  @override
  State<MKMapView> createState() => _MKMapViewState();
}

final class _MKMapViewState extends State<MKMapView>
    implements MKMapViewEventSink {
  MKMapViewControllerImpl? _controller;

  Map<MKAnnotationId, MKPointAnnotation> _annotations = const {};
  Map<MKPolylineId, MKPolyline> _polylines = const {};
  Map<MKPolygonId, MKPolygon> _polygons = const {};
  Map<MKCircleId, MKCircle> _circles = const {};

  @override
  void initState() {
    super.initState();
    _checkWidget();
    _annotations = {for (final a in widget.annotations) a.id: a};
    _polylines = {for (final p in widget.polylines) p.id: p};
    _polygons = {for (final p in widget.polygons) p.id: p};
    _circles = {for (final c in widget.circles) c.id: c};
    if (widget.debugControllerFactory case final factory?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _wireController(factory(this));
      });
    }
  }

  /// Rejects what MapKit can't represent before anything reaches native:
  /// duplicate ids (one would silently replace the other) and iOS-only
  /// settings on macOS (they would silently do nothing).
  void _checkWidget() {
    final w = widget;
    _checkUniqueIds('annotations', w.annotations, (a) => a.id.value);
    _checkUniqueIds('polylines', w.polylines, (p) => p.id.value);
    _checkUniqueIds('polygons', w.polygons, (p) => p.id.value);
    _checkUniqueIds('circles', w.circles, (c) => c.id.value);
    if (defaultTargetPlatform == .macOS) _checkMacOSSupport(w);
  }

  static void _checkUniqueIds<T>(
    String name,
    Set<T> objects,
    String Function(T) idOf,
  ) {
    final seen = <String>{};
    for (final object in objects) {
      final id = idOf(object);
      if (!seen.add(id)) {
        throw ArgumentError(
          'MKMapView.$name contains two objects with id "$id"',
        );
      }
    }
  }

  static void _checkMacOSSupport(MKMapView w) {
    Never unsupported(String feature) =>
        throw MapKitUnsupportedPlatformException(.macOS, feature: feature);
    if (w.userTrackingMode == .followWithHeading) {
      unsupported('MKMapView.userTrackingMode: followWithHeading');
    }
    if (w.selectableMapFeatures.isNotEmpty) {
      unsupported('MKMapView.selectableMapFeatures');
    }
    if (w.onMapFeatureSelected != null) {
      unsupported('MKMapView.onMapFeatureSelected');
    }
    if (!w.insetsLayoutMarginsFromSafeArea) {
      unsupported('MKMapView.insetsLayoutMarginsFromSafeArea: false');
    }
    for (final a in w.annotations) {
      if (a.calloutConsumesTapEvents) {
        unsupported(
          'MKPointAnnotation.calloutConsumesTapEvents (id "${a.id.value}")',
        );
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.debugControllerFactory != null) return const SizedBox.expand();

    const viewType = 'dev.mapkit.flutter/map_view';
    return switch (defaultTargetPlatform) {
      .iOS => UiKitView(
        viewType: viewType,
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: widget.gestureRecognizers,
        creationParamsCodec: const StandardMessageCodec(),
      ),
      .macOS => AppKitView(
        viewType: viewType,
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: widget.gestureRecognizers,
        creationParamsCodec: const StandardMessageCodec(),
      ),
      _ => throw MapKitUnsupportedPlatformException(defaultTargetPlatform),
    };
  }

  void _onPlatformViewCreated(int id) =>
      _wireController(.new(viewId: id, sink: this));

  /// Push the full initial state over the type-safe channel now that the
  /// platform view (and its host API handler) exists.
  void _wireController(MKMapViewControllerImpl controller) {
    _controller = controller;
    controller.initialize(
      initialCamera: widget.initialCamera,
      configuration: _platformConfiguration(),
      annotations: widget.annotations,
      polylines: widget.polylines,
      polygons: widget.polygons,
      circles: widget.circles,
    );
    widget.onMapCreated?.call(controller);
  }

  /// Flattens the sealed [MKMapConfiguration] plus the widget's view-level
  /// properties into the wire bundle.
  PlatformMapConfiguration _platformConfiguration() {
    final (
      PlatformMapKind kind,
      MKMapEmphasisStyle emphasisStyle,
      bool showsTraffic,
      PlatformPointOfInterestFilter? pointOfInterestFilter,
    ) = widget.preferredConfiguration
        ._platformProperties();

    return .new(
      kind: kind,
      emphasisStyle: emphasisStyle,
      elevationStyle: widget.preferredConfiguration.elevationStyle,
      showsTraffic: showsTraffic,
      showsCompass: widget.showsCompass,
      showsScale: widget.showsScale,
      showsUserLocation: widget.showsUserLocation,
      showsUserTrackingButton: widget.showsUserTrackingButton,
      userTrackingMode: widget.userTrackingMode,
      insetsLayoutMarginsFromSafeArea: widget.insetsLayoutMarginsFromSafeArea,
      isRotateEnabled: widget.isRotateEnabled,
      isScrollEnabled: widget.isScrollEnabled,
      isZoomEnabled: widget.isZoomEnabled,
      isPitchEnabled: widget.isPitchEnabled,
      selectableMapFeatures: widget.selectableMapFeatures.toList(),
      pointOfInterestFilter: pointOfInterestFilter,
      cameraZoomRange: widget.cameraZoomRange.toPlatform(),
      cameraBoundary: widget.cameraBoundary?.toPlatform(),
    );
  }

  bool _configurationChanged(MKMapView old) =>
      widget.preferredConfiguration != old.preferredConfiguration ||
      widget.isZoomEnabled != old.isZoomEnabled ||
      widget.isScrollEnabled != old.isScrollEnabled ||
      widget.isRotateEnabled != old.isRotateEnabled ||
      widget.isPitchEnabled != old.isPitchEnabled ||
      widget.showsUserLocation != old.showsUserLocation ||
      widget.showsUserTrackingButton != old.showsUserTrackingButton ||
      widget.showsCompass != old.showsCompass ||
      widget.showsScale != old.showsScale ||
      widget.userTrackingMode != old.userTrackingMode ||
      widget.cameraZoomRange != old.cameraZoomRange ||
      widget.cameraBoundary != old.cameraBoundary ||
      !setEquals(widget.selectableMapFeatures, old.selectableMapFeatures) ||
      widget.insetsLayoutMarginsFromSafeArea !=
          old.insetsLayoutMarginsFromSafeArea;

  @override
  void didUpdateWidget(covariant MKMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkWidget();
    _updateDispatchTables();
    final c = _controller;
    if (c == null) return;

    _updateConfiguration(c, oldWidget);
    _updateAnnotations(c, oldWidget);
    _updatePolylines(c, oldWidget);
    _updatePolygons(c, oldWidget);
    _updateCircles(c, oldWidget);
  }

  void _updateDispatchTables() {
    // Refresh the id→object dispatch tables on every rebuild, before the diff
    // gates below. The models' `==` excludes callbacks (so a closure swap
    // doesn't trigger a needless native recycle); a rebuild that changes only
    // an `onTap`/`onDrag*` closure is therefore `setEquals`-equal and skips the
    // native update — but these tables back inbound event dispatch and must
    // still pick up the fresh closures, or a tap fires stale captured state.
    _annotations = {for (final a in widget.annotations) a.id: a};
    _polylines = {for (final p in widget.polylines) p.id: p};
    _polygons = {for (final p in widget.polygons) p.id: p};
    _circles = {for (final o in widget.circles) o.id: o};
  }

  void _updateConfiguration(MKMapViewControllerImpl c, MKMapView oldWidget) {
    if (_configurationChanged(oldWidget)) {
      c.updateMapConfiguration(_platformConfiguration());
    }
  }

  void _updateAnnotations(MKMapViewControllerImpl c, MKMapView oldWidget) {
    if (!setEquals(widget.annotations, oldWidget.annotations)) {
      final updates = MapObjectUpdates.between(
        oldWidget.annotations,
        widget.annotations,
        idOf: (a) => a.id.value,
      );
      c.updateAnnotations(updates);
    }
  }

  void _updatePolylines(MKMapViewControllerImpl c, MKMapView oldWidget) {
    if (!setEquals(widget.polylines, oldWidget.polylines)) {
      final updates = MapObjectUpdates.between(
        oldWidget.polylines,
        widget.polylines,
        idOf: (p) => p.id.value,
      );
      c.updatePolylines(updates);
    }
  }

  void _updatePolygons(MKMapViewControllerImpl c, MKMapView oldWidget) {
    if (!setEquals(widget.polygons, oldWidget.polygons)) {
      final updates = MapObjectUpdates.between(
        oldWidget.polygons,
        widget.polygons,
        idOf: (p) => p.id.value,
      );
      c.updatePolygons(updates);
    }
  }

  void _updateCircles(MKMapViewControllerImpl c, MKMapView oldWidget) {
    if (!setEquals(widget.circles, oldWidget.circles)) {
      final updates = MapObjectUpdates.between(
        oldWidget.circles,
        widget.circles,
        idOf: (o) => o.id.value,
      );
      c.updateCircles(updates);
    }
  }

  @override
  void onCameraMoveStarted() => widget.onCameraMoveStarted?.call();

  @override
  void onCameraMove(MKMapCamera camera) => widget.onCameraMove?.call(camera);

  @override
  void onCameraIdle() => widget.onCameraIdle?.call();

  @override
  void onUserTrackingModeChanged(MKUserTrackingMode mode) =>
      widget.onUserTrackingModeChanged?.call(mode);

  @override
  void onAnnotationSelect(MKAnnotationId id) =>
      _annotations[id]?.onSelect?.call();

  @override
  void onAnnotationDeselect(MKAnnotationId id) =>
      _annotations[id]?.onDeselect?.call();

  @override
  void onMapFeatureSelected(MKMapFeature feature) =>
      widget.onMapFeatureSelected?.call(feature);

  @override
  void onAnnotationDragStart(
    MKAnnotationId id,
    CLLocationCoordinate2D coordinate,
  ) => _annotations[id]?.onDragStart?.call(coordinate);

  @override
  void onAnnotationDragEnd(
    MKAnnotationId id,
    CLLocationCoordinate2D coordinate,
  ) => _annotations[id]?.onDragEnd?.call(coordinate);

  @override
  void onCalloutTap(MKAnnotationId id) =>
      _annotations[id]?.onCalloutTap?.call();

  @override
  void onPolylineTap(MKPolylineId id) => _polylines[id]?.onTap?.call();

  @override
  void onPolygonTap(MKPolygonId id) => _polygons[id]?.onTap?.call();

  @override
  void onCircleTap(MKCircleId id) => _circles[id]?.onTap?.call();

  @override
  void onMapTap(CLLocationCoordinate2D coordinate) =>
      widget.onTap?.call(coordinate);

  @override
  void onMapLongPress(CLLocationCoordinate2D coordinate) =>
      widget.onLongPress?.call(coordinate);

  @override
  void onDidFailLoadingMap(String error) =>
      widget.onDidFailLoadingMap?.call(error);

  @override
  void onDidFailToLocateUser(String error) =>
      widget.onDidFailToLocateUser?.call(error);
}

extension on MKMapConfiguration {
  (PlatformMapKind, MKMapEmphasisStyle, bool, PlatformPointOfInterestFilter?)
  _platformProperties() => switch (this) {
    MKStandardMapConfiguration(
      :final emphasisStyle,
      :final showsTraffic,
      :final pointOfInterestFilter,
    ) =>
      (
        .standard,
        emphasisStyle,
        showsTraffic,
        pointOfInterestFilter.toPlatform(),
      ),
    MKHybridMapConfiguration(
      :final showsTraffic,
      :final pointOfInterestFilter,
    ) =>
      (.hybrid, .standard, showsTraffic, pointOfInterestFilter.toPlatform()),
    MKImageryMapConfiguration() => (.imagery, .standard, false, null),
  };
}
