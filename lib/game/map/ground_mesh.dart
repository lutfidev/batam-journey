import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Pengumpul segitiga lantai (laut, darat, jalan, marka) per warna, supaya
/// lantai cukup dipecah jadi segitiga sekali lalu digambar ulang lewat
/// [Canvas.drawVertices] tanpa tessellate path tiap frame. Satu [Vertices]
/// per warna tanpa warna per titik: Impeller lalu memakai jalur isian warna
/// padat biasa (warna per titik memakai shader blend yang jauh lebih mahal).
class TriBuilder {
  final _pos = <Color, List<double>>{};

  void tri(Offset a, Offset b, Offset c, Color color) =>
      (_pos[color] ??= []).addAll([a.dx, a.dy, b.dx, b.dy, c.dx, c.dy]);

  void rect(Rect r, Color color) {
    tri(r.topLeft, r.topRight, r.bottomRight, color);
    tri(r.topLeft, r.bottomRight, r.bottomLeft, color);
  }

  /// Poligon cembung sebagai kipas dari titik pertama.
  void fan(List<Offset> poly, Color color) {
    for (var i = 1; i + 1 < poly.length; i++) {
      tri(poly[0], poly[i], poly[i + 1], color);
    }
  }

  /// Persegi panjang selebar [width] dari [a] ke [b] (ujung rata).
  void quadLine(Offset a, Offset b, double width, Color color) {
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final n = Offset(-d.dy, d.dx) * (width / 2 / len);
    fan([a + n, b + n, b - n, a - n], color);
  }

  /// Lingkaran berjari-jari [r]; jumlah sisi mengikuti besarnya.
  void disc(Offset c, double r, Color color) {
    final n = (r * 1.6).clamp(6, 14).round();
    var prev = c + Offset(r, 0);
    for (var i = 1; i <= n; i++) {
      final a = 2 * math.pi * i / n;
      final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
      tri(c, prev, p, color);
      prev = p;
    }
  }

  /// Hasil per warna, siap digambar dengan [GroundMesh.draw].
  GroundMesh build() => GroundMesh([
    for (final MapEntry(key: color, value: pos) in _pos.entries)
      (Vertices.raw(VertexMode.triangles, Float32List.fromList(pos)), Paint()..color = color),
  ]);
}

/// Segitiga satu lapis lantai, dikelompokkan per warna.
class GroundMesh {
  GroundMesh(this.parts);

  final List<(Vertices, Paint)> parts;

  void draw(Canvas canvas) {
    for (final (v, paint) in parts) {
      canvas.drawVertices(v, BlendMode.srcOver, paint);
    }
  }

  void dispose() {
    for (final (v, _) in parts) {
      v.dispose();
    }
  }
}

/// Bagian ruas [a]–[b] di dalam kotak [r] (Liang–Barsky), atau null.
(Offset, Offset)? clipToRect(Offset a, Offset b, Rect r) {
  var t0 = 0.0, t1 = 1.0;
  final d = b - a;
  bool clip(double p, double q) {
    if (p == 0) return q >= 0;
    final t = q / p;
    if (p < 0) {
      if (t > t1) return false;
      if (t > t0) t0 = t;
    } else {
      if (t < t0) return false;
      if (t < t1) t1 = t;
    }
    return true;
  }

  if (!clip(-d.dx, a.dx - r.left) ||
      !clip(d.dx, r.right - a.dx) ||
      !clip(-d.dy, a.dy - r.top) ||
      !clip(d.dy, r.bottom - a.dy)) {
    return null;
  }
  if (t1 <= t0) return null;
  return (a + d * t0, a + d * t1);
}
