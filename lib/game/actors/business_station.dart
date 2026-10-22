import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, FontWeight;

import '../../ui/palette.dart';
import '../batam_game.dart';
import '../iso.dart';
import '../systems/business.dart';

/// Ruko usaha (gaya ruko desain OnFoot): kanopi berwarna, kaca etalase,
/// papan nama, dan status DISEWAKAN / BUKA. Titik (0,0) = tengah depan.
class BusinessStation extends PositionComponent with HasGameReference<BatamGame>, IsoPlaced {
  BusinessStation({required Vector2 position, required this.type})
    : super(position: position, priority: isoDepth(position, -12));

  final BizType type;

  static const serviceRange = 11.0;

  static const _awnings = {
    'kopi': BColors.hijauAksi,
    'warung': BColors.atapMerah,
    'laundry': BColors.tosca,
    'kurir': BColors.kuning,
  };
  static const _labels = {'kopi': 'KOPI', 'warung': 'WARUNG', 'laundry': 'LAUNDRY', 'kurir': 'KURIR'};

  static final _floor = Paint()..color = const Color(0xFFE9E4DA);
  static final _wall = Paint()..color = const Color(0xFFF6E8CC);
  static final _roof = Paint()..color = const Color(0xFFC45A3C);
  static final _glass = Paint()..color = const Color(0xFF7EA6BC);
  static final _stripe = Paint()..color = BColors.cream;
  static final _inkLine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.25
    ..color = BColors.ink;

  static final _texts = <String, TextPainter>{};

  static TextPainter _text(String s, double size) => _texts['$s$size'] ??= TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, color: const Color(0xFFFFFFFF)),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  /// Sprite lama (tampak 3/4) dipusatkan di tengah lantai iso sampai diganti model 3D.
  @override
  Offset get spriteOffset => buildingSpriteOffset;

  @override
  void render(Canvas canvas) {
    canvas.drawRect(const Rect.fromLTWH(-8, -4, 16, 4), _floor);
    // Ruko: atap, dinding lantai atas, kanopi bergaris, etalase.
    canvas.drawRect(const Rect.fromLTWH(-8, -15, 16, 2), _roof);
    canvas.drawRect(const Rect.fromLTWH(-8, -13, 16, 5), _wall);
    canvas.drawRect(const Rect.fromLTWH(-6, -12.2, 3, 2.6), _glass);
    canvas.drawRect(const Rect.fromLTWH(3, -12.2, 3, 2.6), _glass);
    final awning = Paint()..color = _awnings[type.id] ?? BColors.oranye;
    final awn = Path()
      ..moveTo(-8.3, -8)
      ..lineTo(8.3, -8)
      ..lineTo(8.8, -6.6)
      ..lineTo(-8.8, -6.6)
      ..close();
    canvas.drawPath(awn, awning);
    for (var x = -7.0; x < 8; x += 3) {
      canvas.drawRect(Rect.fromLTWH(x, -8, 1.2, 1.4), _stripe);
    }
    canvas.drawRect(const Rect.fromLTWH(-8, -6.6, 16, 2.6), Paint()..color = const Color(0xFF4A3829));
    canvas.drawRect(const Rect.fromLTWH(-7, -6.2, 9, 2.2), _glass);
    canvas.drawRect(const Rect.fromLTWH(-8, -15, 16, 11), _inkLine);

    final name = _text(_labels[type.id] ?? type.name, 1.4);
    final board = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(0, -14), width: name.width + 1.4, height: 1.9),
      const Radius.circular(0.4),
    );
    canvas.drawRRect(board, Paint()..color = BColors.ink);
    name.paint(canvas, Offset(-name.width / 2, -14 - name.height / 2));

    final owned = game.business.owns(type.id);
    final (label, color) = type.locked
        ? ('SEGERA', const Color(0xFF6B5440))
        : owned
        ? ('BUKA', BColors.hijauAksi)
        : ('DISEWAKAN', BColors.atapMerah);
    final tp = _text(label, 1.3);
    final sign = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(5.2, -2.2), width: tp.width + 1.2, height: 1.8),
      const Radius.circular(0.4),
    );
    canvas.drawRRect(sign, Paint()..color = color);
    canvas.drawRRect(sign, _inkLine);
    tp.paint(canvas, Offset(5.2 - tp.width / 2, -2.2 - tp.height / 2));
  }
}
