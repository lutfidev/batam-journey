import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../ui/palette.dart';

/// Sprite prosedural (Canvas) untuk motor dan slime 2D yang menungganginya,
/// sementara sampai motor 3D (langkah 4). Slime jalan kaki sudah 3D
/// (`model3d/models/slime.dart`); [drawSlime] masih dipakai pengendara & layar rumah.
///
/// Semua koordinat di sini memakai piksel desain (layar 844×390);
/// pemanggil men-scale ke satuan dunia.

/// Arah tampak sprite. Arah kiri digambar dengan mencerminkan arah kanan.
enum Facing { down, downSide, side, upSide, up }

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

/// Bayangan lonjong di bawah aktor (pusat di [c]).
void drawShadow(Canvas canvas, Offset c, double rx, double ry) {
  final r = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);
  canvas.drawOval(r, Paint()..shader = Gradient.radial(c, rx, const [Color(0x66000000), Color(0x00000000)]));
}

const _slimeLight = Color(0xFF9FD3FA);
const _slimeMid = Color(0xFF4F95DC);
const _slimeDark = BColors.biruPemain;
const _slimeW = 100.0, _slimeH = 86.0;

/// Ukuran slime saat duduk di jok motor.
const _riderScale = 0.5;

/// Pemain: slime jelly bermata dua. Titik (0,0) = tengah bawah (tanah);
/// ukuran ±100×86 px desain.
/// [lookX]/[lookY] = arah pandang (-1..1, y ke bawah layar); menghadap atas
/// (`lookY < -0,6`) tampak belakang tanpa mata. [phase] menggerakkan lompatan
/// saat [moving], atau napas pelan saat diam. [shadow] dimatikan saat duduk di motor.
void drawSlime(
  Canvas canvas, {
  double lookX = 0,
  double lookY = 1,
  double phase = 0,
  bool moving = false,
  bool helmet = false,
  bool shadow = true,
}) {
  final t = math.sin(phase).abs();
  final hop = moving ? 12 * t : 0.0;
  // Melar saat melayang, gepeng saat mendarat; diam = bernapas.
  final sy = moving ? 0.88 + 0.24 * t : 1 + 0.035 * math.sin(phase);
  final sx = 1 / math.sqrt(sy);
  if (shadow) drawShadow(canvas, Offset.zero, 46 - hop, 9 - hop * 0.3);

  canvas.save();
  canvas.translate(0, -hop);
  canvas.scale(sx, sy);

  const w = _slimeW / 2, h = _slimeH;
  final body = Path()
    ..moveTo(-w, -9)
    ..cubicTo(-w - 2, -h * 0.55, -w * 0.62, -h, 0, -h)
    ..cubicTo(w * 0.62, -h, w + 2, -h * 0.55, w, -9)
    ..quadraticBezierTo(w, 0, w - 12, 0)
    ..lineTo(-w + 12, 0)
    ..quadraticBezierTo(-w, 0, -w, -9)
    ..close();
  canvas.drawPath(
    body,
    Paint()
      ..shader = Gradient.radial(
        Offset(-14 - lookX * 4, -h * 0.68),
        h * 0.95,
        const [_slimeLight, _slimeMid, _slimeDark],
        const [0, 0.5, 1],
      ),
  );
  // Bayangan dalam di dasar supaya terlihat kenyal & bervolume.
  canvas.save();
  canvas.clipPath(body);
  canvas.drawOval(
    Rect.fromCenter(center: const Offset(0, 2), width: w * 2.2, height: 26),
    Paint()..color = const Color(0x401D2F5C),
  );
  canvas.restore();
  canvas.drawPath(body, _stroke(BColors.ink, 2.5));

  // Kilap jelly.
  final shine = Paint()..color = const Color(0xD9FFFFFF);
  canvas.save();
  canvas.translate(-w * 0.5, -h * 0.72);
  canvas.rotate(-0.6);
  canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 20, height: 11), shine);
  canvas.restore();
  canvas.drawCircle(Offset(-w * 0.2, -h * 0.86), 3, shine);

  final back = lookY < -0.6;
  if (!back) _slimeFace(canvas, lookX.clamp(-1.0, 1.0), lookY.clamp(-1.0, 1.0));
  if (helmet) _slimeHelmet(canvas);
  canvas.restore();
}

void _slimeFace(Canvas canvas, double lx, double ly) {
  // Saat menoleh ke samping, wajah bergeser ke sisi itu dan mata yang jauh mengecil.
  final shift = lx * 16;
  final ey = -42.0 + ly * 4;
  final white = Paint()..color = const Color(0xFFFFFFFF);
  for (final side in const [-1.0, 1.0]) {
    final far = side * lx < 0 ? 1 - lx.abs() * 0.35 : 1.0;
    final c = Offset(side * 15 * (1 - lx.abs() * 0.3) + shift, ey);
    final eye = Rect.fromCenter(center: c, width: 17 * far, height: 21 * far);
    canvas.drawOval(eye, white);
    canvas.drawOval(eye, _stroke(BColors.ink, 2));
    final pupil = c + Offset(lx * 3.5, ly * 3 + 1);
    canvas.drawCircle(pupil, 5.5 * far, _ink);
    canvas.drawCircle(pupil + const Offset(-1.8, -2), 1.8 * far, white);
  }
  // Pipi merona & senyum kecil.
  final blush = Paint()..color = const Color(0x66F28C9A);
  for (final side in const [-1.0, 1.0]) {
    canvas.drawOval(Rect.fromCenter(center: Offset(side * 25 + shift, ey + 15), width: 11, height: 6), blush);
  }
  final smile = Path()
    ..moveTo(-5 + shift, ey + 14)
    ..quadraticBezierTo(shift, ey + 19, 5 + shift, ey + 14);
  canvas.drawPath(smile, _stroke(BColors.ink, 2));
}

/// Helm ojek hijau yang menutup ubun-ubun slime.
void _slimeHelmet(Canvas canvas) {
  const top = -_slimeH - 4;
  final shell = Path()
    ..addArc(const Rect.fromLTWH(-40, top, 80, 64), math.pi, math.pi)
    ..close();
  canvas.drawPath(shell, _linear(const Offset(-40, 0), const Offset(40, 0), const [Color(0xFF4DB06B), BColors.hijauAksi]));
  canvas.drawPath(shell, _inkStroke);
  canvas.drawLine(const Offset(-14, top + 8), const Offset(-24, top + 22), _stroke(const Color(0x99FFFFFF), 4));
  final brim = RRect.fromRectAndRadius(const Rect.fromLTWH(-44, top + 29, 88, 7), const Radius.circular(3.5));
  canvas.drawRRect(brim, Paint()..color = const Color(0xFF24572F));
  canvas.drawRRect(brim, _inkStroke);
}

/// Motor matic. Titik (0,0) = tengah bawah (tanah).
/// Arah kanan/kanan-bawah/kanan-atas; balik dengan scale(-1,1) untuk kiri.
void drawMotor(Canvas canvas, Facing facing, {required bool rider, double wheelSpin = 0}) {
  switch (facing) {
    case Facing.side:
      _motorSide(canvas, rider, wheelSpin);
    case Facing.downSide:
      _motorSide(canvas, rider, wheelSpin, slant: 0.42);
    case Facing.upSide:
      _motorSide(canvas, rider, wheelSpin, slant: -0.42);
    case Facing.down:
    case Facing.up:
      _motorFrontBack(canvas, facing == Facing.down, rider);
  }
}

final _body = [const Color(0xFF3A72B8), const Color(0xFF173F70)];

/// Tampak samping. [slant] ≠ 0 = tampak 3/4: badan dipendekkan dan roda depan
/// lebih rendah (slant > 0, menuju kamera) atau lebih tinggi (slant < 0, menjauh).
void _motorSide(Canvas canvas, bool rider, double spin, {double slant = 0}) {
  final squeeze = slant == 0 ? 1.0 : 0.74;
  final toward = slant >= 0;
  // Titik desain tampak samping → titik setelah dipendekkan & dimiringkan.
  Offset tf(Offset p) {
    final x = (p.dx - 626) * squeeze;
    return Offset(x, p.dy - 271 + slant * x);
  }

  drawShadow(canvas, const Offset(0, 1), 64 * squeeze, 8 + slant.abs() * 14);

  final matrix = Float64List.fromList([
    squeeze, slant * squeeze, 0, 0, //
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
  ]);
  void machine(void Function() part) {
    canvas.save();
    canvas.transform(matrix);
    canvas.translate(-626, -271);
    part();
    canvas.restore();
  }

  final box = RRect.fromRectAndRadius(const Rect.fromLTWH(560, 196, 32, 28), const Radius.circular(4));
  void drawBox() => machine(() {
    canvas.drawRRect(box, Paint()..color = BColors.oranye);
    canvas.drawRRect(box, _inkStroke);
  });

  machine(() {
    final tyre = Paint()..color = const Color(0xFF1F1F1F);
    final rim = Paint()..color = const Color(0xFFA7AFB8);
    final spoke = _stroke(const Color(0xFF6B737C), 2);
    for (final c in const [Offset(592, 256), Offset(660, 256)]) {
      canvas.drawCircle(c, 15, tyre);
      canvas.drawCircle(c, 7, rim);
      canvas.drawLine(c + Offset.fromDirection(spin, 6), c - Offset.fromDirection(spin, 6), spoke);
    }
  });

  // Box ojek di belakang; saat motor menjauh, box berada di depan pengendara.
  if (toward) drawBox();

  machine(() {
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
    if (toward) {
      canvas.drawCircle(const Offset(668, 224), 4, Paint()..color = const Color(0xFFFFF3B0));
    } else {
      // Lampu belakang terlihat saat motor menjauh.
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(572, 236, 7, 8), const Radius.circular(2)),
        Paint()..color = BColors.atapMerah,
      );
    }
  });

  if (rider) {
    final seat = tf(const Offset(604, 230));
    final grip = tf(const Offset(654, 218));
    // Tangan jelly menjulur ke setang.
    final arm = Path()
      ..moveTo(seat.dx + 12, seat.dy - 20)
      ..quadraticBezierTo(seat.dx + 28, seat.dy - 18, grip.dx, grip.dy);
    canvas.drawPath(arm, _stroke(BColors.ink, 10));
    canvas.drawPath(arm, _stroke(_slimeMid, 6));
    canvas.save();
    canvas.translate(seat.dx, seat.dy);
    canvas.scale(_riderScale);
    drawSlime(canvas, lookX: 1, lookY: slant == 0 ? 0 : (toward ? 0.6 : -0.4), helmet: true, shadow: false);
    canvas.restore();
    canvas.drawCircle(grip, 4.5, Paint()..color = _slimeMid);
    canvas.drawCircle(grip, 4.5, _stroke(BColors.ink, 1.5));
  }
  if (!toward) drawBox();
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
    canvas.save();
    canvas.translate(0, -58);
    canvas.scale(_riderScale);
    drawSlime(canvas, lookY: front ? 1 : -1, helmet: true, shadow: false);
    canvas.restore();
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
    // Tangan jelly memegang setang.
    for (final x in const [-23.0, 23.0]) {
      canvas.drawCircle(Offset(x, -60), 4.5, Paint()..color = _slimeMid);
      canvas.drawCircle(Offset(x, -60), 4.5, _stroke(BColors.ink, 1.5));
    }
  }
  if (!front) drawBox();
  canvas.restore();
}
