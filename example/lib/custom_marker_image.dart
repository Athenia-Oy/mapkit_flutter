import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart' show MKAnnotationIcon;

/// Paints a simple ringed circle to PNG bytes for [MKAnnotationIcon.image],
/// keeping the example self-contained (no bundled image assets). The bytes
/// feed the custom-image annotation variant so the demo also exercises the
/// reuse/update paths the 0.2.2 fix repairs for `MKAnnotationView.image`.
Future<Uint8List> renderCircleMarkerPng(Color color, {int size = 96}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final d = size.toDouble();
  final center = Offset(d / 2, d / 2);
  const white = Color(0xFFFFFFFF);

  canvas
    ..drawCircle(center, d / 2, .new()..color = color)
    ..drawCircle(
      center,
      d / 2 - d * 0.06,
      .new()
        ..style = .stroke
        ..strokeWidth = d * 0.08
        ..color = white,
    )
    ..drawCircle(center, d * 0.18, .new()..color = white);

  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: .png);
  image.dispose();
  if (data == null) {
    throw StateError('Failed to encode circle marker image to PNG');
  }
  return .sublistView(data);
}
