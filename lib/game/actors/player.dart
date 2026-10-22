import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../batam_game.dart';
import '../map/road_layer.dart';
import 'motorbike.dart';
import 'sprites.dart';

enum PlayerMode { walking, riding }

/// Pemain (Lutfi). Saat naik motor, posisinya menempel ke motor
/// sehingga kamera cukup mengikuti satu komponen ini.
class Player extends PositionComponent with HasGameReference<BatamGame> {
  Player({required Vector2 position}) : super(position: position);

  /// Skala piksel desain → satuan dunia (tinggi badan ±4,6 unit).
  static const spriteScale = 0.032;
  static const walkSpeed = 6.0;

  /// Jarak maksimal (unit dunia) untuk bisa naik motor.
  static const boardRange = 5.0;

  PlayerMode mode = PlayerMode.walking;
  Motorbike? vehicle;

  final Vector2 _facing = Vector2(0, 1);
  double _phase = 0;
  bool _moving = false;

  bool get isRiding => mode == PlayerMode.riding;

  double get heading => math.atan2(_facing.y, _facing.x);

  void board(Motorbike bike) {
    vehicle = bike..ridden = true;
    mode = PlayerMode.riding;
  }

  /// Turun di sisi kiri motor (relatif arah hadap).
  void dismount() {
    final bike = vehicle;
    if (bike == null) return;
    bike.ridden = false;
    final side = Vector2(math.sin(bike.heading), -math.cos(bike.heading))..scale(3.2);
    position = bike.position + side;
    // Di jembatan/pinggir pantai: jangan turun ke air, tetap di atas motor.
    if (game.isWaterBlocked(position.toOffset())) position.setFrom(bike.position);
    game.clampToWorld(position);
    mode = PlayerMode.walking;
    vehicle = null;
  }

  @override
  void update(double dt) {
    if (isRiding) {
      position.setFrom(vehicle!.position);
      priority = position.y.toInt() + 1;
      return;
    }
    final move = game.controls.move;
    _moving = move.length2 > 0.0025;
    if (_moving) {
      final m = move.length > 1 ? move.normalized() : move;
      _walk(m * walkSpeed * dt);
      _facing.setFrom(m);
      _phase += dt * (6 + 6 * m.length);
    } else {
      _phase = 0;
    }
    priority = position.y.toInt();
  }

  /// Gerak sejauh [d]; di pantai meluncur sepanjang garis pantai (coba X lalu Y).
  void _walk(Vector2 d) {
    final from = position.toOffset();
    final stuck = game.isWaterBlocked(from);
    for (final step in [d, Vector2(d.x, 0), Vector2(0, d.y)]) {
      final next = position + step;
      if (stuck || !game.isWaterBlocked(next.toOffset())) {
        position.setFrom(next);
        break;
      }
    }
    game.clampToWorld(position);
  }

  @override
  void render(Canvas canvas) {
    if (isRiding) return;
    final facing = _facing.y < -0.6 ? Facing.up : Facing.down;
    canvas.save();
    canvas.scale(spriteScale);
    drawWalker(canvas, facing, _phase, _facing.x.clamp(-1.0, 1.0), _moving);
    canvas.restore();
  }
}
