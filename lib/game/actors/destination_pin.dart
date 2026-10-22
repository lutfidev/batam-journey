import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../batam_game.dart';
import '../iso.dart';
import '../sprites/sprite_sheet.dart';
import 'sprites.dart';

/// Pin 3D di ujung rute GPS: melayang naik-turun dan berputar melewati 16 arah.
class DestinationPin extends PositionComponent with HasGameReference<BatamGame>, IsoPlaced {
  DestinationPin(this.sprite);

  final DirectionalSprite sprite;

  /// Satu putaran penuh per detik ini.
  static const spinSeconds = 1.6;

  double _time = 0;
  bool _shown = false;

  @override
  void update(double dt) {
    final route = game.gps.route;
    _shown = route != null && game.gps.destination != null;
    if (!_shown) return;
    final end = route!.points.last;
    position.setValues(end.dx, end.dy);
    priority = isoDepth(position);
    _time += dt;
  }

  @override
  void render(Canvas canvas) {
    if (!_shown) return;
    final bob = 0.25 * (1 + math.sin(_time * 3));
    drawShadow(canvas, Offset.zero, 1.3 - bob * 0.3, 0.6 - bob * 0.1);
    final dir = (_time / spinSeconds * sprite.spec.directions).floor() % sprite.spec.directions;
    canvas.save();
    canvas.translate(0, -bob);
    sprite.render(canvas, direction: dir);
    canvas.restore();
  }
}
