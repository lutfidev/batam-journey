import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../ui/palette.dart';
import '../batam_game.dart';
import '../iso.dart';
import '../map/road_layer.dart';
import '../model3d/models/slime.dart';
import '../model3d/raster.dart' show IsoCamera;
import '../sprites/sprite_sheet.dart';
import 'motorbike.dart';
import 'sprites.dart';

enum PlayerMode { walking, riding }

/// Pemain (slime jelly 3D). Saat naik motor, posisinya menempel ke motor
/// sehingga kamera cukup mengikuti satu komponen ini.
class Player extends PositionComponent with HasGameReference<BatamGame>, IsoPlaced {
  Player({required Vector2 position, required this.sprite}) : super(position: position);

  /// Sprite slime 16 arah (lihat `model3d/models/slime.dart`).
  final DirectionalSprite sprite;

  static const walkSpeed = 6.0;

  /// Percepatan & perlambatan jalan kaki (unit/detik²): ±0,2 detik sampai laju
  /// penuh, dan berhenti dalam ±0,17 detik (tidak meluncur).
  static const walkAccel = 30.0;
  static const walkDecel = 36.0;

  /// Kecepatan toleh (rad/detik): putar balik ±0,3 detik, melewati arah-arah antara.
  static const turnRate = 10.0;

  /// Di bawah laju ini (unit/detik) slime berhenti melompat setelah mendarat.
  static const hopMinSpeed = 0.6;

  /// Jarak maksimal (unit dunia) untuk bisa naik motor.
  static const boardRange = 5.0;

  PlayerMode mode = PlayerMode.walking;
  Motorbike? vehicle;

  /// Kecepatan jalan kaki di tanah (unit/detik).
  final Vector2 velocity = Vector2.zero();

  double _heading = math.pi / 2;
  int _dir = 4;

  /// Fase siklus lompat 0..1 (0 = di tanah); siklus diselesaikan sampai mendarat.
  double _hop = 0;
  bool _hopping = false;

  double _time = 0;
  double _blinkIn = 2, _blink = 0;
  final _puffs = <_Puff>[];
  final _rng = math.Random();

  bool get isRiding => mode == PlayerMode.riding;

  double get heading => _heading;

  void board(Motorbike bike) {
    vehicle = bike..ridden = true;
    mode = PlayerMode.riding;
    velocity.setZero();
    _hopping = false;
    _hop = 0;
    _puffs.clear();
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
    _heading = bike.heading;
    _dir = sprite.spec.directionOf(_heading);
    mode = PlayerMode.walking;
    vehicle = null;
  }

  @override
  void update(double dt) {
    if (isRiding) {
      position.setFrom(vehicle!.position);
      priority = isoDepth(position, 1);
      return;
    }
    _time += dt;
    // Joystick = arah layar; dipetakan balik ke arah tanah.
    final move = screenDirToGround(game.controls.move);
    final input = move.length2 > 0.0025;
    final m = move.length > 1 ? move.normalized() : move;
    approachVelocity(velocity, input ? m * walkSpeed : Vector2.zero(), (input ? walkAccel : walkDecel) * dt);
    if (velocity.length2 > 0) _walk(velocity * dt);

    // Toleh halus ke arah joystick, lewat arah-arah antara.
    if (input) _heading = wrapAngle(steerToward(_heading, math.atan2(m.y, m.x), turnRate * dt));
    _dir = sprite.spec.directionWithHysteresis(_dir, _heading);

    final speed = velocity.length;
    if (speed > hopMinSpeed) _hopping = true;
    if (_hopping) {
      // Makin cepat, makin sering melompat (langkah ±2,3 unit saat laju penuh).
      _hop += dt * (1.2 + 1.4 * speed / walkSpeed);
      if (_hop >= 1) {
        _hop -= 1;
        _land();
        if (speed <= hopMinSpeed) {
          _hopping = false;
          _hop = 0;
        }
      }
    }

    _blinkIn -= dt;
    _blink -= dt;
    if (_blinkIn <= 0) {
      _blink = 0.14;
      _blinkIn = 2.2 + _rng.nextDouble() * 2.8;
    }
    for (final p in _puffs) {
      p.age += dt;
    }
    _puffs.removeWhere((p) => p.age >= _Puff.life);
    priority = isoDepth(position);
  }

  /// Mendarat: dua kepul debu di kiri-kanan, sedikit di belakang.
  void _land() {
    final back = Offset(-math.cos(_heading), -math.sin(_heading)) * 0.5;
    final side = Offset(-math.sin(_heading), math.cos(_heading)) * 0.9;
    final at = position.toOffset() + back;
    _puffs
      ..add(_Puff(at + side, 0.8 + _rng.nextDouble() * 0.4))
      ..add(_Puff(at - side, 0.8 + _rng.nextDouble() * 0.4));
  }

  /// Gerak sejauh [d]; di pantai meluncur sepanjang garis pantai (coba X lalu Y).
  /// Bagian kecepatan yang tertahan air dinolkan.
  void _walk(Vector2 d) {
    final stuck = game.isWaterBlocked(position.toOffset());
    final steps = [d, Vector2(d.x, 0), Vector2(0, d.y)];
    var moved = false;
    for (var i = 0; i < steps.length && !moved; i++) {
      final next = position + steps[i];
      if (stuck || !game.isWaterBlocked(next.toOffset())) {
        position.setFrom(next);
        if (i == 1) velocity.y = 0;
        if (i == 2) velocity.x = 0;
        moved = true;
      }
    }
    if (!moved) velocity.setZero();
    game.clampToWorld(position);
  }

  static final _puffFill = Paint();
  static final _puffInk = Paint();
  static const _dust = Color(0xFFE2D1AC);

  @override
  void render(Canvas canvas) {
    if (isRiding) return;
    final here = position.toOffset();
    for (final p in _puffs) {
      final t = p.age / _Puff.life;
      final c = isoOf(p.at - here) - Offset(0, 0.5 * t);
      final r = (0.2 + 0.3 * t) * p.size;
      final fade = 1 - t * t;
      // Gumpalan awan dari tiga bulatan: garis tinta dulu, lalu isinya, supaya
      // garisnya hanya tampak di tepi luar.
      final blobs = [
        (c + Offset(-0.55 * r, 0.1 * r), 0.75 * r),
        (c + Offset(0.5 * r, 0.15 * r), 0.7 * r),
        (c - Offset(0, 0.3 * r), 0.8 * r),
      ];
      _puffInk.color = BColors.ink.withValues(alpha: 0.4 * fade);
      for (final (o, br) in blobs) {
        canvas.drawCircle(o, br + 0.07, _puffInk);
      }
      _puffFill.color = _dust.withValues(alpha: 0.95 * fade);
      for (final (o, br) in blobs) {
        canvas.drawCircle(o, br, _puffFill);
      }
    }

    final lift = _hopping ? slimeHop(_hop).lift : 0.0;
    final shadow = 1.9 - lift * 0.6;
    drawShadow(canvas, Offset.zero, shadow, shadow / 2);
    canvas.save();
    canvas.translate(0, -lift * IsoCamera.heightScale);
    if (_hopping) {
      sprite.render(canvas, direction: _dir, anim: 'jalan', frame: (_hop * sprite.spec.anim('jalan').frames).floor());
    } else if (_blink > 0) {
      sprite.render(canvas, direction: _dir, anim: 'kedip');
    } else {
      sprite.render(canvas, direction: _dir, anim: game.needs.sleepy ? 'lelah' : 'idle', time: _time);
    }
    canvas.restore();
  }
}

/// Ubah [v] menuju [target] paling banyak sejauh [maxDelta] (percepatan × dt).
void approachVelocity(Vector2 v, Vector2 target, double maxDelta) {
  final dx = target.x - v.x, dy = target.y - v.y;
  final d = math.sqrt(dx * dx + dy * dy);
  if (d <= maxDelta) {
    v.setFrom(target);
  } else {
    v.x += dx / d * maxDelta;
    v.y += dy / d * maxDelta;
  }
}

/// Kepul debu langkah di titik tanah [at]; membesar, naik, lalu pudar.
class _Puff {
  _Puff(this.at, this.size);

  static const life = 0.45;

  final Offset at;
  final double size;
  double age = 0;
}
