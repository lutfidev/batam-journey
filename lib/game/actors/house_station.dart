import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, FontWeight;

import '../../ui/palette.dart';
import '../batam_game.dart';
import '../iso.dart';
import '../systems/housing.dart';

/// Rumah di pinggir jalan: kos Bu Ros, rumah dijual, atau rumah milikmu.
/// Papan kecil di depannya berubah: KOS / DIJUAL / RUMAHMU.
/// Titik (0,0) = tengah depan halaman.
class HouseStation extends PositionComponent with HasGameReference<BatamGame>, IsoPlaced {
  HouseStation({required Vector2 position, required this.homeId, required this.roof, required this.title})
    : super(position: position, priority: isoDepth(position, -12));

  final String homeId;
  final Color roof;
  final String title;

  bool get isKos => homeId == Housing.kosId;

  /// Jarak (unit dunia) untuk bisa masuk / melihat rumah.
  static const serviceRange = 11.0;

  static final _yard = Paint()..color = const Color(0xFFA9D58F);
  static final _yardEdge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.4
    ..color = BColors.hutanGelap;
  static final _wall = Paint()..color = const Color(0xFFFBF1DE);
  static final _glass = Paint()..color = const Color(0xFF86ADC2);
  static final _door = Paint()..color = const Color(0xFF8E6B4A);
  static final _fence = Paint()..color = const Color(0xFFFFFFFF);
  static final _inkLine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.25
    ..color = BColors.ink;

  static final _signs = <String, TextPainter>{};

  static TextPainter _text(String s) => _signs[s] ??= TextPainter(
    text: TextSpan(
      text: s,
      style: const TextStyle(fontSize: 1.5, fontWeight: FontWeight.w900, color: Color(0xFFFFFFFF)),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  /// Sprite lama (tampak 3/4) dipusatkan di tengah lantai iso sampai diganti model 3D.
  @override
  Offset get spriteOffset => buildingSpriteOffset;

  @override
  void render(Canvas canvas) {
    final yard = RRect.fromRectAndRadius(const Rect.fromLTWH(-8, -12, 16, 12), const Radius.circular(1));
    canvas.drawRRect(yard, _yard);
    canvas.drawRRect(yard, _yardEdge);

    // Dinding & atap pelana (tampak 3/4).
    canvas.drawRect(const Rect.fromLTWH(-6, -10.5, 12, 6), _wall);
    final roofPath = Path()
      ..moveTo(-7, -10.2)
      ..lineTo(0, -14.5)
      ..lineTo(7, -10.2)
      ..close();
    canvas.drawPath(roofPath, Paint()..color = roof);
    canvas.drawPath(roofPath, _inkLine);
    canvas.drawRect(const Rect.fromLTWH(-6, -10.5, 12, 6), _inkLine);
    canvas.drawRect(const Rect.fromLTWH(-4.6, -9, 2.6, 2), _glass);
    canvas.drawRect(const Rect.fromLTWH(2, -9, 2.6, 2), _glass);
    canvas.drawRect(const Rect.fromLTWH(-1, -8.6, 2, 4.1), _door);

    // Pagar depan.
    canvas.drawRect(const Rect.fromLTWH(-8, -2.2, 6, 0.5), _fence);
    canvas.drawRect(const Rect.fromLTWH(2, -2.2, 6, 0.5), _fence);

    // Papan status.
    final (label, color) = _status();
    final tp = _text(label);
    final sign = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(-5.2, -3.6), width: tp.width + 1.2, height: 2),
      const Radius.circular(0.4),
    );
    canvas.drawRRect(sign, Paint()..color = color);
    canvas.drawRRect(sign, _inkLine);
    tp.paint(canvas, Offset(-5.2 - tp.width / 2, -3.6 - tp.height / 2));
  }

  (String, Color) _status() {
    final h = game.housing;
    if (isKos) return ('KOS', BColors.oranye);
    if (h.owned.value.contains(homeId)) return ('RUMAHMU', BColors.hijauAksi);
    return ('DIJUAL', BColors.atapMerah);
  }
}
