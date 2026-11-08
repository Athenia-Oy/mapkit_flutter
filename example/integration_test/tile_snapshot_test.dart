import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';

/// `takeSnapshot` end to end, through the channel and `MKTileOverlay.loadTile`:
/// a tile's pixels appear on the snapshot, and a tile that can't load fails it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tile overlays appear in snapshots and fail them loudly', (
    tester,
  ) async {
    const magenta = ui.Color(0xFFFF00FF);
    final tiles = await Directory.systemTemp.createTemp('tiles');
    addTearDown(() => tiles.delete(recursive: true));
    final png = await _solidPng(magenta);
    for (final (x, y) in [(1, 1), (2, 1), (1, 2), (2, 2)]) {
      final file = File('${tiles.path}/2/$x/$y.png');
      await file.create(recursive: true);
      await file.writeAsBytes(png);
    }

    MKMapViewController? controller;
    await tester.pumpWidget(
      MaterialApp(
        home: MKMapView(
          initialCamera: .new(
            centerCoordinate: .new(latitude: 0, longitude: 0),
            distance: 400000,
          ),
          onMapCreated: (c) => controller = c,
        ),
      ),
    );
    final deadline = DateTime.now().add(const .new(seconds: 45));
    MKCoordinateRegion? region;
    while (region == null && DateTime.now().isBefore(deadline)) {
      await tester.pump(const .new(milliseconds: 250));
      region = await controller?.region;
    }
    final map = controller;
    if (map == null || region == null) fail('map never laid out');

    Future<ui.Color> centerOf(Uint8List snapshot) async {
      final codec = await ui.instantiateImageCodec(snapshot);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final bytes = await image.toByteData();
      if (bytes == null) fail('snapshot did not decode');
      final offset = (image.height ~/ 2 * image.width + image.width ~/ 4) * 4;
      final color = ui.Color.fromARGB(
        bytes.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
      image.dispose();
      codec.dispose();
      return color;
    }

    final bare = await centerOf(await map.takeSnapshot());
    check(bare.toARGB32()).not((it) => it.equals(magenta.toARGB32()));

    await map.addTileOverlay(
      .new(
        id: const .new('solid'),
        urlTemplate: 'file://${tiles.path}/{z}/{x}/{y}.png',
        maximumZ: 2,
      ),
    );
    final withTiles = await centerOf(await map.takeSnapshot());
    check(withTiles.toARGB32()).equals(magenta.toARGB32());

    final withoutOverlays = await centerOf(
      await map.takeSnapshot(const .new(showsOverlays: false)),
    );
    check(withoutOverlays.toARGB32())
        .not((it) => it.equals(magenta.toARGB32()));

    await map.removeTileOverlay(const .new('solid'));
    await map.addTileOverlay(
      .new(
        id: const .new('gone'),
        urlTemplate: 'file://${tiles.path}/missing/{z}/{x}/{y}.png',
        maximumZ: 2,
      ),
    );
    final failure = await map.takeSnapshot().then<Object?>(
      (_) => null,
      onError: (Object error) => error,
    );
    check(failure)
        .isA<MapKitPlatformException>()
        .has((e) => e.code, 'code')
        .equals('snapshot-failed');
  });
}

Future<Uint8List> _solidPng(ui.Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(color, .src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  final bytes = await image.toByteData(format: .png);
  picture.dispose();
  image.dispose();
  if (bytes == null) fail('tile did not encode');
  return bytes.buffer.asUint8List();
}
