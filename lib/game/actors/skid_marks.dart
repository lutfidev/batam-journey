import 'dart:ui';

import 'package:flame/components.dart';

import '../iso.dart';

/// Jejak rem ban di aspal: garis gelap di lantai (koordinat tanah) yang memudar.
/// Digambar tepat di atas lapisan jalan, di bawah semua aktor.
class SkidMarks extends Component {
  SkidMarks() : super(priority: -1000000000 + 1);

  /// Lama jejak memudar sampai hilang (detik) dan jumlah ruas maksimal.
  static const life = 8.0;
  static const maxMarks = 400;

  /// Jarak minimal antar titik supaya ruasnya tidak terlalu rapat.
  static const step = 0.4;

  final _marks = <_Mark>[];
  Offset? _last;

  int get count => _marks.length;

  /// Sambung jejak ke titik tanah [p] (dari titik sebelumnya, kalau ada).
  void addPoint(Offset p) {
    final last = _last;
    if (last == null) {
      _last = p;
      return;
    }
    if ((p - last).distance < step) return;
    _marks.add(_Mark(last, p));
    if (_marks.length > maxMarks) _marks.removeAt(0);
    _last = p;
  }

  /// Ban berhenti tergelincir: jejak berikutnya mulai garis baru.
  void lift() => _last = null;

  @override
  void update(double dt) {
    for (final m in _marks) {
      m.age += dt;
    }
    _marks.removeWhere((m) => m.age >= life);
  }

  final _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 0.32;

  @override
  void render(Canvas canvas) {
    if (_marks.isEmpty) return;
    canvas.save();
    canvas.transform(isoMatrix);
    for (final m in _marks) {
      _paint.color = const Color(0xFF1E1A17).withValues(alpha: 0.5 * (1 - m.age / life));
      canvas.drawLine(m.a, m.b, _paint);
    }
    canvas.restore();
  }
}

class _Mark {
  _Mark(this.a, this.b);

  final Offset a, b;
  double age = 0;
}
