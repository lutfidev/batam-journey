import 'dart:isolate';
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
    this.directions = 16,
  });

  final double pixelsPerUnit;

  /// Jumlah arah yang dipanggang: 16 untuk aktor; bangunan cukup 4 (tegak lurus
  /// sumbu tanah, gaya kota isometrik) supaya atlasnya tidak terlalu besar.
  final int directions;
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
BakedSheet bakeModel(ModelAsset asset, {int? directions}) {
  directions ??= asset.directions;
  final layout = _layout(asset, directions);
  final cells = _renderCells(asset, layout.frame, directions, 0, layout.spec.rows * directions);
  return _assemble(layout.spec, [cells]);
}

/// Seperti [bakeModel], tetapi sel dibagi rata ke [workers] isolate
/// (HP punya banyak inti; satu isolate saja terlalu lama untuk aset besar).
Future<BakedSheet> bakeModelParallel(ModelAsset asset, {int workers = 4, int? directions}) async {
  final dirs = directions ?? asset.directions;
  final layout = _layout(asset, dirs);
  final frame = layout.frame;
  final total = layout.spec.rows * dirs;
  final per = (total / workers).ceil();
  final parts = await Future.wait([
    for (var start = 0; start < total; start += per)
      Isolate.run(() => _renderCells(asset, frame, dirs, start, math.min(total, start + per))),
  ]);
  return _assemble(layout.spec, parts);
}

double _yaw(int d, int directions) => 2 * math.pi * d / directions;

/// Ukuran sel bersama (gabungan batas semua pose di semua arah) dan spesifikasi sheet.
({PixelFrame frame, SpriteSheetSpec spec}) _layout(ModelAsset asset, int directions) {
  var bounds = ui.Rect.zero;
  for (final a in asset.animations) {
    for (var f = 0; f < a.frames; f++) {
      final m = asset.build(a, f);
      for (var d = 0; d < directions; d++) {
        bounds = bounds.expandToInclude(projectedBounds(m, _yaw(d, directions)));
      }
    }
  }
  final frame = PixelFrame.around(bounds, asset.pixelsPerUnit, pad: asset.style.padPx);
  final spec = SpriteSheetSpec(
    directions: directions,
    frameWidth: frame.width,
    frameHeight: frame.height,
    anchor: frame.anchor,
    pixelsPerUnit: asset.pixelsPerUnit,
    animations: asset.animations,
  );
  return (frame: frame, spec: spec);
}

/// Render sel ke-[start] sampai sebelum [end] (urut baris lalu arah), disambung
/// jadi satu buffer RGBA sel demi sel.
Uint8List _renderCells(ModelAsset asset, PixelFrame frame, int directions, int start, int end) {
  final poses = [
    for (final a in asset.animations)
      for (var f = 0; f < a.frames; f++) (a, f),
  ];
  final cellBytes = frame.width * frame.height * 4;
  final out = Uint8List((end - start) * cellBytes);
  Model? model;
  var modelRow = -1;
  for (var c = start; c < end; c++) {
    final row = c ~/ directions, d = c % directions;
    if (row != modelRow) {
      final (a, f) = poses[row];
      model = asset.build(a, f);
      modelRow = row;
    }
    final img = renderModel(
      model!,
      yaw: _yaw(d, directions),
      pixelsPerUnit: asset.pixelsPerUnit,
      frame: frame,
      style: asset.style,
    );
    out.setRange((c - start) * cellBytes, (c - start + 1) * cellBytes, img.rgba);
  }
  return out;
}

/// Susun potongan sel (urut) ke atlas: kolom = arah, baris = frame.
BakedSheet _assemble(SpriteSheetSpec spec, List<Uint8List> parts) {
  final fw = spec.frameWidth, fh = spec.frameHeight, sheetW = spec.sheetWidth;
  final rgba = Uint8List(sheetW * spec.sheetHeight * 4);
  var c = 0;
  for (final part in parts) {
    for (var off = 0; off < part.length; off += fw * fh * 4, c++) {
      final x0 = (c % spec.directions) * fw, y0 = (c ~/ spec.directions) * fh;
      for (var y = 0; y < fh; y++) {
        final dst = ((y0 + y) * sheetW + x0) * 4;
        rgba.setRange(dst, dst + fw * 4, part, off + y * fw * 4);
      }
    }
  }
  return BakedSheet(spec, rgba);
}

/// Versi renderer; naikkan bila hasil `raster.dart` berubah supaya cache disk lama
/// tidak dipakai lagi.
const rendererVersion = 2;

/// Sidik jari isi [asset] (semua pose, bahan, gaya, skala) untuk kunci cache disk:
/// berubah bila modelnya diubah. FNV-1a 32-bit atas byte angka-angkanya.
String fingerprint(ModelAsset asset, {int? directions}) {
  directions ??= asset.directions;
  var h = 0x811c9dc5;
  final bytes = ByteData(8);
  void num(double v) {
    bytes.setFloat64(0, v);
    for (var i = 0; i < 8; i++) {
      h = ((h ^ bytes.getUint8(i)) * 0x01000193) & 0xffffffff;
    }
  }

  void v3(V3 v) => [v.x, v.y, v.z].forEach(num);
  num(rendererVersion.toDouble());
  num(directions.toDouble());
  num(asset.pixelsPerUnit);
  final st = asset.style;
  v3(st.light);
  [
    st.ambient,
    st.diffuse,
    st.ink.toARGB32().toDouble(),
    st.outlinePx.toDouble(),
    st.supersample.toDouble(),
    st.creaseDepth,
  ].forEach(num);
  for (final a in asset.animations) {
    for (final u in a.name.codeUnits) {
      num(u.toDouble());
    }
    [a.frames.toDouble(), a.fps, a.loop ? 1.0 : 0.0].forEach(num);
    for (var f = 0; f < a.frames; f++) {
      for (final part in asset.build(a, f).parts) {
        final m = part.material;
        [m.color.toARGB32().toDouble(), m.gloss, m.shininess, m.smooth ? 1.0 : 0.0, m.inked ? 1.0 : 0.0].forEach(num);
        v3(part.at);
        v3(part.scale);
        [part.rotX, part.rotY, part.rotZ].forEach(num);
        num(part.mesh.tris.length.toDouble());
        for (final t in part.mesh.tris) {
          v3(t.a);
          v3(t.b);
          v3(t.c);
          v3(t.na);
        }
      }
    }
  }
  return h.toRadixString(16).padLeft(8, '0');
}
