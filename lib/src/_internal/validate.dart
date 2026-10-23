import 'package:meta/meta.dart';

/// Throws [ArgumentError] unless [value] is finite.
@internal
void checkFinite(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, name, 'must be finite');
  }
}

/// Throws [ArgumentError] unless [value] lies in `[min, max]`; NaN fails.
@internal
void checkInRange(num value, num min, num max, String name) {
  if (!(value >= min && value <= max)) {
    throw ArgumentError.value(value, name, 'must be in [$min, $max]');
  }
}

/// Throws [ArgumentError] unless [value] is finite and `>= 0`.
@internal
void checkNonNegative(double value, String name) {
  if (!(value >= 0 && value.isFinite)) {
    throw ArgumentError.value(value, name, 'must be a finite value >= 0');
  }
}

/// Throws [ArgumentError] unless [value] is finite and `> 0`.
@internal
void checkPositive(double value, String name) {
  if (!(value > 0 && value.isFinite)) {
    throw ArgumentError.value(value, name, 'must be a finite value > 0');
  }
}

/// Throws [ArgumentError] when [onTap] is set on an overlay that does not
/// capture taps — the callback could never fire.
@internal
void checkTapCallback(Object? onTap, {required bool consumeTapEvents}) {
  if (onTap != null && !consumeTapEvents) {
    throw ArgumentError.value(
      onTap,
      'onTap',
      'requires consumeTapEvents: true',
    );
  }
}
