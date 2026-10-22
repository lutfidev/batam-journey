import 'dart:math' as math;
import 'dart:ui';

import '../../../ui/palette.dart';
import '../bake.dart';
import '../mesh.dart';
import '../../sprites/sprite_sheet.dart';

/// Pemain: slime jelly biru 3D dengan mata besar. Badan = bentuk putar (gumdrop)
/// yang dipenyet/dilarkan per frame; tinggi lompatan TIDAK dipanggang, tetapi
/// digeser saat menggambar (lihat [slimeHop]) supaya bayangan bisa mengikutinya.
///
/// Animasi:
/// - `idle`: bernapas pelan.
/// - `kedip`: mata tertutup, ditampilkan sebentar oleh game.
/// - `jalan`: satu siklus lompat; frame dipilih dari fase lompat, bukan fps.
/// - `lelah`: kelopak mata turun (energi rendah), bernapas lebih lambat.
const slimeAsset = ModelAsset(
  pixelsPerUnit: 36,
  animations: [
    SpriteAnim('idle', frames: 4, fps: 2.5),
    SpriteAnim('kedip'),
    SpriteAnim('jalan', frames: 6, fps: 12),
    SpriteAnim('lelah', frames: 2, fps: 1.2),
  ],
  build: _build,
);

const _radius = 1.3;
const _height = 2.05;
const _bodyColor = Color(0xFF4F95DC);
const _lidColor = Color(0xFF4A8ED6);

/// Tinggi lompatan (satuan dunia) dan skala tegak badan pada fase [u] (0..1)
/// satu siklus lompat. u = 0 = mendarat (gepeng), lalu melar saat lepas landas,
/// bulat di puncak, dan melar lagi menjelang mendarat.
({double lift, double stretch}) slimeHop(double u) {
  u = u % 1;
  const air0 = 0.12, air1 = 0.88;
  final lift = u <= air0 || u >= air1 ? 0.0 : 0.6 * math.sin(math.pi * (u - air0) / (air1 - air0));
  return (lift: lift, stretch: _keyed(u, const [(0, 0.8), (0.17, 1.15), (0.5, 1.0), (0.83, 1.1), (1, 0.8)]));
}

/// Interpolasi kosinus antar-kunci (u, nilai) yang terurut.
double _keyed(double u, List<(double, double)> keys) {
  for (var i = 0; i + 1 < keys.length; i++) {
    final (u0, v0) = keys[i];
    final (u1, v1) = keys[i + 1];
    if (u <= u1) {
      final t = (1 - math.cos(math.pi * (u - u0) / (u1 - u0))) / 2;
      return v0 + (v1 - v0) * t;
    }
  }
  return keys.last.$2;
}

/// Profil badan: alas datar dengan tepi membulat, sisi sedikit menggembung,
/// kubah bulat di atas.
final List<Offset> _profile = [
  const Offset(0, 0),
  const Offset(_radius * 0.86, 0),
  const Offset(_radius * 0.98, 0.07),
  const Offset(_radius * 1.03, 0.24),
  for (var k = 1; k <= 9; k++)
    () {
      final phi = math.pi / 2 * k / 9;
      return Offset(_radius * 1.03 * math.pow(math.cos(phi), 0.85), 0.24 + (_height - 0.24) * math.sin(phi));
    }(),
];

/// Tinggi badan slime tegak (satuan dunia), tanpa dilarkan.
const slimeHeight = _height;

/// Jari-jari badan (sebelum dipenyet) pada tinggi [z].
double slimeRadiusAt(double z) {
  for (var k = 0; k + 1 < _profile.length; k++) {
    final a = _profile[k], b = _profile[k + 1];
    if (z <= b.dy && b.dy > a.dy) return a.dx + (b.dx - a.dx) * (z - a.dy) / (b.dy - a.dy);
  }
  return 0;
}

final _body = Mesh.lathe(_profile, segments: 20);
final _ball = Mesh.sphere(1, segments: 12, rings: 8);

Model _build(SpriteAnim anim, int frame) => slimeModel(
  stretch: switch (anim.name) {
    'jalan' => slimeHop(frame / anim.frames).stretch,
    'lelah' => 1 - 0.03 * math.sin(2 * math.pi * frame / anim.frames),
    'idle' => 1 + 0.035 * math.sin(2 * math.pi * frame / anim.frames),
    _ => 1.0,
  },
  eyes: switch (anim.name) {
    'kedip' => SlimeEyes.closed,
    'lelah' => SlimeEyes.sleepy,
    _ => SlimeEyes.open,
  },
);

/// Badan slime menghadap +x dengan alas di (0,0,0), dilarkan tegak [stretch]
/// kali. Dipakai juga untuk pengendara motor (`motor.dart`).
Model slimeModel({double stretch = 1, SlimeEyes eyes = SlimeEyes.open}) {
  // Volume tetap: melar ke atas = menyempit ke samping.
  final s = V3(1 / math.sqrt(stretch), 1 / math.sqrt(stretch), stretch);
  final parts = <Part>[Part(_body, const Material(_bodyColor, smooth: true, gloss: 0.8, shininess: 60), scale: s)];

  /// Bola berjari-jari [r] yang menempel di permukaan badan pada tinggi [z],
  /// sudut [a] dari depan, dan menonjol [out] dari permukaan.
  void onSurface(double z, double a, V3 r, Material m, {double out = 0}) {
    final rad = slimeRadiusAt(z) * s.x + out;
    parts.add(Part(_ball, m, at: V3(math.cos(a) * rad, math.sin(a) * rad, z * s.z), scale: r, rotZ: a));
  }

  const eyeZ = 1.18, eyeA = 0.36;
  for (final side in const [-1.0, 1.0]) {
    final a = side * eyeA;
    switch (eyes) {
      case SlimeEyes.closed:
        onSurface(eyeZ - 0.06, a, const V3(0.06, 0.2, 0.045), const Material(BColors.ink), out: 0.01);
      case SlimeEyes.open || SlimeEyes.sleepy:
        onSurface(eyeZ, a, const V3(0.12, 0.25, 0.32), const Material(Color(0xFFFFFFFF), smooth: true), out: -0.04);
        // Pupil sedikit ke tengah & bawah: menatap ke depan, terlihat ramah. Kilap
        // putih di pupil muncul dari specular.
        onSurface(
          eyeZ - 0.05,
          a - side * 0.05,
          const V3(0.08, 0.15, 0.2),
          const Material(BColors.ink, smooth: true, gloss: 1, shininess: 40),
          out: 0.02,
        );
        if (eyes == SlimeEyes.sleepy) {
          // Kelopak: bola sewarna badan menutup setengah atas mata.
          onSurface(eyeZ + 0.12, a, const V3(0.15, 0.28, 0.2), const Material(_lidColor, smooth: true), out: -0.005);
        }
    }
  }

  // Pipi merona tanpa garis tinta.
  for (final side in const [-1.0, 1.0]) {
    onSurface(
      0.82,
      side * 0.72,
      const V3(0.05, 0.17, 0.1),
      const Material(Color(0xFFF0A0AE), smooth: true, inked: false),
      out: -0.015,
    );
  }
  // Senyum kecil: deretan bola tinta kecil melengkung.
  const smile = 9;
  for (var i = 0; i < smile; i++) {
    final t = i / (smile - 1) * 2 - 1;
    onSurface(
      0.8 - 0.06 * (1 - t * t),
      t * 0.14,
      const V3(0.04, 0.04, 0.04),
      const Material(BColors.ink, inked: false),
      out: -0.01,
    );
  }
  return Model(parts);
}

enum SlimeEyes { open, closed, sleepy }
