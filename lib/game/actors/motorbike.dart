import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../batam_game.dart';
import '../map/road_layer.dart';
import '../systems/economy.dart';
import 'sprites.dart';

/// Motor matic pemain. Bisa diparkir atau dikendarai.
class Motorbike extends PositionComponent with HasGameReference<BatamGame> {
  Motorbike({required Vector2 position, this.heading = 0}) : super(position: position);

  /// Skala piksel desain → satuan dunia (panjang motor ±5,9 unit).
  static const spriteScale = 0.06;

  static const maxSpeed = 28.0; // unit/detik di jalan
  static const maxSpeedOffRoad = 10.0;
  static const maxReverse = 4.0;

  /// Kecepatan dorong saat bensin habis.
  static const pushSpeed = 3.0;
  static const accel = 14.0;
  static const brakeDecel = 30.0;
  static const drag = 5.0;
  static const turnRate = 2.4; // rad/detik pada kecepatan penuh setir

  /// Faktor tampilan km/j per unit/detik (28 u/s ≈ 70 km/j).
  static const kmhPerUnit = 2.5;

  double heading;
  double speed = 0;

  /// Batas kecepatan sementara (ban bocor, mogok) dan sisa waktunya.
  double _capSpeed = 0, _capTime = 0;

  bool get restricted => _capTime > 0;

  /// Batasi kecepatan maksimal ke [cap] selama [seconds] detik.
  void restrict(double cap, double seconds) {
    _capSpeed = cap;
    _capTime = seconds;
  }

  bool ridden = false;
  double _wheel = 0;

  double get speedKmh => speed.abs() * kmhPerUnit;

  Facing get facing {
    final c = math.cos(heading), s = math.sin(heading);
    if (c.abs() >= 0.5) return Facing.side;
    return s > 0 ? Facing.down : Facing.up;
  }

  @override
  void update(double dt) {
    final c = game.controls;
    final onRoad = game.graph.isOnRoad(position.toOffset());
    final tank = game.tank;
    // Bengkel: modifikasi & kondisi mesin/rem mengubah kecepatan, tarikan, dan rem.
    final ws = game.workshop;
    var top = tank.isEmpty
        ? pushSpeed
        : (onRoad ? maxSpeed : maxSpeedOffRoad) * tank.grade.speedBonus * ws.speedFactor * game.needs.speedFactor;
    if (_capTime > 0) {
      _capTime -= dt;
      top = math.min(top, _capSpeed);
    }

    if (ridden && c.gas) {
      speed += accel * ws.accelFactor * dt;
    } else if (ridden && c.brake) {
      speed = speed > 0 ? math.max(0, speed - brakeDecel * ws.brakeFactor * dt) : speed - accel * 0.5 * dt;
    } else {
      final d = drag * dt;
      speed = speed.abs() <= d ? 0 : speed - d * speed.sign;
    }
    if (speed > top) speed = math.max(top, speed - brakeDecel * dt);
    speed = speed.clamp(-maxReverse, maxSpeed * FuelGrade.turbo.speedBonus * math.max(1, ws.speedFactor));

    if (ridden && speed.abs() > 0.1) {
      final steer = (c.right ? 1 : 0) - (c.left ? 1 : 0);
      final grip = (speed.abs() / 8).clamp(0.0, 1.0);
      heading += steer * turnRate * grip * dt * speed.sign;
    }

    final next = position + Vector2(math.cos(heading), math.sin(heading)) * speed * dt;
    // Pantai: motor memantul mundur sedikit, kecuali sudah terlanjur di air
    // (mis. spawn lama) supaya tetap bisa keluar.
    if (game.isWaterBlocked(next.toOffset()) && !game.isWaterBlocked(position.toOffset())) {
      if (ridden && speed.abs() > 4) game.toast.value = 'Itu laut! Putar balik';
      speed = -speed.sign * math.max(speed.abs() * 0.3, 1.5);
    } else {
      position.setFrom(next);
    }
    if (ridden) tank.consume(speed.abs() * dt);
    game.clampToWorld(position);
    _wheel += speed * dt * 0.9;
    priority = position.y.toInt();
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.scale(spriteScale);
    final f = facing;
    if (f == Facing.side && math.cos(heading) < 0) canvas.scale(-1, 1);
    drawMotor(canvas, f, rider: ridden, wheelSpin: _wheel);
    canvas.restore();
  }
}
