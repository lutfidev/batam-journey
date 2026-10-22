import 'dart:math' as math;
import 'dart:ui';

import '../../../ui/palette.dart';
import '../bake.dart';
import '../mesh.dart';
import '../../sprites/sprite_sheet.dart';
import 'slime.dart';

/// Motor matic ojek pemain dengan box oranye. Menghadap +x, kanan motor = +y.
///
/// Animasi:
/// - `parkir`: tanpa pengendara, miring sedikit ke kiri di standar samping.
/// - `kendara`: slime berhelm di jok; frame = kemiringan dari [motorMaxLean] ke kiri
///   sampai ke kanan (lihat [motorLeanFrame]). Dipilih dari laju belok, bukan fps.
const motorAsset = ModelAsset(
  pixelsPerUnit: 32,
  animations: [
    SpriteAnim('parkir'),
    SpriteAnim('kendara', frames: motorLeanFrames),
  ],
  build: _build,
);

/// Jumlah tingkat kemiringan yang dipanggang (ganjil supaya ada frame tegak).
const motorLeanFrames = 7;

/// Kemiringan terbesar saat belok (radian).
const motorMaxLean = 28 * math.pi / 180;

/// Kemiringan standar samping saat parkir (ke kiri).
const _parkLean = -8 * math.pi / 180;

/// Frame `kendara` terdekat untuk kemiringan [lean] (positif = ke kanan).
int motorLeanFrame(double lean) {
  final t = (lean / motorMaxLean).clamp(-1.0, 1.0);
  return ((t + 1) / 2 * (motorLeanFrames - 1)).round();
}

/// Kemiringan frame `kendara` ke-[frame].
double motorLeanOf(int frame) => (frame / (motorLeanFrames - 1) * 2 - 1) * motorMaxLean;

/// Titik penting di model tegak (satuan dunia) untuk efek saat main.
abstract final class MotorPoints {
  /// Ujung knalpot (sisi kanan, rendah): sumber asap.
  static const exhaust = V3(-2.15, 0.55, 0.5);

  /// Lampu rem di buritan.
  static const tailLight = V3(-2.47, 0, 1.13);

  /// Titik sentuh roda belakang di tanah: sumber jejak rem.
  static const rearWheel = V3(-1.6, 0, 0);
}

const _paint = Material(Color(0xFF3A72B8), gloss: 0.35, shininess: 30);
const _dark = Material(Color(0xFF3B3F47));
const _tyre = Material(Color(0xFF2B2B30));
const _metal = Material(Color(0xFFA7AFB8), gloss: 0.6, shininess: 30);
const _seat = Material(Color(0xFF33302E), gloss: 0.2);
const _box = Material(BColors.oranye, gloss: 0.1);
const _helmet = Material(Color(0xFF4DB06B), smooth: true, gloss: 0.5, shininess: 40);
const _jelly = Material(Color(0xFF4F95DC), smooth: true, gloss: 0.8, shininess: 60);

const _wheelR = 0.62, _wheelW = 0.3;
const _frontX = 1.95, _rearX = -1.6;
const _riderAt = V3(-0.8, 0, 1.62);
const _riderScale = 0.72;
const _gripX = 1.42, _gripZ = 2.12;

/// Profil samping (x, z) diekstrusi selebar [width] ke arah y, berpusat di y = [y].
Part _side(List<Offset> xz, double width, Material m, {double y = 0}) =>
    Part(Mesh.extrude(xz, width), m, at: V3(0, y + width / 2, 0), rotX: math.pi / 2);

/// Silinder berporos y (roda, setang) selebar [w], berpusat di ([x], [y], [z]).
Part _axle(double r, double w, Material m, double x, double z, {double y = 0, int segments = 12}) =>
    Part(Mesh.cylinder(r, w, segments: segments), m, at: V3(x, y + w / 2, z), rotX: math.pi / 2);

/// Elipsoid memanjang dari [a] ke [b] setebal [r] (lengan, batang).
Part _limb(V3 a, V3 b, double r, Material m) {
  final d = b - a;
  final len = d.length;
  return Part(
    Mesh.sphere(1, segments: 10, rings: 6),
    m,
    at: (a + b) * 0.5,
    scale: V3(len / 2, r, r),
    rotY: math.asin(-d.z / len),
    rotZ: math.atan2(d.y, d.x),
  );
}

/// Pita busur (spakbor) di bidang xz: pusat [c], jari-jari dalam [r0] dan luar [r1].
List<Offset> _arc(Offset c, double r0, double r1, double from, double to, {int steps = 8}) => [
  for (var i = 0; i <= steps; i++) c + Offset.fromDirection(from + (to - from) * i / steps, r1),
  for (var i = steps; i >= 0; i--) c + Offset.fromDirection(from + (to - from) * i / steps, r0),
];

final _bike = <Part>[
  // Roda + velg.
  for (final x in const [_frontX, _rearX]) ...[
    _axle(_wheelR, _wheelW, _tyre, x, _wheelR, segments: 14),
    _axle(0.3, _wheelW + 0.06, _metal, x, _wheelR),
  ],
  // Badan belakang di bawah jok, menutup atas roda belakang.
  _side(const [
    Offset(-2.35, 0.92),
    Offset(-1.0, 0.86),
    Offset(-0.55, 0.58),
    Offset(-0.15, 0.58),
    Offset(-0.15, 1.15),
    Offset(-0.4, 1.42),
    Offset(-2.05, 1.5),
    Offset(-2.42, 1.22),
  ], 0.92, _paint),
  // Dek pijakan kaki.
  Part(Mesh.box(1.2, 0.95, 0.14), _dark, at: const V3(0.45, 0, 0.5)),
  // Tameng kaki & batang depan sampai kepala setang.
  _side(const [
    Offset(0.9, 0.5),
    Offset(1.25, 0.5),
    Offset(1.4, 1.0),
    Offset(1.6, 1.7),
    Offset(1.42, 1.95),
    Offset(1.15, 1.92),
    Offset(0.98, 1.3),
  ], 0.82, _paint),
  // Spakbor depan di atas roda.
  _side(_arc(const Offset(_frontX, _wheelR), 0.68, 0.8, 0.45, 2.5), 0.4, _paint),
  // Garpu depan.
  for (final y in const [-0.19, 0.19])
    Part(Mesh.cylinder(0.07, 1.14, segments: 6), _metal, at: V3(_frontX, y, _wheelR), rotY: -0.31),
  // Kepala setang + lampu depan.
  Part(Mesh.box(0.55, 1.0, 0.28), _paint, at: const V3(1.45, 0, 1.92)),
  Part(
    Mesh.sphere(0.2, ry: 0.32, rz: 0.14, segments: 10, rings: 6),
    const Material(Color(0xFFFFF3B0), smooth: true, gloss: 0.6),
    at: const V3(1.74, 0, 2.03),
  ),
  // Setang, handel, dan spion.
  _axle(0.06, 1.5, _dark, _gripX, _gripZ, segments: 6),
  for (final y in const [-0.6, 0.6]) _axle(0.09, 0.3, _tyre, _gripX, _gripZ, y: y, segments: 6),
  for (final side in const [-1.0, 1.0]) ...[
    Part(Mesh.cylinder(0.03, 0.45, segments: 5), _dark, at: V3(1.38, side * 0.45, _gripZ), rotX: -side * 0.3),
    Part(
      Mesh.sphere(0.08, ry: 0.17, rz: 0.11, segments: 8, rings: 5),
      _metal,
      at: V3(1.36, side * 0.58, _gripZ + 0.45),
    ),
  ],
  // Jok, lampu rem, knalpot (kanan), dan blok mesin (kiri).
  Part(Mesh.box(1.7, 0.84, 0.2), _seat, at: const V3(-1.15, 0, 1.45)),
  Part(Mesh.box(0.1, 0.5, 0.16), const Material(BColors.atapMerah), at: const V3(-2.42, 0, 1.05)),
  Part(Mesh.cylinder(0.12, 1.0, segments: 8), _metal, at: const V3(-1.15, 0.55, 0.5), rotY: -math.pi / 2),
  Part(Mesh.box(1.0, 0.3, 0.38), const Material(Color(0xFF6B737C)), at: const V3(-1.25, -0.4, 0.3)),
  // Box ojek di rak belakang.
  Part(Mesh.box(1.0, 1.05, 0.8), _box, at: const V3(-2.3, 0, 1.5)),
  Part(Mesh.box(1.04, 1.09, 0.14), const Material(Color(0xFFD9752A)), at: const V3(-2.3, 0, 2.24)),
];

/// Helm hijau di kepala slime (koordinat slime, sebelum diperkecil): kubah yang
/// mengikuti lengkung badan dari atas mata ke ubun-ubun, pinggiran, dan pet.
final _helmetParts = () {
  const z0 = 1.5, lift = 0.12, gap = 0.1;
  final dome = [
    for (var k = 0; k <= 8; k++)
      () {
        final z = z0 + (slimeHeight - z0) * k / 8;
        return Offset(slimeRadiusAt(z) + gap, z + lift * k / 8);
      }(),
    const Offset(0, slimeHeight + lift + 0.01),
  ];
  final rim = slimeRadiusAt(z0) + gap + 0.04;
  return <Part>[
    Part(Mesh.lathe(dome, segments: 16), _helmet),
    Part(Mesh.cylinder(rim, 0.1, segments: 16), const Material(Color(0xFF24572F)), at: const V3(0, 0, z0 - 0.06)),
    Part(
      Mesh.sphere(0.24, ry: 0.55, rz: 0.06, segments: 10, rings: 4),
      const Material(Color(0xFF24572F)),
      at: V3(rim - 0.08, 0, z0 + 0.04),
      rotY: 0.25,
    ),
  ];
}();

/// Slime berhelm yang duduk di jok, dengan lengan jelly ke handel.
Model _rider() {
  final body = Model([...slimeModel().parts, ..._helmetParts]).placed(_riderAt, scale: _riderScale);
  return Model([
    ...body.parts,
    for (final side in const [-1.0, 1.0]) ...[
      _limb(V3(-0.45, side * 0.6, 2.25), V3(_gripX - 0.05, side * 0.58, _gripZ + 0.02), 0.13, _jelly),
      Part(Mesh.sphere(0.16, segments: 8, rings: 6), _jelly, at: V3(_gripX, side * 0.6, _gripZ + 0.04)),
    ],
  ]);
}

Model _build(SpriteAnim anim, int frame) => switch (anim.name) {
  // Putaran x positif = atas condong ke kiri, jadi kemiringan dibalik tandanya.
  'parkir' => Model(_bike).rolled(-_parkLean),
  _ => Model([..._bike, ..._rider().parts]).rolled(-motorLeanOf(frame)),
};
