import 'package:flutter/foundation.dart';
import 'package:mapkit_flutter/src/messages.g.dart';
import 'package:meta/meta.dart';

/// What a map snapshot includes, mirroring `MKMapSnapshotter.Options`
/// ([showsPointsOfInterest]) plus toggles for the plugin-drawn
/// [showsAnnotations] and [showsOverlays]. Buildings follow the map's
/// configuration.
/// See: https://developer.apple.com/documentation/mapkit/mkmapsnapshotter/options
@immutable
final class const MKMapSnapshotOptions({
  /// Whether points of interest appear in the snapshot.
  final bool showsPointsOfInterest = true,

  /// Whether the plugin draws the current annotations into the snapshot.
  final bool showsAnnotations = true,

  /// Whether the plugin draws the current overlays into the snapshot, tile
  /// overlays included: their visible tiles are fetched with
  /// `MKTileOverlay.loadTile`, and one that fails fails the snapshot.
  final bool showsOverlays = true,
}) {
  /// Creates options controlling what a map snapshot includes.
  this;

  /// Converts these snapshot options to their Pigeon wire representation.
  @internal
  PlatformSnapshotOptions toPlatform() => .new(
    showsPointsOfInterest: showsPointsOfInterest,
    showsAnnotations: showsAnnotations,
    showsOverlays: showsOverlays,
  );

  @override
  bool operator ==(Object other) =>
      other is MKMapSnapshotOptions &&
      other.showsPointsOfInterest == showsPointsOfInterest &&
      other.showsAnnotations == showsAnnotations &&
      other.showsOverlays == showsOverlays;

  @override
  int get hashCode =>
      Object.hash(showsPointsOfInterest, showsAnnotations, showsOverlays);

  @override
  String toString() =>
      'MKMapSnapshotOptions('
      'showsPointsOfInterest: $showsPointsOfInterest, '
      'showsAnnotations: $showsAnnotations, showsOverlays: $showsOverlays)';
}
