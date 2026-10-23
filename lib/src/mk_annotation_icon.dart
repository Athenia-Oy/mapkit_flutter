import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'package:mapkit_flutter/src/_internal/validate.dart';
import 'package:mapkit_flutter/src/messages.g.dart';

/// What an annotation looks like, mirroring the `MKMarkerAnnotationView` /
/// `MKAnnotationView` split: [MKAnnotationIcon.marker] is the system balloon
/// marker with optional `markerTintColor` / glyph branding, and
/// [MKAnnotationIcon.image] supplies fully custom imagery
/// (`MKAnnotationView.image`).
/// See: https://developer.apple.com/documentation/mapkit/mkmarkerannotationview
@immutable
final class MKAnnotationIcon {
  /// System balloon marker (`MKMarkerAnnotationView`).
  ///
  /// All-default renders the plain red marker. `markerTintColor` tints the
  /// balloon; brand the glyph with a short `glyphText` label or an SF Symbol
  /// via [systemImage], tinted by `glyphTintColor`. An SF Symbol name the OS
  /// doesn't know fails the map update with a `MapKitPlatformException`
  /// (`invalid-icon`) instead of silently drawing a plain marker.
  const new marker({
    this._markerTintColor,
    this._glyphText,
    String? systemImage,
    this._glyphTintColor,
  }) : _type = .marker,
       _glyphSystemImage = systemImage,
       _imageBytes = null,
       _imagePixelRatio = null;

  /// Raw PNG bytes as the annotation image (`MKAnnotationView.image`). Render
  /// any Flutter widget to a PNG (e.g. via `RenderRepaintBoundary.toImage`)
  /// and pass it here for a fully custom marker. Bytes the platform can't
  /// decode fail the map update with a `MapKitPlatformException`
  /// (`invalid-icon`) instead of rendering an invisible annotation.
  ///
  /// `imagePixelRatio` is the pixels-per-logical-point of [png] (pass the
  /// `pixelRatio` the widget was rendered with); defaults to the device pixel
  /// ratio, matching bytes rendered at native resolution.
  ///
  /// Throws [ArgumentError] for an `imagePixelRatio` that is not finite and
  /// `> 0`.
  new image(Uint8List png, {this._imagePixelRatio})
    : _type = .image,
      _markerTintColor = null,
      _glyphText = null,
      _glyphSystemImage = null,
      _glyphTintColor = null,
      _imageBytes = png {
    if (_imagePixelRatio case final ratio?) {
      checkPositive(ratio, 'imagePixelRatio');
    }
  }

  /// Load an annotation image from the asset bundle into an
  /// [MKAnnotationIcon.image].
  static Future<MKAnnotationIcon> asset(
    String name, {
    AssetBundle? bundle,
    String? package,
    double? devicePixelRatio,
  }) async {
    final config = ImageConfiguration(
      devicePixelRatio:
          devicePixelRatio ??
          PlatformDispatcher.instance.implicitView?.devicePixelRatio ??
          1.0,
    );
    final provider = AssetImage(name, bundle: bundle, package: package);
    final key = await provider.obtainKey(config);
    final data = await key.bundle.load(key.name);
    // key.scale is the resolved variant's scale (1x/2x/3x), which is the
    // ratio of the bytes actually loaded — not necessarily the screen's.
    return .image(.sublistView(data), imagePixelRatio: key.scale);
  }

  final PlatformAnnotationIconType _type;
  final Color? _markerTintColor;
  final String? _glyphText;
  final String? _glyphSystemImage;
  final Color? _glyphTintColor;
  final Uint8List? _imageBytes;
  final double? _imagePixelRatio;

  /// Converts this icon to its Pigeon wire representation.
  @internal
  PlatformAnnotationIcon toPlatform() => .new(
    type: _type,
    markerTintArgb: _markerTintColor?.toARGB32(),
    glyphText: _glyphText,
    glyphSystemImage: _glyphSystemImage,
    glyphTintArgb: _glyphTintColor?.toARGB32(),
    imageBytes: _imageBytes,
    imagePixelRatio: _imageBytes == null
        ? null
        : _imagePixelRatio ??
              PlatformDispatcher.instance.implicitView?.devicePixelRatio,
  );

  @override
  bool operator ==(Object other) =>
      other is MKAnnotationIcon &&
      other._type == _type &&
      other._markerTintColor == _markerTintColor &&
      other._glyphText == _glyphText &&
      other._glyphSystemImage == _glyphSystemImage &&
      other._glyphTintColor == _glyphTintColor &&
      listEquals(other._imageBytes, _imageBytes) &&
      other._imagePixelRatio == _imagePixelRatio;

  @override
  int get hashCode => Object.hash(
    _type,
    _markerTintColor,
    _glyphText,
    _glyphSystemImage,
    _glyphTintColor,
    _imageBytes == null ? null : .hashAll(_imageBytes),
    _imagePixelRatio,
  );

  @override
  String toString() {
    final b = StringBuffer('MKAnnotationIcon(')..write(_type.name);
    if (_markerTintColor case final c?) b.write(', markerTintColor: $c');
    if (_glyphText case final t?) b.write(', glyphText: $t');
    if (_glyphSystemImage case final s?) b.write(', systemImage: $s');
    if (_glyphTintColor case final c?) b.write(', glyphTintColor: $c');
    if (_imageBytes case final bytes?) b.write(', image: ${bytes.length}B');
    if (_imagePixelRatio case final r?) b.write(', imagePixelRatio: $r');
    return (b..write(')')).toString();
  }
}
