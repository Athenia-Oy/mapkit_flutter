import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

void main() {
  group('MapKitException.fromPlatform', () {
    test('wraps any code with its diagnostics', () {
      final e = MapKitException.fromPlatform(
        .new(code: 'boom', message: 'kaboom', details: 42),
      );
      check(e).isA<MapKitPlatformException>()
        ..has((p) => p.code, 'code').equals('boom')
        ..has((p) => p.message, 'message').equals('kaboom')
        ..has((p) => p.details, 'details').equals(42)
        ..has((p) => p.toString(), 'toString()').contains('boom');
    });

    test('falls back to a generic message when the platform sends none', () {
      final e = MapKitException.fromPlatform(.new(code: 'x'));
      check(e.message).equals('Platform error');
    });
  });

  group('concrete exceptions', () {
    test('disposed exception names the controller', () {
      final message = const MapKitDisposedException().message;
      check(message).contains('MKMapViewController');
    });

    test('unsupported platform exception carries the platform', () {
      const e = MapKitUnsupportedPlatformException(.android);
      check(e.platform).equals(.android);
      check(e.toString()).contains('android');
    });
  });
}
