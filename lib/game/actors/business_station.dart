import 'dart:ui';

import 'package:flame/components.dart';

import '../../ui/palette.dart';
import '../city/city_gen.dart';
import '../city/city_layer.dart';
import '../model3d/models/buildings.dart';
import '../sprites/sprite_library.dart';
import '../systems/business.dart';

/// Ruko usaha (model 3D `ruko`, warna kanopi per jenis usaha), dengan papan
/// nama dan status DISEWAKAN / BUKA. [position] = depan etalase.
class BusinessStation {
  BusinessStation({required this.site, required this.type}) : position = Vector2(site.entrance.dx, site.entrance.dy);

  final Site site;
  final Vector2 position;
  final BizType type;

  static const serviceRange = 9.0;

  /// Frame ruko (warna kanopi) per usaha, lihat [rukoColors].
  static const _frames = {'kopi': 0, 'warung': 1, 'laundry': 2, 'kurir': 3};
  static const _labels = {'kopi': 'KOPI', 'warung': 'WARUNG', 'laundry': 'LAUNDRY', 'kurir': 'KURIR'};

  List<CityProp> props(BusinessSystem business) {
    final f = facingVector(site.facing);
    final signAt = site.entrance + Offset(f.dy, -f.dx) * 2.0;
    return [
      CityProp(
        PropSpec(
          sprite: SpriteIds.ruko,
          frame: _frames[type.id] ?? 4,
          dir: site.facing,
          at: site.center,
          footprint: site.footprint,
          blockers: site.blockers,
        ),
        overlay: faceLabel(_labels[type.id] ?? type.name.toUpperCase(), rukoInfo.label!, site.facing),
      ),
      statusSign(signAt, () {
        if (type.locked) return ('SEGERA', const Color(0xFF6B5440));
        if (business.owns(type.id)) return ('BUKA', BColors.hijauAksi);
        return ('DISEWAKAN', BColors.atapMerah);
      }),
    ];
  }
}
