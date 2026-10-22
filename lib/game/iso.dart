import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/rendering.dart';

/// Proyeksi isometrik 2:1. Simulasi (graf jalan, A*, GPS, order, save) tetap di
/// koordinat tanah; hanya gambar dan input yang memakai koordinat layar iso:
/// `layar = (x − y, (x + y) / 2)`. Utara tanah jadi kiri-atas layar.

/// Titik tanah → titik layar iso.
Offset isoOf(Offset g) => Offset(g.dx - g.dy, (g.dx + g.dy) / 2);

/// Titik layar iso → titik tanah (kebalikan [isoOf]).
Offset groundOf(Offset s) => Offset(s.dy + s.dx / 2, s.dy - s.dx / 2);

Vector2 isoOfV(Vector2 g) => Vector2(g.x - g.y, (g.x + g.y) / 2);

/// Matriks kanvas yang menggambar koordinat tanah sebagai lantai iso.
final Float64List isoMatrix = Float64List.fromList([
  1, 0.5, 0, 0, //
  -1, 0.5, 0, 0, //
  0, 0, 1, 0, //
  0, 0, 0, 1, //
]);

/// Kotak tanah terkecil yang memuat seluruh kotak layar [s].
Rect groundRectOf(Rect s) {
  final pts = [groundOf(s.topLeft), groundOf(s.topRight), groundOf(s.bottomLeft), groundOf(s.bottomRight)];
  return Rect.fromLTRB(
    pts.map((p) => p.dx).reduce(math.min),
    pts.map((p) => p.dy).reduce(math.min),
    pts.map((p) => p.dx).reduce(math.max),
    pts.map((p) => p.dy).reduce(math.max),
  );
}

/// Arah joystick/keyboard di layar → arah di tanah dengan panjang yang sama,
/// supaya dorongan ke kanan layar membuat aktor bergerak ke kanan layar.
Vector2 screenDirToGround(Vector2 s) {
  final len = s.length;
  if (len == 0) return Vector2.zero();
  final g = Vector2(s.y + s.x / 2, s.y - s.x / 2)..normalize();
  return g..scale(len);
}

/// Prioritas gambar dari kedalaman tanah `x + y`: makin ke depan (bawah layar), makin atas.
int isoDepth(Vector2 g, [double bias = 0]) => (g.x + g.y + bias).toInt();

/// Komponen yang [position]-nya koordinat tanah, tetapi digambar tegak di titik
/// layar iso-nya (sprite tidak ikut miring). Sudut/skala/anchor tidak dipakai.
mixin IsoPlaced on PositionComponent {
  @override
  FutureOr<void> onLoad() {
    decorator = IsoDecorator(this);
    return super.onLoad();
  }
}

/// Pengganti [Transform2DDecorator]: geser kanvas ke titik layar iso dari posisi tanah.
class IsoDecorator extends Decorator {
  IsoDecorator(this.component);

  final IsoPlaced component;

  @override
  void apply(void Function(Canvas) draw, Canvas canvas) {
    final p = component.position;
    canvas.save();
    canvas.translate(p.x - p.y, (p.x + p.y) / 2);
    draw(canvas);
    canvas.restore();
  }
}
