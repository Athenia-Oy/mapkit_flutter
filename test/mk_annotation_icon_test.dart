import 'dart:ui' show PlatformDispatcher;

import 'package:checks/checks.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

void main() {
  group('MKAnnotationIcon.marker', () {
    test('plain marker serializes with no styling', () {
      final platform = const MKAnnotationIcon.marker().toPlatform();
      check(platform.type).equals(.marker);
      check(platform.markerTintArgb).isNull();
      check(platform.glyphText).isNull();
      check(platform.glyphSystemImage).isNull();
      check(platform.glyphTintArgb).isNull();
      check(platform.imageBytes).isNull();
      check(platform.imagePixelRatio).isNull();
    });

    test('serializes MKMarkerAnnotationView styling as ARGB32', () {
      final platform = const MKAnnotationIcon.marker(
        markerTintColor: .new(0xFF112233),
        glyphText: 'HQ',
        systemImage: 'star.fill',
        glyphTintColor: .new(0xFFFFFFFF),
      ).toPlatform();
      check(platform.markerTintArgb).equals(0xFF112233);
      check(platform.glyphText).equals('HQ');
      check(platform.glyphSystemImage).equals('star.fill');
      check(platform.glyphTintArgb).equals(0xFFFFFFFF);
      check(platform.imageBytes).isNull();
    });
  });

  group('MKAnnotationIcon.image', () {
    test('serializes raw bytes', () {
      final png = Uint8List.fromList([1, 2, 3]);
      final platform = MKAnnotationIcon.image(png).toPlatform();
      check(platform.type).equals(.image);
      check(platform.imageBytes).isNotNull().deepEquals(png);
      check(platform.markerTintArgb).isNull();
    });

    test('serializes explicit imagePixelRatio', () {
      final platform = MKAnnotationIcon.image(
        .fromList([1]),
        imagePixelRatio: 2.5,
      ).toPlatform();
      check(platform.imagePixelRatio).equals(2.5);
    });

    test('rejects an imagePixelRatio that is not finite and > 0', () {
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        check(
          because: 'imagePixelRatio $bad',
          () => MKAnnotationIcon.image(.fromList([1]), imagePixelRatio: bad),
        ).throws<ArgumentError>();
      }
    });

    test('imagePixelRatio defaults to the implicit view ratio', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final platform = MKAnnotationIcon.image(.fromList([1])).toPlatform();
      check(platform.imagePixelRatio)
          .equals(PlatformDispatcher.instance.implicitView?.devicePixelRatio);
    });
  });

  group('MKAnnotationIcon.asset', () {
    test('loads from key.bundle and slices ByteData view bounds', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final backing = Uint8List.fromList([99, 10, 20, 30, 88]);
      final sliced = ByteData.sublistView(backing, 1, 4);
      final bundle = _FakeAssetBundle({'packages/demo/pin.png': sliced});

      final icon = await MKAnnotationIcon.asset(
        'pin.png',
        bundle: bundle,
        package: 'demo',
      );
      final platform = icon.toPlatform();
      check(platform.imageBytes).isNotNull().deepEquals([10, 20, 30]);
      check(platform.imagePixelRatio).equals(1);
    });
  });

  group('equality', () {
    test('markers compare by full styling', () {
      const tinted = MKAnnotationIcon.marker(markerTintColor: .new(0xFF112233));
      check(tinted).equals(tinted);
      check(tinted == const .marker()).isFalse();
    });

    test('images compare by byte content', () {
      final a = MKAnnotationIcon.image(.fromList([1, 2]));
      final b = MKAnnotationIcon.image(.fromList([1, 2]));
      final c = MKAnnotationIcon.image(.fromList([9]));
      check(a).equals(b);
      check(a.hashCode).equals(b.hashCode);
      check(a == c).isFalse();
    });

    test('images with different pixel ratios never compare equal', () {
      final bytes = Uint8List.fromList([1, 2]);
      final a = MKAnnotationIcon.image(bytes, imagePixelRatio: 2);
      final b = MKAnnotationIcon.image(bytes, imagePixelRatio: 3);
      check(a == b).isFalse();
      check(a).equals(.image(bytes, imagePixelRatio: 2));
    });

    test('marker and image never compare equal', () {
      check(const MKAnnotationIcon.marker() == .image(.new(0))).isFalse();
    });
  });
}

final class _FakeAssetBundle(final Map<String, ByteData> _assets)
    extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(
            const <String, List<Object>>{},
          ) ??
          .new(0);
    }
    final data = _assets[key];
    if (data == null) {
      throw FlutterError('Unable to load asset: "$key".');
    }
    return data;
  }
}
