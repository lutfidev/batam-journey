import 'dart:math' as math;
import 'dart:ui';

import '../../ui/palette.dart';

/// Sprite prosedural (Canvas) yang meniru gambar desain OnFoot/Main.
/// Sementara sampai sprite sheet 8 arah dari Blender siap.
///
/// Semua koordinat di sini memakai piksel desain (layar 844×390);
/// pemanggil men-scale ke satuan dunia.

/// Arah tampak sprite. Arah kiri digambar dengan mencerminkan arah kanan.
enum Facing { down, downSide, side, upSide, up }

final _skin = Paint();
final _ink = Paint()..color = BColors.ink;
final _inkStroke = Paint()
  ..style = PaintingStyle.stroke
  ..color = BColors.ink
  ..strokeWidth = 2
  ..strokeJoin = StrokeJoin.round;

Paint _linear(Offset a, Offset b, List<Color> c, [List<double>? stops]) =>
    Paint()..shader = Gradient.linear(a, b, c, stops);

Paint _stroke(Color c, double w) => Paint()
  ..style = PaintingStyle.stroke
  ..color = c
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

void _skinAt(Rect r) {
  _skin.shader = Gradient.linear(r.topLeft, r.bottomRight, const [Color(0xFFD9A274), Color(0xFFB07A50)]);
}

/// Bayangan lonjong di bawah aktor (pusat di [c]).
void drawShadow(Canvas canvas, Offset c, double rx, double ry) {
  final r = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);
  canvas.drawOval(r, Paint()..shader = Gradient.radial(c, rx, const [Color(0x66000000), Color(0x00000000)]));
}

/// Pemain berjalan kaki. Titik (0,0) = kaki; tinggi ±145 px desain.
/// [phase] = fase langkah (radian), [lookX] = -1..1 arah pandang mendatar.
void drawWalker(Canvas canvas, Facing facing, double phase, double lookX, bool moving) {
  canvas.save();
  canvas.translate(-420, -276);
  drawShadow(canvas, const Offset(420, 276), 30, 7);

  final swing = moving ? 6 * math.sin(phase) : 0.0;
  final bob = moving ? 2 * math.sin(phase * 2).abs() : 0.0;
  canvas.translate(0, -bob);

  final jeans = _linear(const Offset(400, 0), const Offset(440, 0), const [Color(0xFF2A3550), Color(0xFF3D4C70)]);
  jeans
    ..style = PaintingStyle.stroke
    ..strokeWidth = 12
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(const Offset(410, 228), Offset(404 + swing, 272 + bob), jeans);
  canvas.drawLine(const Offset(430, 228), Offset(438 - swing, 270 + bob), jeans);
  final shoe = Paint()..color = const Color(0xFFF2F2F2);
  final shoeLine = _stroke(BColors.ink, 1.5);
  for (final c in [Offset(402 + swing, 274 + bob), Offset(441 - swing, 272 + bob)]) {
    final r = Rect.fromCenter(center: c, width: 18, height: 10);
    canvas.drawOval(r, shoe);
    canvas.drawOval(r, shoeLine);
  }

  // Lengan di belakang badan saat tampak belakang.
  final arm = _stroke(BColors.hijauAksi, 11);
  final armL = Path()
    ..moveTo(398, 190)
    ..lineTo(386, 222)
    ..lineTo(392 - swing * 0.6, 240);
  final armR = Path()
    ..moveTo(442, 190)
    ..lineTo(454, 214)
    ..lineTo(450 + swing * 0.6, 236);

  final torso = Path()
    ..moveTo(398, 186)
    ..quadraticBezierTo(420, 174, 442, 186)
    ..lineTo(446, 234)
    ..lineTo(394, 234)
    ..close();
  final jacket = _linear(
    const Offset(398, 0),
    const Offset(446, 0),
    const [Color(0xFF2F7A45), Color(0xFF4DB06B), Color(0xFF2F7A45)],
    const [0, 0.6, 1],
  );

  if (facing == Facing.up) {
    canvas.drawPath(armL, arm);
    canvas.drawPath(armR, arm);
  }
  canvas.drawPath(torso, jacket);
  canvas.drawPath(torso, _inkStroke);
  if (facing != Facing.up) {
    canvas.drawLine(const Offset(420, 182), const Offset(420, 234), _stroke(const Color(0xFF24572F), 2));
  }
  canvas.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTWH(398, 226, 48, 8), const Radius.circular(3)),
    Paint()..color = const Color(0xFF24572F),
  );
  if (facing != Facing.up) {
    canvas.drawPath(armL, arm);
    canvas.drawPath(armR, arm);
    _skinAt(const Rect.fromLTWH(380, 230, 76, 20));
    canvas.drawCircle(Offset(392 - swing * 0.6, 242), 6, _skin);
    canvas.drawCircle(Offset(450 + swing * 0.6, 238), 6, _skin);
  }

  _skinAt(const Rect.fromLTWH(403, 137, 34, 34));
  canvas.drawRect(const Rect.fromLTWH(414, 168, 12, 10), _skin);
  canvas.drawOval(
    Rect.fromCenter(center: const Offset(403, 156), width: 6, height: 8),
    Paint()..color = const Color(0xFFB07A50),
  );
  canvas.drawOval(
    Rect.fromCenter(center: const Offset(437, 156), width: 6, height: 8),
    Paint()..color = const Color(0xFFB07A50),
  );
  canvas.drawCircle(const Offset(420, 154), 17, _skin);

  if (facing == Facing.up) {
    // Tampak belakang: rambut menutup kepala.
    canvas.drawCircle(const Offset(420, 152), 17, _ink);
  } else {
    final hair = Path()
      ..moveTo(403, 152)
      ..quadraticBezierTo(402, 134, 420, 133)
      ..quadraticBezierTo(438, 134, 437, 152)
      ..quadraticBezierTo(432, 142, 420, 142)
      ..quadraticBezierTo(410, 142, 403, 152)
      ..close();
    canvas.drawPath(hair, _ink);
    final ex = lookX * 4;
    canvas.drawCircle(Offset(414 + ex, 156), 2.2, _ink);
    canvas.drawCircle(Offset(426 + ex, 156), 2.2, _ink);
    final smile = Path()
      ..moveTo(414 + ex, 163)
      ..quadraticBezierTo(420 + ex, 167, 426 + ex, 163);
    canvas.drawPath(smile, _stroke(BColors.ink, 1.8));
  }
  canvas.restore();
}

/// Motor matic. Titik (0,0) = tengah bawah (tanah).
/// Tampak samping menghadap kanan; balik dengan scale(-1,1) untuk kiri.
void drawMotor(Canvas canvas, Facing facing, {required bool rider, double wheelSpin = 0}) {
  switch (facing) {
    case Facing.side:
    case Facing.downSide:
    case Facing.upSide:
      _motorSide(canvas, rider, wheelSpin);
    case Facing.down:
    case Facing.up:
      _motorFrontBack(canvas, facing == Facing.down, rider);
  }
}

final _body = [const Color(0xFF3A72B8), const Color(0xFF173F70)];

void _motorSide(Canvas canvas, bool rider, double spin) {
  canvas.save();
  canvas.translate(-626, -271);
  drawShadow(canvas, const Offset(626, 272), 64, 8);

  final tyre = Paint()..color = const Color(0xFF1F1F1F);
  final rim = Paint()..color = const Color(0xFFA7AFB8);
  final spoke = _stroke(const Color(0xFF6B737C), 2);
  for (final c in const [Offset(592, 256), Offset(660, 256)]) {
    canvas.drawCircle(c, 15, tyre);
    canvas.drawCircle(c, 7, rim);
    canvas.drawLine(c + Offset.fromDirection(spin, 6), c - Offset.fromDirection(spin, 6), spoke);
  }

  // Box ojek di belakang.
  final box = RRect.fromRectAndRadius(const Rect.fromLTWH(560, 196, 32, 28), const Radius.circular(4));
  canvas.drawRRect(box, Paint()..color = BColors.oranye);
  canvas.drawRRect(box, _inkStroke);

  if (rider) {
    final legs = _stroke(const Color(0xFF2F3D5E), 11);
    final leg = Path()
      ..moveTo(604, 226)
      ..lineTo(628, 232)
      ..lineTo(634, 250);
    canvas.drawPath(leg, legs);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(638, 252), width: 16, height: 8),
      Paint()..color = const Color(0xFFF2F2F2),
    );
  }

  final body = Path()
    ..moveTo(574, 250)
    ..quadraticBezierTo(572, 234, 586, 230)
    ..lineTo(626, 232)
    ..quadraticBezierTo(634, 234, 634, 246)
    ..lineTo(644, 246)
    ..lineTo(652, 222)
    ..quadraticBezierTo(656, 212, 664, 216)
    ..lineTo(672, 242)
    ..quadraticBezierTo(674, 254, 666, 256)
    ..lineTo(672, 256)
    ..quadraticBezierTo(660, 242, 648, 254)
    ..lineTo(606, 254)
    ..quadraticBezierTo(594, 240, 580, 254)
    ..close();
  canvas.drawPath(body, _linear(const Offset(0, 212), const Offset(0, 256), _body));
  canvas.drawPath(body, _inkStroke);
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(584, 224, 44, 8), const Radius.circular(4)), _ink);
  // Lampu depan.
  canvas.drawCircle(const Offset(668, 224), 4, Paint()..color = const Color(0xFFFFF3B0));

  if (rider) {
    final torso = Path()
      ..moveTo(596, 228)
      ..lineTo(600, 192)
      ..quadraticBezierTo(612, 184, 622, 194)
      ..lineTo(618, 228)
      ..close();
    canvas.drawPath(
      torso,
      _linear(const Offset(596, 0), const Offset(622, 0), const [Color(0xFF2F7A45), Color(0xFF4DB06B)]),
    );
    canvas.drawPath(torso, _inkStroke);
    final arm = Path()
      ..moveTo(614, 198)
      ..lineTo(638, 212)
      ..lineTo(654, 218);
    canvas.drawPath(arm, _stroke(BColors.hijauAksi, 9));
    _skinAt(const Rect.fromLTWH(598, 160, 28, 28));
    canvas.drawCircle(const Offset(656, 218), 4.5, _skin);
    canvas.drawCircle(const Offset(612, 174), 13, _skin);
    _helmet(canvas, const Offset(612, 172), visorRight: true);
  }
  canvas.restore();
}

void _motorFrontBack(Canvas canvas, bool front, bool rider) {
  canvas.save();
  drawShadow(canvas, const Offset(0, 1), 26, 7);
  final tyre = Paint()..color = const Color(0xFF1F1F1F);
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-6, -30, 12, 30), const Radius.circular(6)), tyre);

  final box = RRect.fromRectAndRadius(const Rect.fromLTWH(-18, -86, 36, 28), const Radius.circular(4));
  void drawBox() {
    canvas.drawRRect(box, Paint()..color = BColors.oranye);
    canvas.drawRRect(box, _inkStroke);
  }

  if (front) drawBox();

  if (rider) {
    final torso = RRect.fromRectAndRadius(const Rect.fromLTWH(-15, -100, 30, 42), const Radius.circular(9));
    canvas.drawRRect(
      torso,
      _linear(
        const Offset(-15, 0),
        const Offset(15, 0),
        const [Color(0xFF2F7A45), Color(0xFF4DB06B), Color(0xFF2F7A45)],
        const [0, 0.55, 1],
      ),
    );
    canvas.drawRRect(torso, _inkStroke);
  }

  final shield = Path()
    ..moveTo(-16, -22)
    ..lineTo(-14, -56)
    ..quadraticBezierTo(0, -64, 14, -56)
    ..lineTo(16, -22)
    ..quadraticBezierTo(0, -16, -16, -22)
    ..close();
  canvas.drawPath(shield, _linear(const Offset(0, -64), const Offset(0, -16), _body));
  canvas.drawPath(shield, _inkStroke);
  canvas.drawLine(const Offset(-26, -60), const Offset(26, -60), _stroke(BColors.ink, 5));
  if (front) {
    canvas.drawCircle(const Offset(0, -46), 6, Paint()..color = const Color(0xFFFFF3B0));
    canvas.drawCircle(const Offset(0, -46), 6, _stroke(BColors.ink, 1.5));
  } else {
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(-9, -32, 18, 6), const Radius.circular(3)),
      Paint()..color = BColors.atapMerah,
    );
  }

  if (rider) {
    final hands = Paint()..color = const Color(0xFFC48C60);
    canvas.drawLine(const Offset(-12, -92), const Offset(-22, -62), _stroke(BColors.hijauAksi, 8));
    canvas.drawLine(const Offset(12, -92), const Offset(22, -62), _stroke(BColors.hijauAksi, 8));
    canvas.drawCircle(const Offset(-23, -60), 4, hands);
    canvas.drawCircle(const Offset(23, -60), 4, hands);
    _skinAt(const Rect.fromLTWH(-13, -126, 26, 26));
    canvas.drawCircle(const Offset(0, -112), 13, _skin);
    _helmet(canvas, const Offset(0, -114), visorFront: front);
  }
  if (!front) drawBox();
  canvas.restore();
}

void _helmet(Canvas canvas, Offset c, {bool visorRight = false, bool visorFront = false}) {
  final shell = Path()
    ..addArc(Rect.fromCircle(center: c, radius: 15), 3.3, 2.82)
    ..close();
  canvas.drawPath(shell, Paint()..color = BColors.hijauAksi);
  canvas.drawPath(shell, _inkStroke);
  if (visorRight) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(c.dx + 4, c.dy - 2, 10, 7), const Radius.circular(3)),
      Paint()..color = const Color(0xFF2B3A4A),
    );
  } else if (visorFront) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(c.dx - 10, c.dy - 2, 20, 7), const Radius.circular(3)),
      Paint()..color = const Color(0xFF2B3A4A),
    );
  } else {
    canvas.drawCircle(c, 15, Paint()..color = BColors.hijauAksi);
    canvas.drawCircle(c, 15, _inkStroke);
  }
}
