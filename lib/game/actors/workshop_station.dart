import 'package:flame/components.dart';

import '../city/city_gen.dart';
import '../city/city_layer.dart';
import '../model3d/models/buildings.dart';
import '../sprites/sprite_library.dart';

/// Bengkel motor di pinggir jalan (model 3D `bengkel`). [position] = depan
/// pintu gulung.
class WorkshopStation {
  WorkshopStation({required this.site, required this.name}) : position = Vector2(site.entrance.dx, site.entrance.dy);

  final Site site;
  final Vector2 position;
  final String name;

  /// Jarak (unit dunia) dari [position] untuk bisa masuk bengkel.
  static const serviceRange = 9.0;

  List<CityProp> get props => [
    CityProp(
      PropSpec(
        sprite: SpriteIds.bengkel,
        dir: site.facing,
        at: site.center,
        footprint: site.footprint,
        blockers: site.blockers,
      ),
      overlay: faceLabel('BENGKEL', bengkelInfo.label!, site.facing),
    ),
  ];
}
