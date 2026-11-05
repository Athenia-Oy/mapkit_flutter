// Pigeon schema for the type-safe Dart <-> Swift boundary.
//
// Regenerate after editing (outputs are checked in; never hand-edit them):
//   dart run pigeon --input pigeons/messages.dart
//   dart format lib/src/messages.g.dart
// CI regenerates and fails on any diff.
//
// Naming: every type here carries a `Platform` prefix — including enums that
// the public API re-exports via `typedef` (e.g. `MKUserTrackingMode =
// PlatformUserTrackingMode`). The prefix is load-bearing on the Swift side:
// this file generates into `messages.g.swift`, where an enum literally named
// `MKUserTrackingMode` or `CGLineCap` would shadow Apple's real types across
// the plugin module. Keep the prefix for any future addition.
//
// Error-code contract (host -> MapKitPlatformException at the controller):
//   snapshot-failed       — `takeSnapshot` could not produce image data.
//   look-around-failed    — the Look Around scene request or presentation
//                           failed (a missing scene is `false`, not an error).
//   unsupported-platform  — the feature does not exist on this platform
//                           (e.g. `openLookAround` on macOS).
//   duplicate-id          — `addTileOverlay` with an id already on the map.
//   invalid-icon          — undecodable image bytes or an unknown SF Symbol.
//   unavailable-poi-category — a point-of-interest category newer than the
//                           running OS.
//   invalid-argument      — a value MapKit rejects (zoom range, boundary).
// Unknown ids are reported, not ignored: select/deselect/remove return
// whether they found the object. Reads that need a layout return null
// before the first layout.

// Pigeon parses this file with its own bundled analyzer, which does not
// support Dart 3.13 primary-constructor syntax. Keep the class name on
// constructors here or `dart run pigeon` fails to parse the input.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    swiftOut: 'darwin/mapkit_flutter/Sources/mapkit_flutter/messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'MapKitHostError'),
    dartPackageName: 'mapkit_flutter',
  ),
)
// ----------------------------- Enums -----------------------------
enum PlatformMapKind { standard, hybrid, imagery }

/// Label and feature emphasis on the standard map
/// (`MKStandardMapConfiguration.EmphasisStyle`).
///
/// `standard` maps to Apple's `.default` — `default` is a Dart reserved word.
/// See: https://developer.apple.com/documentation/mapkit/mkstandardmapconfiguration/emphasisstyle
enum PlatformMapEmphasisStyle { standard, muted }

/// Flat versus realistic 3-D terrain (`MKMapConfiguration.ElevationStyle`).
/// See: https://developer.apple.com/documentation/mapkit/mkmapconfiguration/elevationstyle
enum PlatformMapElevationStyle { flat, realistic }

/// How the map camera follows the user's location (`MKUserTrackingMode`).
/// See: https://developer.apple.com/documentation/mapkit/mkusertrackingmode
enum PlatformUserTrackingMode { none, follow, followWithHeading }

/// Stroke end-cap style for an `MKPolyline` (`CGLineCap`).
/// See: https://developer.apple.com/documentation/coregraphics/cglinecap
enum PlatformLineCap { butt, round, square }

/// Stroke join style between `MKPolyline` segments (`CGLineJoin`).
/// See: https://developer.apple.com/documentation/coregraphics/cglinejoin
enum PlatformLineJoin { miter, round, bevel }

enum PlatformPOIMode { none, all, including, excluding }

/// Vertical placement of an overlay relative to the base map's own labels and
/// roads (`MKOverlayLevel`).
/// See: https://developer.apple.com/documentation/mapkit/mkoverlaylevel
enum PlatformOverlayLevel {
  /// Drawn above roads but below map labels (POIs, place names). Default.
  aboveRoads,

  /// Drawn above everything, including labels.
  aboveLabels,
}

/// Mirrors `MKPointOfInterestCategory`.
/// See: https://developer.apple.com/documentation/mapkit/mkpointofinterestcategory
enum PlatformPointOfInterestCategory {
  airport,
  amusementPark,
  aquarium,
  atm,
  bakery,
  bank,
  beach,
  brewery,
  cafe,
  campground,
  carRental,
  evCharger,
  fireStation,
  fitnessCenter,
  foodMarket,
  gasStation,
  hospital,
  hotel,
  laundry,
  library,
  marina,
  movieTheater,
  museum,
  nationalPark,
  nightlife,
  park,
  parking,
  pharmacy,
  police,
  postOffice,
  publicTransport,
  restaurant,
  restroom,
  school,
  stadium,
  store,
  theater,
  university,
  winery,
  zoo,

  // iOS 18 / macOS 15. A filter naming one on an older OS fails with
  // `unavailable-poi-category`.
  /// iOS 18 / macOS 15.
  animalService,

  /// iOS 18 / macOS 15.
  automotiveRepair,

  /// iOS 18 / macOS 15.
  baseball,

  /// iOS 18 / macOS 15.
  basketball,

  /// iOS 18 / macOS 15.
  beauty,

  /// iOS 18 / macOS 15.
  bowling,

  /// iOS 18 / macOS 15.
  castle,

  /// iOS 18 / macOS 15.
  conventionCenter,

  /// iOS 18 / macOS 15.
  distillery,

  /// iOS 18 / macOS 15.
  fairground,

  /// iOS 18 / macOS 15.
  fishing,

  /// iOS 18 / macOS 15.
  fortress,

  /// iOS 18 / macOS 15.
  golf,

  /// iOS 18 / macOS 15.
  goKart,

  /// iOS 18 / macOS 15.
  hiking,

  /// iOS 18 / macOS 15.
  kayaking,

  /// iOS 18 / macOS 15.
  landmark,

  /// iOS 18 / macOS 15.
  mailbox,

  /// iOS 18 / macOS 15.
  miniGolf,

  /// iOS 18 / macOS 15.
  musicVenue,

  /// iOS 18 / macOS 15.
  nationalMonument,

  /// iOS 18 / macOS 15.
  planetarium,

  /// iOS 18 / macOS 15.
  rockClimbing,

  /// iOS 18 / macOS 15.
  rvPark,

  /// iOS 18 / macOS 15.
  skatePark,

  /// iOS 18 / macOS 15.
  skating,

  /// iOS 18 / macOS 15.
  skiing,

  /// iOS 18 / macOS 15.
  soccer,

  /// iOS 18 / macOS 15.
  spa,

  /// iOS 18 / macOS 15.
  surfing,

  /// iOS 18 / macOS 15.
  swimming,

  /// iOS 18 / macOS 15.
  tennis,

  /// iOS 18 / macOS 15.
  volleyball,
}

/// Map features the user can select (`MKMapFeatureOptions`).
/// See: https://developer.apple.com/documentation/mapkit/mkmapfeatureoptions
enum PlatformMapFeatureOptions {
  pointsOfInterest,
  territories,
  physicalFeatures,
}

enum PlatformAnnotationIconType { marker, image }

/// MKMapFeatureAnnotation.FeatureType.
enum PlatformMapFeatureType { pointOfInterest, territory, physicalFeature }

// ----------------------------- Data classes -----------------------------

class PlatformCoordinate {
  PlatformCoordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class PlatformCoordinateSpan {
  PlatformCoordinateSpan({
    required this.latitudeDelta,
    required this.longitudeDelta,
  });

  final double latitudeDelta;
  final double longitudeDelta;
}

class PlatformCoordinateRegion {
  PlatformCoordinateRegion({required this.center, required this.span});

  final PlatformCoordinate center;
  final PlatformCoordinateSpan span;
}

/// Mirrors `MKMapCamera`: [distance] is `centerCoordinateDistance` in meters.
class PlatformMapCamera {
  PlatformMapCamera({
    required this.centerCoordinate,
    required this.distance,
    required this.heading,
    required this.pitch,
  });

  final PlatformCoordinate centerCoordinate;
  final double distance;
  final double heading;
  final double pitch;
}

class PlatformPoint {
  PlatformPoint({required this.x, required this.y});

  final double x;
  final double y;
}

/// Discriminated union of the `MKAnnotationIcon` variants. Only the fields
/// relevant to [type] are non-null.
class PlatformAnnotationIcon {
  PlatformAnnotationIcon({
    required this.type,
    this.markerTintArgb,
    this.glyphText,
    this.glyphSystemImage,
    this.glyphTintArgb,
    this.imageBytes,
    this.imagePixelRatio,
  });

  final PlatformAnnotationIconType type;

  /// `MKMarkerAnnotationView.markerTintColor` (ARGB) for the `marker` variant.
  final int? markerTintArgb;

  /// `MKMarkerAnnotationView.glyphText` for the `marker` variant.
  final String? glyphText;

  /// SF Symbol name for `MKMarkerAnnotationView.glyphImage`.
  final String? glyphSystemImage;

  /// `MKMarkerAnnotationView.glyphTintColor` (ARGB).
  final int? glyphTintArgb;

  /// Raw PNG bytes for the `image` variant (`MKAnnotationView.image`).
  final Uint8List? imageBytes;

  /// Pixels per logical point in [imageBytes] (`UIImage(data:scale:)`).
  final double? imagePixelRatio;
}

class PlatformAnnotation {
  PlatformAnnotation({
    required this.id,
    required this.coordinate,
    required this.icon,
    required this.calloutConsumesTapEvents,
    required this.alpha,
    required this.anchorPointX,
    required this.anchorPointY,
    required this.isDraggable,
    required this.isHidden,
    required this.zPriority,
    this.title,
    this.subtitle,
    this.clusteringIdentifier,
  });

  final String id;
  final PlatformCoordinate coordinate;
  final PlatformAnnotationIcon icon;
  final String? title;
  final String? subtitle;
  final bool calloutConsumesTapEvents;
  final double alpha;
  final double anchorPointX;
  final double anchorPointY;
  final bool isDraggable;
  final bool isHidden;
  final double zPriority;
  final String? clusteringIdentifier;
}

class PlatformPolyline {
  PlatformPolyline({
    required this.id,
    required this.coordinates,
    required this.strokeColorArgb,
    required this.lineWidth,
    required this.lineCap,
    required this.lineJoin,
    required this.isHidden,
    required this.consumeTapEvents,
    required this.isGeodesic,
    required this.level,
    required this.zIndex,
    this.lineDashPattern,
    this.gradientColorsArgb,
  });

  final String id;
  final List<PlatformCoordinate> coordinates;
  final int strokeColorArgb;
  final double lineWidth;
  final PlatformLineCap lineCap;
  final PlatformLineJoin lineJoin;
  final bool isHidden;
  final bool consumeTapEvents;
  final bool isGeodesic;
  final PlatformOverlayLevel level;
  final int zIndex;

  /// Alternating dash/gap lengths in points (`lineDashPattern`).
  final List<double>? lineDashPattern;

  /// When non-empty, renders with `MKGradientPolylineRenderer` spreading these
  /// ARGB colors evenly across the line.
  final List<int>? gradientColorsArgb;
}

class PlatformPolygon {
  PlatformPolygon({
    required this.id,
    required this.coordinates,
    required this.interiorPolygons,
    required this.fillColorArgb,
    required this.strokeColorArgb,
    required this.lineWidth,
    required this.zIndex,
    required this.isHidden,
    required this.consumeTapEvents,
    required this.level,
  });

  final String id;
  final List<PlatformCoordinate> coordinates;
  final List<List<PlatformCoordinate>> interiorPolygons;
  final int fillColorArgb;
  final int strokeColorArgb;
  final double lineWidth;
  final int zIndex;
  final bool isHidden;
  final bool consumeTapEvents;
  final PlatformOverlayLevel level;
}

class PlatformCircle {
  PlatformCircle({
    required this.id,
    required this.center,
    required this.radius,
    required this.fillColorArgb,
    required this.strokeColorArgb,
    required this.lineWidth,
    required this.zIndex,
    required this.isHidden,
    required this.consumeTapEvents,
    required this.level,
  });

  final String id;
  final PlatformCoordinate center;
  final double radius;
  final int fillColorArgb;
  final int strokeColorArgb;
  final double lineWidth;
  final int zIndex;
  final bool isHidden;
  final bool consumeTapEvents;
  final PlatformOverlayLevel level;
}

class PlatformTileOverlay {
  PlatformTileOverlay({
    required this.id,
    required this.urlTemplate,
    required this.minimumZ,
    required this.maximumZ,
    required this.tileSize,
    required this.canReplaceMapContent,
    required this.alpha,
    required this.level,
  });

  final String id;
  final String urlTemplate;
  final int minimumZ;
  final int maximumZ;
  final int tileSize;
  final bool canReplaceMapContent;
  final double alpha;
  final PlatformOverlayLevel level;
}

class PlatformPointOfInterestFilter {
  PlatformPointOfInterestFilter({required this.mode, required this.categories});

  final PlatformPOIMode mode;

  /// Only meaningful for [PlatformPOIMode.including] /
  /// [PlatformPOIMode.excluding].
  final List<PlatformPointOfInterestCategory> categories;
}

/// Mirrors `MKMapView.CameraZoomRange` — distances in meters.
class PlatformCameraZoomRange {
  PlatformCameraZoomRange({
    this.minCenterCoordinateDistance,
    this.maxCenterCoordinateDistance,
  });

  final double? minCenterCoordinateDistance;
  final double? maxCenterCoordinateDistance;
}

class PlatformMapConfiguration {
  PlatformMapConfiguration({
    required this.kind,
    required this.emphasisStyle,
    required this.elevationStyle,
    required this.showsTraffic,
    required this.showsCompass,
    required this.showsScale,
    required this.showsUserLocation,
    required this.showsUserTrackingButton,
    required this.userTrackingMode,
    required this.viewRespectsSystemMinimumLayoutMargins,
    required this.insetsLayoutMarginsFromSafeArea,
    required this.layoutMargins,
    required this.isRotateEnabled,
    required this.isScrollEnabled,
    required this.isZoomEnabled,
    required this.isPitchEnabled,
    required this.selectableMapFeatures,
    this.pointOfInterestFilter,
    this.cameraZoomRange,
    this.cameraBoundary,
  });

  final PlatformMapKind kind;
  final PlatformMapEmphasisStyle emphasisStyle;
  final PlatformMapElevationStyle elevationStyle;
  final bool showsTraffic;
  final bool showsCompass;
  final bool showsScale;
  final bool showsUserLocation;
  final bool showsUserTrackingButton;
  final PlatformUserTrackingMode userTrackingMode;
  final bool viewRespectsSystemMinimumLayoutMargins;
  final bool insetsLayoutMarginsFromSafeArea;
  final List<double?>? layoutMargins;
  final bool isRotateEnabled;
  final bool isScrollEnabled;
  final bool isZoomEnabled;
  final bool isPitchEnabled;
  final List<PlatformMapFeatureOptions> selectableMapFeatures;
  final PlatformPointOfInterestFilter? pointOfInterestFilter;
  final PlatformCameraZoomRange? cameraZoomRange;
  final PlatformCoordinateRegion? cameraBoundary;
}

/// Mirrors `MKMapSnapshotter.Options` plus plugin-drawn annotation/overlay
/// toggles.
class PlatformSnapshotOptions {
  PlatformSnapshotOptions({
    required this.showsPointsOfInterest,
    required this.showsAnnotations,
    required this.showsOverlays,
  });

  final bool showsPointsOfInterest;
  final bool showsAnnotations;
  final bool showsOverlays;
}

class PlatformMapViewCreationParams {
  PlatformMapViewCreationParams({
    required this.initialCamera,
    required this.configuration,
    required this.annotations,
    required this.polylines,
    required this.polygons,
    required this.circles,
  });

  final PlatformMapCamera initialCamera;
  final PlatformMapConfiguration configuration;
  final List<PlatformAnnotation> annotations;
  final List<PlatformPolyline> polylines;
  final List<PlatformPolygon> polygons;
  final List<PlatformCircle> circles;
}

/// A selected map feature (`MKMapFeatureAnnotation`).
class PlatformMapFeature {
  PlatformMapFeature({
    required this.featureType,
    required this.coordinate,
    this.title,
    this.pointOfInterestCategory,
  });

  final PlatformMapFeatureType featureType;
  final PlatformCoordinate coordinate;
  final String? title;
  final PlatformPointOfInterestCategory? pointOfInterestCategory;
}

// ----------------------------- APIs -----------------------------

/// Flutter -> host. One instance per platform view, keyed by the view id via
/// Pigeon's `messageChannelSuffix`.
@HostApi()
abstract class MapKitHostApi {
  /// Pushes the full initial state immediately after the platform view is
  /// created.
  void initialize(PlatformMapViewCreationParams params);

  // Pigeon API methods don't support named parameters, so the `animated`
  // bools below must stay positional.
  // ignore_for_file: avoid_positional_boolean_parameters

  /// `MKMapView.setCamera(_:animated:)`.
  void setCamera(PlatformMapCamera camera, bool animated);

  /// `MKMapView.setRegion(_:animated:)`.
  void setRegion(PlatformCoordinateRegion region, bool animated);

  /// `MKMapView.setCenter(_:animated:)`.
  void setCenter(PlatformCoordinate coordinate, bool animated);

  /// `MKMapView.camera`; null before the first layout.
  PlatformMapCamera? getCamera();

  /// `MKMapView.region`; null before the first layout.
  PlatformCoordinateRegion? getRegion();

  /// `MKMapView.convert(_:toPointTo:)`.
  PlatformPoint? convertToPoint(PlatformCoordinate coordinate);

  /// `MKMapView.convert(_:toCoordinateFrom:)`.
  PlatformCoordinate? convertToCoordinate(PlatformPoint point);

  void updateAnnotations(
    List<PlatformAnnotation> toAdd,
    List<PlatformAnnotation> toChange,
    List<String> idsToRemove,
  );
  void updatePolylines(
    List<PlatformPolyline> toAdd,
    List<PlatformPolyline> toChange,
    List<String> idsToRemove,
  );
  void updatePolygons(
    List<PlatformPolygon> toAdd,
    List<PlatformPolygon> toChange,
    List<String> idsToRemove,
  );
  void updateCircles(
    List<PlatformCircle> toAdd,
    List<PlatformCircle> toChange,
    List<String> idsToRemove,
  );

  void updateMapConfiguration(PlatformMapConfiguration configuration);

  /// `MKMapView.selectAnnotation(_:animated:)`; false when the id is not on
  /// the map or the annotation is hidden.
  bool selectAnnotation(String annotationId);

  /// `MKMapView.deselectAnnotation(_:animated:)`; false when the id is not on
  /// the map.
  bool deselectAnnotation(String annotationId);

  bool isAnnotationSelected(String annotationId);

  /// Throws: `snapshot-failed`.
  // @asyncCallback, not @async: pigeon's async-throws host handlers capture the non-Sendable api/reply in a Task, which Swift 6 rejects.
  @asyncCallback
  Uint8List takeSnapshot(PlatformSnapshotOptions options);

  /// False when no scene exists. Throws: `look-around-failed`,
  /// `unsupported-platform` (macOS).
  // @asyncCallback, not @async: pigeon's async-throws host handlers capture the non-Sendable api/reply in a Task, which Swift 6 rejects.
  @asyncCallback
  bool openLookAround(PlatformCoordinate coordinate);

  /// Throws: `duplicate-id`.
  void addTileOverlay(PlatformTileOverlay overlay);

  /// False when no tile overlay with this id is on the map.
  bool removeTileOverlay(String tileOverlayId);

  /// Tears down the native view: removes this host's channel handlers,
  /// detaches the map delegate, stops location updates.
  void dispose();
}

/// Host -> Flutter. One instance per platform view, keyed by view id.
@FlutterApi()
abstract class MapKitFlutterApi {
  void onCameraMoveStarted();
  void onCameraMove(PlatformMapCamera camera);
  void onCameraIdle();

  /// `MKMapViewDelegate.mapView(_:didChange:animated:)` — e.g. MapKit drops
  /// to `none` when the user pans.
  void onUserTrackingModeChanged(PlatformUserTrackingMode mode);

  /// `MKMapViewDelegate.mapView(_:didSelect:)` for a Flutter annotation.
  void onAnnotationSelect(String annotationId);

  /// `MKMapViewDelegate.mapView(_:didDeselect:)` for a Flutter annotation.
  void onAnnotationDeselect(String annotationId);

  /// A selected `MKMapFeatureAnnotation` (iOS).
  void onMapFeatureSelected(PlatformMapFeature feature);

  void onAnnotationDragStart(
    String annotationId,
    PlatformCoordinate coordinate,
  );
  void onAnnotationDragEnd(String annotationId, PlatformCoordinate coordinate);
  void onCalloutTap(String annotationId);
  void onPolylineTap(String polylineId);
  void onPolygonTap(String polygonId);
  void onCircleTap(String circleId);
  void onMapTap(PlatformCoordinate coordinate);
  void onMapLongPress(PlatformCoordinate coordinate);

  /// `MKMapViewDelegate.mapViewDidFailLoadingMap(_:withError:)`.
  void onDidFailLoadingMap(String error);

  /// `MKMapViewDelegate.mapView(_:didFailToLocateUserWithError:)`.
  void onDidFailToLocateUser(String error);
}
