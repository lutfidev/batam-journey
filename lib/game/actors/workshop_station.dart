import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, FontWeight;

import '../../ui/palette.dart';
import 'sprites.dart';

/// Bengkel motor di pinggir jalan: bangunan kecil, rolling door terbuka,
/// papan "BENGKEL", tumpukan ban. Titik (0,0) = tengah depan lantai.
class WorkshopStation extends PositionComponent {
  WorkshopStation({required Vector2 position, required this.name})
    // Prioritas = tepi belakang, supaya pemain/motor di depannya tetap terlihat.
    : super(position: position, priority: position.y.toInt() - 11);

  final String name;

  /// Jarak (unit dunia) untuk bisa masuk bengkel.
  static const serviceRange = 11.0;

  static final _floor = Paint()..color = const Color(0xFFD9D4CB);
  static final _floorEdge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.4
    ..color = BColors.trotoar;
  static final _wall = Paint()..color = const Color(0xFFEDE3D3);
  static final _roof = Paint()..color = BColors.biruPemain;
  static final _inside = Paint()..color = const Color(0xFF3A3330);
  static final _door = Paint()..color = const Color(0xFFA7AFB8);
  static final _sign = Paint()..color = BColors.oranye;
  static final _tyre = Paint()..color = const Color(0xFF1F1F1F);
  static final _hub = Paint()..color = const Color(0xFFA7AFB8);
  static final _inkLine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.25
    ..color = BColors.ink;

  static final _label = TextPainter(
    text: const TextSpan(
      text: 'BENGKEL',
      style: TextStyle(fontSize: 1.7, fontWeight: FontWeight.w900, color: Color(0xFFFFFFFF)),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void render(Canvas canvas) {
    final floor = RRect.fromRectAndRadius(const Rect.fromLTWH(-8, -11, 16, 11), const Radius.circular(1));
    canvas.drawRRect(floor, _floor);
    canvas.drawRRect(floor, _floorEdge);

    // Bangunan (dinding depan + atap), tampak 3/4.
    canvas.drawRect(const Rect.fromLTWH(-7, -14, 14, 3), _roof);
    canvas.drawRect(const Rect.fromLTWH(-7, -11, 14, 6), _wall);
    canvas.drawRect(const Rect.fromLTWH(-5, -9.5, 10, 4.5), _inside);
    canvas.drawRect(const Rect.fromLTWH(-5, -9.5, 10, 1.2), _door);
    canvas.drawRect(const Rect.fromLTWH(-7, -14, 14, 9), _inkLine);

    final sign = RRect.fromRectAndRadius(const Rect.fromLTWH(-4.4, -13.6, 8.8, 2.2), const Radius.circular(0.4));
    canvas.drawRRect(sign, _sign);
    _label.paint(canvas, Offset(-_label.width / 2, -12.5 - _label.height / 2));

    // Tumpukan ban di samping pintu.
    drawShadow(canvas, const Offset(6.2, -2.4), 1.6, 0.5);
    for (final y in const [-3.0, -4.2]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(6.2, y), width: 2.6, height: 1.2), _tyre);
      canvas.drawOval(Rect.fromCenter(center: Offset(6.2, y), width: 1.0, height: 0.45), _hub);
    }
  }
}
