import 'dart:math' as math;
import 'dart:ui';

import '../../../ui/palette.dart';
import '../bake.dart';
import '../mesh.dart';
import '../../sprites/sprite_sheet.dart';

/// Pin tujuan GPS: penanda tetes oranye yang melayang dan berputar di ujung rute.
/// Badan pipih (ekstrusi) supaya putaran 16 arahnya terlihat.
const pinTujuanAsset = ModelAsset(pixelsPerUnit: 36, animations: [SpriteAnim('idle')], build: _build);

const _radius = 1.0;
const _center = 2.0; // tinggi pusat lingkaran dari ujung bawah
const _thick = 0.55;
const _lift = 0.5;

Model _build(SpriteAnim anim, int frame) {
  // Lingkaran + ujung lancip; garis singgung dari ujung ke lingkaran.
  final gamma = math.acos(_radius / _center);
  const steps = 14;
  final outline = <Offset>[const Offset(0, 0)];
  for (var i = 0; i <= steps; i++) {
    final a = -math.pi / 2 + gamma + (2 * math.pi - 2 * gamma) * i / steps;
    outline.add(Offset(math.cos(a) * _radius, _center + math.sin(a) * _radius));
  }
  const disc = _thick + 0.08;
  return Model([
    // Profil (bidang xy) ditegakkan ke bidang yz: lebar → y, tinggi → z, tebal → x.
    Part(
      Mesh.extrude(outline, _thick),
      const Material(BColors.oranye, gloss: 0.15),
      at: const V3(-_thick / 2, 0, _lift),
      rotX: math.pi / 2,
      rotZ: math.pi / 2,
    ),
    Part(
      Mesh.cylinder(_radius * 0.45, disc, segments: 12),
      const Material(BColors.cream),
      at: const V3(-disc / 2, 0, _lift + _center),
      rotY: math.pi / 2,
    ),
  ]);
}
