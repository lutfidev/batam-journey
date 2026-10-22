import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../palette.dart';

/// Gambar-gambar bersama untuk minimap dan peta penuh (layar "Peta Batam").

/// Kategori pin di peta, sesuai chip filter desain.
enum PinKind {
  fuel('SPBU', Color(0xFFD62828), 'fuel'),
  ferry('Pelabuhan', BColors.biruPemain, 'ferry_terminal'),
  hospital('Rumah Sakit', Color(0xFF7B5EA7), 'hospital'),
  market('Pasar', BColors.oranye, 'marketplace'),
  house('Rumah dijual', BColors.hijauAksi, 'house_sale'),
  home('Rumahku', BColors.biruPemain, 'home'),
  business('Usaha', Color(0xFF7B5EA7), 'business');

  const PinKind(this.label, this.color, this.poiType);

  final String label;
  final Color color;
  final String poiType;

  static PinKind? forPoi(String type) {
    for (final k in values) {
      if (k.poiType == type) return k;
    }
    return null;
  }
}

/// Gambar peta Batam sehingga titik dunia [center] berada di [screenCenter],
/// dengan [scale] piksel layar per satuan dunia.
void drawMapImage(Canvas canvas, ui.Image image, Size worldSize, Offset center, double scale, Offset screenCenter) {
  final dst = Rect.fromLTWH(
    screenCenter.dx - center.dx * scale,
    screenCenter.dy - center.dy * scale,
    worldSize.width * scale,
    worldSize.height * scale,
  );
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    dst,
    Paint()..filterQuality = FilterQuality.medium,
  );
}

/// Garis rute biru. [dashed] untuk pratinjau rute di peta penuh.
void drawRoute(Canvas canvas, List<Offset> screenPts, {double width = 5, bool dashed = false}) {
  if (screenPts.length < 2) return;
  final halo = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width + 3
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = const Color(0xDDFFFFFF);
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = BColors.biruPemain;
  final path = Path()..addPolygon(screenPts, false);
  canvas.drawPath(path, halo);
  if (!dashed) {
    canvas.drawPath(path, line);
    return;
  }
  for (final metric in path.computeMetrics()) {
    for (var d = 0.0; d < metric.length; d += 17) {
      canvas.drawPath(metric.extractPath(d, math.min(d + 10, metric.length)), line);
    }
  }
}

/// Panah posisi pemain (desain: "M12 2l7 19-7-4-7 4z"), [heading] 0 = timur.
void drawPlayerArrow(Canvas canvas, Offset at, double heading, {double size = 20}) {
  final s = size / 24;
  canvas.save();
  canvas.translate(at.dx, at.dy);
  canvas.rotate(heading + math.pi / 2);
  canvas.scale(s);
  canvas.translate(-12, -12);
  final p = Path()
    ..moveTo(12, 2)
    ..lineTo(19, 21)
    ..lineTo(12, 17)
    ..lineTo(5, 21)
    ..close();
  canvas.drawPath(p, Paint()..color = BColors.biruPemain);
  canvas.drawPath(
    p,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFFFFFFF),
  );
  canvas.restore();
}

/// Pin tetesan (bulat dengan ujung di bawah) yang ujungnya tepat di [tip].
void drawPin(Canvas canvas, Offset tip, Color color, {PinKind? kind, double r = 14}) {
  final c = tip - Offset(0, r * 1.45);
  final body = Path()
    ..addOval(Rect.fromCircle(center: c, radius: r))
    ..moveTo(c.dx - r * 0.7, c.dy + r * 0.7)
    ..lineTo(tip.dx, tip.dy)
    ..lineTo(c.dx + r * 0.7, c.dy + r * 0.7)
    ..close();
  canvas.drawPath(body.shift(const Offset(0, 2)), Paint()..color = BColors.ink);
  canvas.drawPath(body, Paint()..color = color);
  canvas.drawPath(
    body,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = const Color(0xFFFFFFFF),
  );
  _glyph(canvas, c, r * 0.62, kind);
}

void _glyph(Canvas canvas, Offset c, double h, PinKind? kind) {
  final w = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = h * 0.28
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = const Color(0xFFFFFFFF);
  final p = Path();
  switch (kind) {
    case PinKind.fuel:
      p
        ..addRect(Rect.fromLTRB(c.dx - h * 0.6, c.dy - h * 0.75, c.dx + h * 0.2, c.dy + h * 0.75))
        ..moveTo(c.dx + h * 0.2, c.dy - h * 0.2)
        ..lineTo(c.dx + h * 0.65, c.dy)
        ..lineTo(c.dx + h * 0.65, c.dy + h * 0.5);
    case PinKind.ferry:
      p
        ..moveTo(c.dx - h * 0.8, c.dy + h * 0.1)
        ..lineTo(c.dx + h * 0.8, c.dy + h * 0.1)
        ..lineTo(c.dx + h * 0.45, c.dy + h * 0.7)
        ..lineTo(c.dx - h * 0.45, c.dy + h * 0.7)
        ..close()
        ..moveTo(c.dx, c.dy + h * 0.1)
        ..lineTo(c.dx, c.dy - h * 0.8)
        ..lineTo(c.dx + h * 0.5, c.dy - h * 0.2);
    case PinKind.hospital:
      p
        ..moveTo(c.dx, c.dy - h * 0.75)
        ..lineTo(c.dx, c.dy + h * 0.75)
        ..moveTo(c.dx - h * 0.75, c.dy)
        ..lineTo(c.dx + h * 0.75, c.dy);
    case PinKind.market:
      p
        ..moveTo(c.dx - h * 0.75, c.dy - h * 0.25)
        ..lineTo(c.dx + h * 0.75, c.dy - h * 0.25)
        ..lineTo(c.dx + h * 0.55, c.dy + h * 0.7)
        ..lineTo(c.dx - h * 0.55, c.dy + h * 0.7)
        ..close()
        ..moveTo(c.dx - h * 0.35, c.dy - h * 0.25)
        ..arcToPoint(Offset(c.dx + h * 0.35, c.dy - h * 0.25), radius: Radius.circular(h * 0.4));
    case PinKind.business:
      p
        ..addRect(Rect.fromLTRB(c.dx - h * 0.7, c.dy - h * 0.2, c.dx + h * 0.7, c.dy + h * 0.7))
        ..moveTo(c.dx - h * 0.8, c.dy - h * 0.2)
        ..lineTo(c.dx - h * 0.55, c.dy - h * 0.7)
        ..lineTo(c.dx + h * 0.55, c.dy - h * 0.7)
        ..lineTo(c.dx + h * 0.8, c.dy - h * 0.2);
    case PinKind.house:
    case PinKind.home:
      p
        ..moveTo(c.dx - h * 0.75, c.dy - h * 0.05)
        ..lineTo(c.dx, c.dy - h * 0.7)
        ..lineTo(c.dx + h * 0.75, c.dy - h * 0.05)
        ..moveTo(c.dx - h * 0.55, c.dy - h * 0.2)
        ..lineTo(c.dx - h * 0.55, c.dy + h * 0.7)
        ..lineTo(c.dx + h * 0.55, c.dy + h * 0.7)
        ..lineTo(c.dx + h * 0.55, c.dy - h * 0.2);
    case null:
      // Bendera tujuan.
      p
        ..moveTo(c.dx - h * 0.5, c.dy + h * 0.8)
        ..lineTo(c.dx - h * 0.5, c.dy - h * 0.8)
        ..lineTo(c.dx + h * 0.7, c.dy - h * 0.45)
        ..lineTo(c.dx - h * 0.5, c.dy - h * 0.1);
  }
  canvas.drawPath(p, w);
}
