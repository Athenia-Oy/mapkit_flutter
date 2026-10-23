import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'package:mapkit_flutter/src/_internal/copy_with_keep.dart';
import 'package:mapkit_flutter/src/_internal/validate.dart';
import 'package:mapkit_flutter/src/cl_location_coordinate_2d.dart';
import 'package:mapkit_flutter/src/map_item_id.dart';
import 'package:mapkit_flutter/src/messages.g.dart';
import 'package:mapkit_flutter/src/mk_annotation_icon.dart';

/// Typed identifier for an [MKPointAnnotation].
typedef MKAnnotationId = MapItemId<MKPointAnnotation>;

/// A pin or custom marker at a geographical [coordinate], mirroring
/// `MKPointAnnotation` ([coordinate], [title], [subtitle]) with its
/// `MKAnnotationView` presentation merged in ([icon], [alpha], [isDraggable],
/// [zPriority]…) — Flutter is declarative, so there is no separate view
/// object to configure.
/// See: https://developer.apple.com/documentation/mapkit/mkpointannotation
@immutable
final class MKPointAnnotation({
  /// Unique identifier used to diff this annotation across rebuilds.
  required final MKAnnotationId id,

  /// Geographical position of the annotation.
  required final CLLocationCoordinate2D coordinate,

  /// Visual appearance of the annotation view.
  final MKAnnotationIcon icon = const .marker(),

  /// Callout title (`MKAnnotation.title`). A non-null title enables the
  /// callout bubble on tap.
  final String? title,

  /// Callout subtitle (`MKAnnotation.subtitle`).
  final String? subtitle,

  /// View opacity in `[0, 1]`.
  final double alpha = 1.0,

  /// Normalized anchor within the icon image (`MKAnnotationView.anchorPoint`
  /// on iOS, the equivalent `centerOffset` on macOS): `(0.5, 1)` pins the
  /// bottom-center to [coordinate]. Applies to [MKAnnotationIcon.image]
  /// icons; system markers anchor themselves.
  final Offset anchorPoint = const .new(0.5, 1),

  /// Whether the user can drag the annotation
  /// (`MKAnnotationView.isDraggable`).
  final bool isDraggable = false,

  /// Whether the annotation view is hidden on the map.
  final bool isHidden = false,

  /// Display priority for overlap stacking
  /// (`MKAnnotationView.zPriority`); MapKit's default is 500
  /// (`.defaultUnselected`), higher floats above.
  final double zPriority = 500,

  /// Annotations sharing the same `clusteringIdentifier` cluster together
  /// when they're close on screen (`MKAnnotationView.clusteringIdentifier`).
  /// `null` means the annotation never clusters.
  final String? clusteringIdentifier,

  /// Whether taps on the callout bubble are captured and reported to
  /// [onCalloutTap]. iOS only: `MKMapView` throws a
  /// `MapKitUnsupportedPlatformException` for `true` on macOS, which shows
  /// MapKit's default callout.
  final bool calloutConsumesTapEvents = false,

  /// Called when the callout bubble is tapped; requires
  /// [calloutConsumesTapEvents]. iOS only.
  final VoidCallback? onCalloutTap,

  /// Called with the starting coordinate when a drag begins.
  final ValueChanged<CLLocationCoordinate2D>? onDragStart,

  /// Called with the final coordinate when a drag ends.
  final ValueChanged<CLLocationCoordinate2D>? onDragEnd,

  /// `mapView(_:didSelect:)` — the user tapped the annotation, or
  /// `MKMapViewController.selectAnnotation` selected it.
  final VoidCallback? onSelect,

  /// `mapView(_:didDeselect:)`.
  final VoidCallback? onDeselect,
}) {
  /// Creates a point annotation at [coordinate].
  ///
  /// Throws [ArgumentError] when [alpha] is outside `[0, 1]`, or when
  /// [onCalloutTap] is set without [calloutConsumesTapEvents] (it would never
  /// fire).
  this {
    checkInRange(alpha, 0, 1, 'alpha');
    if (onCalloutTap != null && !calloutConsumesTapEvents) {
      throw ArgumentError.value(
        onCalloutTap,
        'onCalloutTap',
        'requires calloutConsumesTapEvents: true',
      );
    }
  }

  /// Returns a copy with the given fields replaced.
  MKPointAnnotation copyWith({
    CLLocationCoordinate2D? coordinate,
    MKAnnotationIcon? icon,
    String? title = keepString,
    String? subtitle = keepString,
    double? alpha,
    Offset? anchorPoint,
    bool? isDraggable,
    bool? isHidden,
    double? zPriority,
    String? clusteringIdentifier = keepString,
    bool? calloutConsumesTapEvents,
    VoidCallback? onCalloutTap = keepCallback,
    ValueChanged<CLLocationCoordinate2D>? onDragStart = keepCoordinateCallback,
    ValueChanged<CLLocationCoordinate2D>? onDragEnd = keepCoordinateCallback,
    VoidCallback? onSelect = keepCallback,
    VoidCallback? onDeselect = keepCallback,
  }) => .new(
    id: id,
    coordinate: coordinate ?? this.coordinate,
    icon: icon ?? this.icon,
    title: identical(title, keepString) ? this.title : title,
    subtitle: identical(subtitle, keepString) ? this.subtitle : subtitle,
    alpha: alpha ?? this.alpha,
    anchorPoint: anchorPoint ?? this.anchorPoint,
    isDraggable: isDraggable ?? this.isDraggable,
    isHidden: isHidden ?? this.isHidden,
    zPriority: zPriority ?? this.zPriority,
    clusteringIdentifier: identical(clusteringIdentifier, keepString)
        ? this.clusteringIdentifier
        : clusteringIdentifier,
    calloutConsumesTapEvents:
        calloutConsumesTapEvents ?? this.calloutConsumesTapEvents,
    onCalloutTap: identical(onCalloutTap, keepCallback)
        ? this.onCalloutTap
        : onCalloutTap,
    onDragStart: identical(onDragStart, keepCoordinateCallback)
        ? this.onDragStart
        : onDragStart,
    onDragEnd: identical(onDragEnd, keepCoordinateCallback)
        ? this.onDragEnd
        : onDragEnd,
    onSelect: identical(onSelect, keepCallback) ? this.onSelect : onSelect,
    onDeselect: identical(onDeselect, keepCallback)
        ? this.onDeselect
        : onDeselect,
  );

  /// Converts this annotation to its Pigeon wire representation.
  @internal
  PlatformAnnotation toPlatform() => .new(
    id: id.value,
    coordinate: coordinate.toPlatform(),
    icon: icon.toPlatform(),
    title: title,
    subtitle: subtitle,
    calloutConsumesTapEvents: calloutConsumesTapEvents,
    alpha: alpha,
    anchorPointX: anchorPoint.dx,
    anchorPointY: anchorPoint.dy,
    isDraggable: isDraggable,
    isHidden: isHidden,
    zPriority: zPriority,
    clusteringIdentifier: clusteringIdentifier,
  );

  @override
  bool operator ==(Object other) =>
      other is MKPointAnnotation &&
      other.id == id &&
      other.coordinate == coordinate &&
      other.icon == icon &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.alpha == alpha &&
      other.anchorPoint == anchorPoint &&
      other.isDraggable == isDraggable &&
      other.isHidden == isHidden &&
      other.zPriority == zPriority &&
      other.clusteringIdentifier == clusteringIdentifier &&
      other.calloutConsumesTapEvents == calloutConsumesTapEvents;

  @override
  int get hashCode => Object.hash(
    id,
    coordinate,
    icon,
    title,
    subtitle,
    alpha,
    anchorPoint,
    isDraggable,
    isHidden,
    zPriority,
    clusteringIdentifier,
    calloutConsumesTapEvents,
  );

  @override
  String toString() {
    final b = StringBuffer('MKPointAnnotation(')
      ..write('id: ${id.value}, ')
      ..write('coordinate: $coordinate, ')
      ..write('title: $title, ')
      ..write('isHidden: $isHidden, ')
      ..write('isDraggable: $isDraggable, ')
      ..write('onSelect: ${onSelect != null ? 'set' : 'null'}');
    return (b..write(')')).toString();
  }
}
