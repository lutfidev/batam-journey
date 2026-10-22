import 'dart:math' as math;
import 'dart:ui';

import '../../../ui/palette.dart';
import '../bake.dart';
import '../mesh.dart';
import '../../sprites/sprite_sheet.dart';

/// Pernik kota: pohon dan lampu jalan. Titik (0,0,0) = pangkal di tanah.

/// Jenis pohon per frame `pohon`.
abstract final class PohonFrame {
  static const bulat = 0;
  static const rimbun = 1;
  static const kelapa = 2;
  static const cemara = 3;
  static const count = 4;
}

/// Pohon dipanggang 4 arah; arah dipilih acak per pohon supaya tidak seragam.
final pohonAsset = ModelAsset(
  pixelsPerUnit: 26,
  directions: 4,
  animations: const [SpriteAnim('diam', frames: PohonFrame.count, fps: 0)],
  build: (_, f) => _pohon(f),
);

const _trunk = Material(Color(0xFF8A5A3B));
const _leaf = Material(BColors.hutan, smooth: true, gloss: 0.12, shininess: 12);
const _leafDark = Material(BColors.hutanGelap, smooth: true, gloss: 0.1, shininess: 12);
const _leafLight = Material(Color(0xFFA9D58F), smooth: true, gloss: 0.12, shininess: 12);
const _palm = Material(Color(0xFF5FA35A));

Part _ball(double x, double y, double z, double r, Material m, {double squash = 0.9}) =>
    Part(Mesh.sphere(r, rz: r * squash, segments: 12, rings: 8), m, at: V3(x, y, z));

Model _pohon(int f) => switch (f) {
  PohonFrame.bulat => Model([
    Part(Mesh.cylinder(0.28, 1.6, rTop: 0.2, segments: 8), _trunk),
    _ball(0, 0, 2.6, 1.55, _leaf),
    _ball(-0.5, -0.4, 3.35, 0.8, _leafLight),
  ]),
  PohonFrame.rimbun => Model([
    Part(Mesh.cylinder(0.3, 1.4, rTop: 0.2, segments: 8), _trunk),
    _ball(0.5, 0.3, 2.2, 1.2, _leafDark),
    _ball(-0.6, 0.2, 2.4, 1.15, _leafDark),
    _ball(0, -0.5, 3.0, 1.25, _leaf),
  ]),
  PohonFrame.kelapa => _kelapa(),
  _ => Model([
    Part(Mesh.cylinder(0.2, 0.9, segments: 8), _trunk),
    Part(Mesh.cylinder(1.3, 1.9, rTop: 0, segments: 9), _leafDark, at: const V3(0, 0, 0.8)),
    Part(Mesh.cylinder(1.0, 1.7, rTop: 0, segments: 9), _leaf, at: const V3(0, 0, 2.0)),
  ]),
};

/// Pohon kelapa: batang melengkung dari ruas-ruas silinder dan pelepah menjuntai.
Model _kelapa() {
  final parts = <Part>[];
  var at = V3.zero;
  const segs = 5;
  for (var i = 0; i < segs; i++) {
    final tilt = 0.08 + i * 0.05;
    parts.add(Part(Mesh.cylinder(0.2 - i * 0.015, 0.95, segments: 7), _trunk, at: at, rotY: tilt));
    at = at + V3(math.sin(tilt) * 0.95, 0, math.cos(tilt) * 0.95);
  }
  for (var k = 0; k < 7; k++) {
    final a = 2 * math.pi * k / 7;
    // Pelepah: elipsoid pipih memanjang, condong ke bawah di ujung.
    parts.add(
      Part(
        Mesh.sphere(1.0, ry: 0.28, rz: 0.08, segments: 8, rings: 4),
        _palm,
        at: at + V3(math.cos(a) * 0.9, math.sin(a) * 0.9, -0.2),
        scale: const V3(1.1, 1, 1),
        rotY: 0.45,
        rotZ: a,
      ),
    );
  }
  parts.add(_ball(at.x, at.y, at.z - 0.1, 0.32, const Material(Color(0xFF6B8F3A)), squash: 1));
  return Model(parts);
}

/// Lampu jalan: tiang, lengan ke arah jalan (+x), dan kap lampu.
/// 16 arah supaya lengannya selalu menunjuk ke jalan.
final lampuJalanAsset = ModelAsset(
  pixelsPerUnit: 26,
  animations: const [SpriteAnim('diam', fps: 0)],
  build: (_, _) => _lampu,
);

/// Titik kap lampu (model), untuk cahaya malam nanti.
const lampuHead = V3(1.55, 0, 5.15);

const _pole = Material(Color(0xFF5B6470), gloss: 0.3, shininess: 20);

final _lampu = Model([
  Part(Mesh.cylinder(0.22, 0.5, segments: 8), _pole),
  Part(Mesh.cylinder(0.11, 5.4, rTop: 0.08, segments: 8), _pole),
  Part(Mesh.box(1.7, 0.14, 0.14), _pole, at: const V3(0.8, 0, 5.3)),
  Part(Mesh.box(0.75, 0.42, 0.22), _pole, at: const V3(1.55, 0, 5.12)),
  Part(Mesh.box(0.6, 0.3, 0.05), const Material(Color(0xFFFFF3B0)), at: const V3(1.55, 0, 5.07)),
]);
