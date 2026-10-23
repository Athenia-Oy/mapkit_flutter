import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/src/messages.g.dart';

import 'fake_host_api.dart';

/// A host call or sink event captured by a test fake.
typedef RecordedCall = ({String name, Object? args});

typedef CameraCall = (PlatformMapCamera camera, bool animated);
typedef CoordinateCall = (PlatformCoordinate coordinate, bool animated);
typedef RegionCall = (PlatformCoordinateRegion region, bool animated);
typedef AnnotationUpdate = (
  List<PlatformAnnotation> toAdd,
  List<PlatformAnnotation> toChange,
  List<String> idsToRemove,
);
typedef PolylineUpdate = (
  List<PlatformPolyline> toAdd,
  List<PlatformPolyline> toChange,
  List<String> idsToRemove,
);

/// Unwraps recorded args with an [is] check instead of `! as`.
T requireRecordedArgs<T>(Object? args, {required String call}) {
  if (args is T) return args;
  fail('$call: expected $T, got ${args.runtimeType}: $args');
}

extension FakeHostApiExpectations on FakeHostApi {
  void expectCalls(List<String> names) => check(callNames).deepEquals(names);

  PlatformMapViewCreationParams initializeParams() {
    check(calls.single.$1).equals('initialize');
    return calls.requireSingleArgs();
  }
}

extension FakeHostCallExpectations on List<(String, Object?)> {
  RecordedCall lastRecorded() {
    final (name, args) = last;
    return (name: name, args: args);
  }

  RecordedCall recordedAt(int index) {
    final (name, args) = this[index];
    return (name: name, args: args);
  }

  T requireSingleArgs<T>() {
    final (name, args) = single;
    return requireRecordedArgs(args, call: name);
  }

  T requireLastArgs<T>() {
    final (:name, :args) = lastRecorded();
    return requireRecordedArgs(args, call: name);
  }

  T requireArgsAt<T>(int index) {
    final (:name, :args) = recordedAt(index);
    return requireRecordedArgs(args, call: name);
  }

  T expectLastArgs<T>(String name) {
    check(lastRecorded().name).equals(name);
    return requireLastArgs<T>();
  }
}

extension RecordedSinkEvents on List<(String, Object?)> {
  void expectOnlyEvent(String event) => check(single.$1).equals(event);

  void expectEventNames(List<String> names) =>
      check(map((e) => e.$1).toList()).deepEquals(names);

  T requireLastPayload<T>({required String event}) {
    final (name, payload) = last;
    if (name != event) {
      fail('Expected event "$event", got "$name"');
    }
    return requireRecordedArgs(payload, call: name);
  }

  T requireSinglePayload<T>({required String event}) {
    final (name, payload) = single;
    if (name != event) {
      fail('Expected event "$event", got "$name"');
    }
    return requireRecordedArgs(payload, call: name);
  }
}
