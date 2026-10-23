import 'package:flutter/foundation.dart';
import 'package:mapkit_flutter/src/messages.g.dart';
import 'package:mapkit_flutter/src/mk_enums.dart';

/// Which points of interest (shops, transit, parks…) the base map labels,
/// mirroring `MKPointOfInterestFilter`: [includingAll], [excludingAll],
/// [MKPointOfInterestFilter.including], or [MKPointOfInterestFilter.excluding].
/// See: https://developer.apple.com/documentation/mapkit/mkpointofinterestfilter
@immutable
sealed class MKPointOfInterestFilter {
  const new();

  /// Shows only the listed [categories].
  factory including(List<MKPointOfInterestCategory> categories) =
      IncludingPointsOfInterest;

  /// Shows every category except the listed [categories].
  factory excluding(List<MKPointOfInterestCategory> categories) =
      ExcludingPointsOfInterest;

  /// Shows every point-of-interest category.
  static const MKPointOfInterestFilter includingAll =
      IncludingAllPointsOfInterest();

  /// Hides all points of interest.
  static const MKPointOfInterestFilter excludingAll =
      ExcludingAllPointsOfInterest();

  /// Converts this filter to its Pigeon wire representation.
  @internal
  PlatformPointOfInterestFilter toPlatform();
}

/// Shows every point-of-interest category
/// ([MKPointOfInterestFilter.includingAll]).
final class IncludingAllPointsOfInterest extends MKPointOfInterestFilter {
  /// Creates a filter that includes every point-of-interest category.
  const new();

  @override
  PlatformPointOfInterestFilter toPlatform() =>
      .new(mode: .all, categories: const []);

  @override
  bool operator ==(Object other) => other is IncludingAllPointsOfInterest;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'MKPointOfInterestFilter.includingAll';
}

/// Hides all points of interest ([MKPointOfInterestFilter.excludingAll]).
final class ExcludingAllPointsOfInterest extends MKPointOfInterestFilter {
  /// Creates a filter that excludes every point-of-interest category.
  const new();

  @override
  PlatformPointOfInterestFilter toPlatform() =>
      .new(mode: .none, categories: const []);

  @override
  bool operator ==(Object other) => other is ExcludingAllPointsOfInterest;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'MKPointOfInterestFilter.excludingAll';
}

/// Shows only the listed [categories].
final class IncludingPointsOfInterest extends MKPointOfInterestFilter {
  /// Creates a filter that includes only [categories].
  new(List<MKPointOfInterestCategory> categories)
    : categories = .unmodifiable(categories);

  /// Categories included by this filter.
  final List<MKPointOfInterestCategory> categories;

  @override
  PlatformPointOfInterestFilter toPlatform() =>
      .new(mode: .including, categories: categories);

  @override
  bool operator ==(Object other) =>
      other is IncludingPointsOfInterest &&
      listEquals(other.categories, categories);

  @override
  int get hashCode => Object.hash('including', .hashAll(categories));

  @override
  String toString() => 'MKPointOfInterestFilter.including($categories)';
}

/// Shows every category except the listed [categories].
final class ExcludingPointsOfInterest extends MKPointOfInterestFilter {
  /// Creates a filter that excludes [categories].
  new(List<MKPointOfInterestCategory> categories)
    : categories = .unmodifiable(categories);

  /// Categories excluded by this filter.
  final List<MKPointOfInterestCategory> categories;

  @override
  PlatformPointOfInterestFilter toPlatform() =>
      .new(mode: .excluding, categories: categories);

  @override
  bool operator ==(Object other) =>
      other is ExcludingPointsOfInterest &&
      listEquals(other.categories, categories);

  @override
  int get hashCode => Object.hash('excluding', .hashAll(categories));

  @override
  String toString() => 'MKPointOfInterestFilter.excluding($categories)';
}
