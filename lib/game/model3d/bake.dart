import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../sprites/sprite_sheet.dart';
import 'mesh.dart';
import 'raster.dart';

/// Aset yang dipanggang dari model Dart: model per frame animasi + skala piksel.
class ModelAsset {
  const ModelAsset({
    required this.pixelsPerUnit,
    required this.animations,
    required this.build,
    this.style = const RenderStyle(),
  });

  final double pixelsPerUnit;
  final List<SpriteAnim> animations;

  /// Model untuk frame ke-[frame] animasi [anim], menghadap +x.
  final Model Function(SpriteAnim anim, int frame) build;
  final RenderStyle style;
}

/// Atlas piksel RGBA premultiplied hasil panggang, sebelum jadi gambar GPU.
class BakedSheet {
  BakedSheet(this.spec, this.rgba);

  final SpriteSheetSpec spec;
  final Uint8List rgba;

  /// Unggah ke GPU sebagai [ui.Image].
  Future<ui.Image> toImage() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final desc = ui.ImageDescriptor.raw(
      buffer,
      width: spec.sheetWidth,
      height: spec.sheetHeight,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    desc.dispose();
    buffer.dispose();
    return frame.image;
  }

  Future<DirectionalSprite> toSprite() async => DirectionalSprite(await toImage(), spec);
}

/// Panggang [asset] ke 16 arah × semua frame. Ukuran sel sama untuk semua pose
/// (gabungan batas semua pose), dan titik pijak ada di koordinat piksel bulat.
BakedSheet bakeModel(ModelAsset asset, {int directions = 16}) {
  final ppu = asset.pixelsPerUnit;
  final models = [
    for (final a in asset.animations)
      for (var f = 0; f < a.frames; f++) asset.build(a, f),
  ];
  double yaw(int d) => 2 * math.pi * d / directions;

  var bounds = ui.Rect.zero;
  for (final m in models) {
    for (var d = 0; d < directions; d++) {
      bounds = bounds.expandToInclude(projectedBounds(m, yaw(d)));
    }
  }
  final frame = PixelFrame.around(bounds, ppu, pad: asset.style.padPx);
  final spec = SpriteSheetSpec(
    directions: directions,
    frameWidth: frame.width,
    frameHeight: frame.height,
    anchor: frame.anchor,
    pixelsPerUnit: ppu,
    animations: asset.animations,
  );

  final sheetW = spec.sheetWidth;
  final rgba = Uint8List(sheetW * spec.sheetHeight * 4);
  for (var row = 0; row < models.length; row++) {
    for (var d = 0; d < directions; d++) {
      final img = renderModel(models[row], yaw: yaw(d), pixelsPerUnit: ppu, frame: frame, style: asset.style);
      final x0 = d * frame.width, y0 = row * frame.height;
      for (var y = 0; y < frame.height; y++) {
        final src = y * frame.width * 4;
        rgba.setRange(((y0 + y) * sheetW + x0) * 4, ((y0 + y) * sheetW + x0 + frame.width) * 4, img.rgba, src);
      }
    }
  }
  return BakedSheet(spec, rgba);
}
