import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, FontWeight;

import '../../ui/palette.dart';
import '../iso.dart';
import 'sprites.dart';

/// SPBU "BensinKu" di pinggir jalan: lantai, dua pompa, kanopi merah-putih.
/// Titik (0,0) = tengah depan lantai; ukuran ±18×14 unit.
class FuelStation extends PositionComponent with IsoPlaced {
  FuelStation({required Vector2 position, required this.area, required this.pumpNo})
    // Prioritas = tepi belakang lantai, supaya pemain/motor di atas lantai
    // tetap tergambar di depan kanopi.
    : super(position: position, priority: isoDepth(position, -12));

  final String area;
  final int pumpNo;

  /// Jarak (unit dunia) untuk bisa isi bensin.
  static const serviceRange = 11.0;

  static final _pad = Paint()..color = const Color(0xFFEFE0C0);
  static final _padEdge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.4
    ..color = BColors.trotoar;
  static final _ink = Paint()..color = BColors.ink;
  static final _inkLine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.25
    ..color = BColors.ink;
  static final _cream = Paint()..color = BColors.cream;
  static final _red = Paint()..color = BColors.atapMerah;
  static final _white = Paint()..color = const Color(0xFFFFFFFF);
  static final _tosca = Paint()..color = BColors.tosca;
  static final _yellow = Paint()..color = BColors.kuning;
  static final _canopyShadow = Paint()..color = const Color(0x33000000);

  static final _sign = TextPainter(
    text: const TextSpan(
      text: 'SPBU',
      style: TextStyle(fontSize: 2.2, fontWeight: FontWeight.w900, color: Color(0xFFFFFFFF)),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  /// Sprite lama (tampak 3/4) dipusatkan di tengah lantai iso sampai diganti model 3D.
  @override
  Offset get spriteOffset => buildingSpriteOffset;

  @override
  void render(Canvas canvas) {
    final pad = RRect.fromRectAndRadius(const Rect.fromLTWH(-9, -12, 18, 12), const Radius.circular(1));
    canvas.drawRRect(pad, _pad);
    canvas.drawRRect(pad, _padEdge);
    canvas.drawRect(const Rect.fromLTWH(-8.5, -8.5, 17, 6), _canopyShadow);

    for (final x in const [-4.5, 3.0]) {
      drawShadow(canvas, Offset(x + 0.75, -3.6), 1.6, 0.5);
      final pump = RRect.fromRectAndRadius(Rect.fromLTWH(x, -7, 1.5, 3.4), const Radius.circular(0.3));
      canvas.drawRRect(pump, _cream);
      canvas.drawRRect(pump, _inkLine);
      canvas.drawRect(Rect.fromLTWH(x + 0.25, -6.6, 1, 0.8), _ink);
      canvas.drawRect(Rect.fromLTWH(x + 0.25, -5.4, 1, 1.4), x < 0 ? _yellow : _tosca);
    }

    // Tiang & kanopi (tampak 3/4: atap terlihat di atas lantai).
    for (final x in const [-7.5, 7.0]) {
      canvas.drawRect(Rect.fromLTWH(x, -9.5, 0.5, 6.5), _ink);
    }
    final roof = RRect.fromRectAndRadius(const Rect.fromLTWH(-8.5, -14, 17, 5), const Radius.circular(0.6));
    canvas.drawRRect(roof, _white);
    canvas.drawRect(const Rect.fromLTWH(-8.5, -10.2, 17, 1.2), _red);
    canvas.drawRRect(roof, _inkLine);
    final sign = RRect.fromRectAndRadius(const Rect.fromLTWH(-3.4, -13.4, 6.8, 2.8), const Radius.circular(0.5));
    canvas.drawRRect(sign, _red);
    _sign.paint(canvas, Offset(-_sign.width / 2, -12 - _sign.height / 2));
  }
}
