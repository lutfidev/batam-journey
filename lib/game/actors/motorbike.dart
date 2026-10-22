import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../batam_game.dart';
import '../iso.dart';
import '../map/road_graph.dart';
import '../map/road_layer.dart';
import '../model3d/mesh.dart' show V3;
import '../model3d/models/motor.dart';
import '../model3d/raster.dart' show IsoCamera;
import '../sprites/sprite_sheet.dart';
import '../systems/economy.dart';
import 'sprites.dart';

/// Motor matic pemain (model 3D, 16 arah). Bisa diparkir atau dikendarai.
class Motorbike extends PositionComponent with HasGameReference<BatamGame>, IsoPlaced {
  Motorbike({required Vector2 position, required this.sprite, this.heading = 0}) : super(position: position) {
    _dir = sprite.spec.directionOf(heading);
  }

  /// Sprite motor 16 arah (lihat `model3d/models/motor.dart`).
  final DirectionalSprite sprite;

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

  /// Kecepatan gas & rem naik ke penuh (per detik) saat tombolnya ditahan:
  /// gas ±0,4 detik, rem ±0,25 detik. Saat dilepas turun lebih cepat.
  static const throttleRise = 2.5, brakeRise = 4.0, releaseRate = 8.0;

  /// Assist lajur: aktif bila arah setir dalam sudut ini dari arah jalan,
  /// dan seberapa kuat arah setir ditarik ke lajur (0..1).
  static const assistCone = 25 * math.pi / 180;
  static const assistBlend = 0.5;

  /// Faktor tampilan km/j per unit/detik (28 u/s ≈ 70 km/j).
  static const kmhPerUnit = 2.5;

  double heading;
  double speed = 0;

  /// Bukaan gas & tekanan rem 0..1 (naik bertahap selama tombol ditahan).
  double throttle = 0, brakeLevel = 0;

  /// Kemiringan badan (radian, positif = ke kanan) mengikuti laju belok.
  double lean = 0;

  /// Batas kecepatan sementara (ban bocor, mogok) dan sisa waktunya.
  double _capSpeed = 0, _capTime = 0;

  bool get restricted => _capTime > 0;

  /// Batasi kecepatan maksimal ke [cap] selama [seconds] detik.
  void restrict(double cap, double seconds) {
    _capSpeed = cap;
    _capTime = seconds;
  }

  bool ridden = false;

  double get speedKmh => speed.abs() * kmhPerUnit;

  late int _dir;
  final _smoke = <_Smoke>[];
  double _smokeIn = 0;
  final _rng = math.Random();

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

    final gas = ridden && c.gas, brake = ridden && c.brake && !gas;
    throttle = approach(throttle, gas ? 1 : 0, (gas ? throttleRise : releaseRate) * dt);
    brakeLevel = approach(brakeLevel, brake ? 1 : 0, (brake ? brakeRise : releaseRate) * dt);
    if (gas) {
      speed += driveAccel(throttle, speed, top) * ws.accelFactor * dt;
    } else if (brake) {
      // Rem mulai 30% lalu menguat; setelah berhenti, rem = mundur pelan.
      speed = speed > 0
          ? math.max(0, speed - brakeDecel * ws.brakeFactor * (0.3 + 0.7 * brakeLevel) * dt)
          : speed - accel * 0.5 * dt;
    } else {
      final d = drag * dt;
      speed = speed.abs() <= d ? 0 : speed - d * speed.sign;
    }
    if (speed > top) speed = math.max(top, speed - brakeDecel * dt);
    speed = speed.clamp(-maxReverse, maxSpeed * FuelGrade.turbo.speedBonus * math.max(1, ws.speedFactor));

    final before = heading;
    if (ridden) _steer(dt);

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

    final yawRate = dt > 0 ? wrapAngle(heading - before) / dt : 0.0;
    lean += ((ridden ? leanFor(yawRate, speed) : 0) - lean) * math.min(1, dt * 6);
    _dir = sprite.spec.directionWithHysteresis(_dir, heading);
    _updateSmoke(dt, running: ridden && !tank.isEmpty);
    // Jejak rem: roda belakang tergelincir saat rem keras di laju tinggi.
    if (ridden && brakeLevel > 0.5 && speed > 9) {
      game.skids.addPoint(_ground(MotorPoints.rearWheel));
    } else {
      game.skids.lift();
    }
    priority = isoDepth(position);
  }

  /// Setir mengikuti arah joystick di layar (dipetakan balik ke arah tanah),
  /// ditambah assist lajur ringan: di jalan, arah yang hampir searah jalan ditarik
  /// ke lajur kiri, dan tanpa joystick motor ikut lengkung jalan pelan-pelan.
  void _steer(double dt) {
    if (speed.abs() <= 0.1) return;
    final stick = screenDirToGround(game.controls.move);
    double? target = stick.length2 > 0.04 ? math.atan2(stick.y, stick.x) : null;
    var rate = turnRate * (speed.abs() / 8).clamp(minGrip, 1.0);
    if (speed > 4) {
      final hit = game.graph.nearest(position.toOffset(), maxDist: 8);
      if (hit != null && hit.distance <= hit.segment.edge.width / 2 + 0.5) {
        final lane = laneHeading(position.toOffset(), heading, hit.segment);
        if (wrapAngle((target ?? heading) - lane.road).abs() < assistCone) {
          if (target == null) rate *= 0.35;
          target = target == null ? lane.lane : blendAngle(target, lane.lane, assistBlend);
        }
      }
    }
    if (target == null) return;
    if (speed > 6 && wrapAngle(target - heading).abs() > math.pi / 2) speed -= sharpTurnDecel * dt;
    heading = wrapAngle(steerToward(heading, target, rate * dt));
  }

  /// Titik model tegak [p] → titik tanah di dunia (mengikuti arah motor).
  Offset _ground(V3 p) {
    final r = p.rotZ(heading);
    return Offset(position.x + r.x, position.y + r.y);
  }

  void _updateSmoke(double dt, {required bool running}) {
    for (final s in _smoke) {
      s.age += dt;
      s.at += s.drift * dt;
      s.z += 0.9 * dt;
    }
    _smoke.removeWhere((s) => s.age >= s.life);
    if (!running) return;
    // Langsam: kepul jarang; makin dalam gas, makin rapat.
    _smokeIn -= dt;
    while (_smokeIn <= 0 && _smoke.length < 40) {
      _smokeIn += 1 / (2.5 + 14 * throttle);
      final back = Offset(-math.cos(heading), -math.sin(heading));
      final side = Offset(-back.dy, back.dx) * (_rng.nextDouble() - 0.5);
      // Saat melaju asap cepat buyar, supaya tidak jadi deretan titik panjang.
      _smoke.add(
        _Smoke(
          _ground(MotorPoints.exhaust),
          MotorPoints.exhaust.z,
          back * 1.2 + side,
          0.7 + _rng.nextDouble() * 0.5,
          _Smoke.maxLife / (1 + speed.abs() / 8),
        ),
      );
    }
  }

  static final _smokeFill = Paint();
  static final _smokeInk = Paint();
  static final _glow = Paint();
  static const _smokeColor = Color(0xFFDCD8D0);

  @override
  void render(Canvas canvas) {
    final here = position.toOffset();
    // Bayangan lonjong sepanjang badan motor, di lantai.
    canvas.save();
    canvas.transform(isoMatrix);
    canvas.rotate(heading);
    drawShadow(canvas, const Offset(0.1, 0), 3.0, 0.9);
    canvas.restore();

    final depth = position.x + position.y;
    _renderSmoke(canvas, here, (s) => s.at.dx + s.at.dy < depth);
    sprite.render(
      canvas,
      direction: _dir,
      anim: ridden ? 'kendara' : 'parkir',
      frame: ridden ? motorLeanFrame(lean) : 0,
    );
    // Lampu rem menyala saat direm, bila buritan menghadap kamera.
    if (ridden && brakeLevel > 0.05 && math.cos(heading) + math.sin(heading) < 0) {
      final t = MotorPoints.tailLight.rotZ(heading);
      final at = IsoCamera.project(t);
      _glow.shader = Gradient.radial(at, 0.7, [
        const Color(0xFFFF5A3C).withValues(alpha: 0.85 * brakeLevel),
        const Color(0x00FF5A3C),
      ]);
      canvas.drawCircle(at, 0.7, _glow);
    }
    _renderSmoke(canvas, here, (s) => s.at.dx + s.at.dy >= depth);
  }

  void _renderSmoke(Canvas canvas, Offset here, bool Function(_Smoke) which) {
    for (final s in _smoke) {
      if (!which(s)) continue;
      final t = s.age / s.life;
      final c = isoOf(s.at - here) - Offset(0, s.z * IsoCamera.heightScale);
      final r = (0.18 + 0.4 * t) * s.size;
      final fade = 1 - t;
      _smokeInk.color = const Color(0xFF2B1D12).withValues(alpha: 0.25 * fade);
      canvas.drawCircle(c, r + 0.06, _smokeInk);
      _smokeFill.color = _smokeColor.withValues(alpha: 0.8 * fade);
      canvas.drawCircle(c, r, _smokeFill);
    }
  }
}

/// Kepul asap knalpot di titik tanah [at] setinggi [z]; hanyut ke [drift] dan
/// hilang setelah [life] detik.
class _Smoke {
  _Smoke(this.at, this.z, this.drift, this.size, this.life);

  /// Umur kepul saat motor diam (langsam).
  static const maxLife = 0.9;

  Offset at;
  double z;
  final Offset drift;
  final double size, life;
  double age = 0;
}

/// Sudut dinormalisasi ke -π..π.
double wrapAngle(double a) => (a + math.pi) % (2 * math.pi) - math.pi;

/// Putar [heading] ke [target] lewat jalan terpendek, paling banyak [maxStep] radian.
double steerToward(double heading, double target, double maxStep) {
  final d = wrapAngle(target - heading);
  return d.abs() <= maxStep ? heading + d : heading + maxStep * d.sign;
}

/// Sudut di antara [a] dan [b] (jalan terpendek), [t] = 0 → a, 1 → b.
double blendAngle(double a, double b, double t) => wrapAngle(a + wrapAngle(b - a) * t);

/// Geser [v] menuju [target] paling banyak [maxStep].
double approach(double v, double target, double maxStep) =>
    (target - v).abs() <= maxStep ? target : v + maxStep * (target - v).sign;

/// Percepatan gas (unit/detik²) pada bukaan [throttle]: tarikan paling kuat saat
/// pelan, melemah mendekati laju puncak [top].
double driveAccel(double throttle, double speed, double top) {
  final frac = top <= 0 ? 1.0 : (speed / top).clamp(0.0, 1.0);
  return Motorbike.accel * throttle * (1.3 - 0.7 * frac);
}

/// Kemiringan sasaran (positif = kanan) dari laju belok [yawRate] (rad/detik,
/// positif = belok kanan) dan laju [speed]: makin cepat & tajam, makin miring.
double leanFor(double yawRate, double speed) =>
    (yawRate * speed.abs() / 40).clamp(-1.0, 1.0) * motorMaxLean;

/// Arah jalan [seg] yang searah [heading] (`road`), dan arah menuju tengah lajur
/// kiri (`lane`; Indonesia lajur kiri, jalan satu arah = tengah jalan). Makin
/// jauh dari tengah lajur, makin besar koreksinya (paling banyak ±10°).
({double road, double lane}) laneHeading(Offset pos, double heading, RoadSegment seg) {
  var d = (seg.b - seg.a) / seg.length;
  if (d.dx * math.cos(heading) + d.dy * math.sin(heading) < 0) d = -d;
  final right = Offset(-d.dy, d.dx);
  final rel = pos - seg.closestPoint(pos);
  final laneOffset = seg.edge.oneway ? 0.0 : -seg.edge.width / 4;
  final err = rel.dx * right.dx + rel.dy * right.dy - laneOffset;
  final road = math.atan2(d.dy, d.dx);
  const maxFix = 10 * math.pi / 180;
  return (road: road, lane: wrapAngle(road - math.atan(err * 0.12).clamp(-maxFix, maxFix)));
}

/// Pandangan kamera ke depan (unit tanah) untuk motor ber-[heading] dan laju [speed].
Vector2 lookAheadOf(double heading, double speed) =>
    Vector2(math.cos(heading), math.sin(heading))..scale(speed.clamp(0.0, Motorbike.maxSpeed * 1.3) * 0.4);
