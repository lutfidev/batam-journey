import 'package:flame/components.dart';

import '../city/city_gen.dart';
import '../city/city_layer.dart';
import '../model3d/models/buildings.dart';
import '../sprites/sprite_library.dart';

/// SPBU "BensinKu" di pinggir jalan (model 3D `spbu`). [position] = titik
/// parkir di bawah kanopi, di antara dua pulau pompa.
class FuelStation {
  FuelStation({required this.site, required this.area, required this.pumpNo})
    : position = Vector2(site.entrance.dx, site.entrance.dy);

  final Site site;
  final Vector2 position;
  final String area;
  final int pumpNo;

  /// Jarak (unit dunia) dari [position] untuk bisa isi bensin.
  static const serviceRange = 9.0;

  List<CityProp> get props => [
    CityProp(
      PropSpec(
        sprite: SpriteIds.spbu,
        dir: site.facing,
        at: site.center,
        footprint: site.footprint,
        blockers: site.blockers,
      ),
      overlay: faceLabel('SPBU', spbuInfo.label!, site.facing),
    ),
  ];
}
