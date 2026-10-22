import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../batam_game.dart';
import '../iso.dart';
import '../map/road_layer.dart';
import '../systems/economy.dart';
import 'sprites.dart';

/// Motor matic pemain. Bisa diparkir atau dikendarai.
class Motorbike extends PositionComponent with HasGameReference<BatamGame>, IsoPlaced {
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
  static const turnRate = 4.5; // rad/detik pada grip penuh
  static const minGrip = 0.35; // supaya tetap bisa belok saat pelan
  static const sharpTurnDecel = 8.0; // pengurangan laju saat belok > 90°

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

  /// Arah gambar di layar (0..7) dengan histeresis supaya tidak berkedip di batas.
  int _octant = 0;

  MotorPose get pose => poseFor(_octant);

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

    // Setir mengikuti arah joystick di layar: moncong motor diputar ke arah itu
    // (arah layar dipetakan balik ke arah tanah).
    final stick = screenDirToGround(c.move);
    if (ridden && speed.abs() > 0.1 && stick.length2 > 0.04) {
      final target = math.atan2(stick.y, stick.x);
      final grip = (speed.abs() / 8).clamp(minGrip, 1.0);
      if (speed > 6 && wrapAngle(target - heading).abs() > math.pi / 2) speed -= sharpTurnDecel * dt;
      heading = wrapAngle(steerToward(heading, target, turnRate * grip * dt));
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
    _octant = octantWithHysteresis(_octant, screenHeadingOf(heading));
    priority = isoDepth(position);
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.scale(spriteScale);
    final p = pose;
    if (p.flip) canvas.scale(-1, 1);
    drawMotor(canvas, p.facing, rider: ridden, wheelSpin: _wheel);
    canvas.restore();
  }
}

/// Pose gambar motor: arah tampak dan apakah dicerminkan (menghadap kiri).
typedef MotorPose = ({Facing facing, bool flip});

/// Sudut dinormalisasi ke -π..π.
double wrapAngle(double a) => (a + math.pi) % (2 * math.pi) - math.pi;

/// Putar [heading] ke [target] lewat jalan terpendek, paling banyak [maxStep] radian.
double steerToward(double heading, double target, double maxStep) {
  final d = wrapAngle(target - heading);
  return d.abs() <= maxStep ? heading + d : heading + maxStep * d.sign;
}

/// Arah 8 penjuru dari [heading]: 0 = timur, 2 = selatan (bawah layar), 4 = barat, 6 = utara.
int octantOf(double heading) => (wrapAngle(heading) / (math.pi / 4)).round() % 8;

/// Seperti [octantOf], tapi tetap di [current] sampai [heading] lewat batas bin lebih dari 5°.
int octantWithHysteresis(int current, double heading) {
  const margin = 5 * math.pi / 180;
  final off = wrapAngle(heading - current * math.pi / 4).abs();
  return off > math.pi / 8 + margin ? octantOf(heading) : current;
}

MotorPose poseFor(int octant) => switch (octant % 8) {
  0 => (facing: Facing.side, flip: false),
  1 => (facing: Facing.downSide, flip: false),
  2 => (facing: Facing.down, flip: false),
  3 => (facing: Facing.downSide, flip: true),
  4 => (facing: Facing.side, flip: true),
  5 => (facing: Facing.upSide, flip: true),
  6 => (facing: Facing.up, flip: false),
  _ => (facing: Facing.upSide, flip: false),
};
