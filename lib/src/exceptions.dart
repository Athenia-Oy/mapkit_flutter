import 'package:flutter/foundation.dart' show TargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:meta/meta.dart';

/// Base type for every error surfaced by `mapkit_flutter`.
///
/// Catch this to handle any map failure, or switch on the concrete subtypes
/// for finer control:
///
/// ```dart
/// try {
///   await controller.takeSnapshot();
/// } on MapKitPlatformException catch (e) {
///   // Native failure with a stable code, e.g. 'snapshot-failed'.
/// } on MapKitException {
///   // Anything else (e.g. controller already disposed).
/// }
/// ```
@immutable
sealed class const MapKitException(
  /// Human-readable description of what went wrong.
  final String message,
) implements Exception {
  /// Creates a [MapKitException] with [message].
  this;

  /// Wraps a raw [PlatformException] from the platform channel into a
  /// [MapKitException].
  @internal
  factory fromPlatform(PlatformException e) => MapKitPlatformException(
    code: e.code,
    message: e.message ?? 'Platform error',
    details: e.details,
  );

  @override
  String toString() => 'MapKitException: $message';
}

/// Thrown when a method is called on a controller whose map view has already
/// been disposed.
final class MapKitDisposedException extends MapKitException {
  /// Creates an exception for a disposed controller.
  const new() : super('The MKMapViewController has been disposed.');
}

/// Thrown when an `MKMapView` is built on a non-Apple platform (anything other
/// than iOS or macOS, including the web on an Apple device), or when it is
/// configured with an iOS-only [feature] on macOS. `mapkit_flutter` wraps
/// Apple's MapKit, so there is no fallback — this surfaces loudly instead of
/// silently rendering an empty box or ignoring the setting.
final class const MapKitUnsupportedPlatformException(
  /// The platform the widget was built on.
  final TargetPlatform platform, {

  /// The setting that has no effect on [platform], or `null` when
  /// `MKMapView` cannot render on [platform] at all.
  final String? feature,
}) extends MapKitException {
  /// Creates an exception for an unsupported [platform], optionally naming
  /// the unsupported [feature].
  this
    : super(
        feature == null
            ? 'mapkit_flutter supports iOS and macOS only; '
                  'MKMapView cannot render here.'
            : '$feature is iOS only and has no effect here.',
      );

  @override
  String toString() => switch (feature) {
    null =>
      'MapKitUnsupportedPlatformException: '
          'mapkit_flutter supports iOS and macOS only and '
          'cannot render on ${kIsWeb ? 'the web' : platform}.',
    final feature =>
      'MapKitUnsupportedPlatformException: $feature is iOS only and has no '
          'effect on $platform.',
  };
}

/// A failure reported by the native MapKit layer. Carries the original
/// platform [code] and [details] for diagnostics.
final class const MapKitPlatformException({
  /// The platform error code (from the Swift side).
  required final String code,
  required String message,

  /// Optional structured details from the platform.
  final Object? details,
}) extends MapKitException {
  /// Creates a platform exception with [code], [message], and [details].
  this : super(message);

  @override
  String toString() => 'MapKitPlatformException($code): $message';
}
