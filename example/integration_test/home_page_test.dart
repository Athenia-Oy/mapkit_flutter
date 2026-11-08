import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mapkit_flutter_example/main.dart';

/// Drives the example's restyle-lab control bar against a live MKMapView so the
/// demo controls (select, tint, glyph, subtitle, zoom, reset, rebuild) are
/// exercised end-to-end. A regression in the in-place update / reuse paths or
/// the example wiring would surface as a thrown exception here.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('restyle-lab controls drive a live map without errors', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    // Let the platform view initialize and the first frame settle (this also
    // runs the startup custom-Flutter-widget marker rasterization).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const .new(milliseconds: 100));
    }
    check(find.text('Tint'), because: 'control bar never built').isNotNull();

    Future<void> tap(Finder finder) async {
      await tester.tap(finder, warnIfMissed: false);
      await tester.pump(const .new(milliseconds: 50));
    }

    // Cycle selection across pins, restyling each in place.
    for (var i = 0; i < _pinCount; i++) {
      await tap(find.text('Tint'));
      await tap(find.text('Glyph'));
      await tap(find.text('Subtitle'));
      await tap(find.text('Next pin'));
    }

    await tap(find.byTooltip('Zoom in'));
    await tap(find.byTooltip('Zoom out'));
    await tap(find.text('Reset'));
    await tap(find.text('Rebuild'));
    await tester.pump(const .new(milliseconds: 500));

    check(tester.takeException()).isNull();
  });
}

const _pinCount = 4;
