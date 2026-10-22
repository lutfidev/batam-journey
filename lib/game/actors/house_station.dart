import 'dart:ui';

import 'package:flame/components.dart';

import '../../ui/palette.dart';
import '../city/city_gen.dart';
import '../city/city_layer.dart';
import '../model3d/models/buildings.dart';
import '../sprites/sprite_library.dart';
import '../systems/housing.dart';

/// Rumah di pinggir jalan: kos Bu Ros, rumah dijual, atau rumah milikmu.
/// Papan di depannya berubah: KOS / DIJUAL / RUMAHMU. [position] = depan pintu.
class HouseStation {
  HouseStation({required this.site, required this.homeId, required this.title})
    : position = Vector2(site.entrance.dx, site.entrance.dy);

  final Site site;
  final Vector2 position;
  final String homeId;
  final String title;

  bool get isKos => homeId == Housing.kosId;

  /// Jarak (unit dunia) dari [position] untuk bisa masuk / melihat rumah.
  static const serviceRange = 9.0;

  /// Model & frame per rumah: kos dan villa punya model sendiri; ruko dijual
  /// memakai ruko oranye; rumah subsidi/cluster memakai warna atap desainnya.
  static (String, int, BuildingInfo) modelFor(String homeId) => switch (homeId) {
    Housing.kosId => (SpriteIds.kos, 0, kosInfo),
    'villa' => (SpriteIds.villa, 0, villaInfo),
    'ruko' => (SpriteIds.ruko, 4, rukoInfo),
    'cluster' => (SpriteIds.rumah, 1, rumahInfo),
    _ => (SpriteIds.rumah, 0, rumahInfo),
  };

  List<CityProp> props(Housing housing) {
    final (sprite, frame, _) = modelFor(homeId);
    // Papan status di halaman depan, agak ke kanan pintu.
    final f = facingVector(site.facing);
    final signAt = site.entrance + Offset(f.dy, -f.dx) * 2.2;
    return [
      CityProp(
        PropSpec(
          sprite: sprite,
          frame: frame,
          dir: site.facing,
          at: site.center,
          footprint: site.footprint,
          blockers: site.blockers,
        ),
      ),
      statusSign(signAt, () {
        if (isKos) return ('KOS', BColors.oranye);
        if (housing.owned.value.contains(homeId)) return ('RUMAHMU', BColors.hijauAksi);
        return ('DIJUAL', BColors.atapMerah);
      }),
    ];
  }
}
