import 'package:meta/meta.dart';

/// Computes the add/change/remove delta between two snapshots of map objects,
/// keyed by a stable string id. Shared by annotations and every overlay type so
/// the diff lives in one place instead of one near-identical class per kind.
@internal
final class MapObjectUpdates<T extends Object> {
  const new _({
    required this.toAdd,
    required this.toChange,
    required this.idsToRemove,
  });

  factory between(
    Set<T> before,
    Set<T> after, {
    required String Function(T) idOf,
  }) {
    final beforeById = {for (final o in before) idOf(o): o};
    final afterById = {for (final o in after) idOf(o): o};

    return ._(
      toAdd: {
        for (final e in afterById.entries)
          if (!beforeById.containsKey(e.key)) e.value,
      },
      toChange: {
        for (final e in afterById.entries)
          if (beforeById[e.key] case final prior? when prior != e.value)
            e.value,
      },
      idsToRemove: {
        for (final id in beforeById.keys)
          if (!afterById.containsKey(id)) id,
      },
    );
  }

  final Set<T> toAdd;
  final Set<T> toChange;
  final Set<String> idsToRemove;

  bool isEmpty() => toAdd.isEmpty && toChange.isEmpty && idsToRemove.isEmpty;
}
