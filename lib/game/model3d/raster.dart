import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color, Offset, Rect;

import 'mesh.dart';

/// Rasterizer perangkat lunak untuk [Model]: proyeksi iso 2:1 yang sama dengan
/// `iso.dart`, z-buffer, cahaya searah, dan outline tinta. Hasilnya piksel RGBA
/// (premultiplied) yang dipanggang jadi sprite oleh `bake.dart`. Murni Dart,
/// jadi bisa dites tanpa GPU.

/// Kamera ortografis yang cocok dengan proyeksi lantai game
/// `layar = (x − y, (x + y) / 2)`: elevasi 30°, tinggi z dikali √1,5.
abstract final class IsoCamera {
  static const heightScale = 1.2247448713915890;

  /// Vektor satuan dari adegan ke arah kamera (tenggara, di atas).
  static const toCamera = V3(0.6123724356957945, 0.6123724356957945, 0.5);

  /// Titik model → titik layar iso dalam satuan dunia (sama dengan `isoOf` saat z = 0).
  static Offset project(V3 p) => Offset(p.x - p.y, (p.x + p.y) / 2 - p.z * heightScale);

  /// Makin besar = makin dekat ke kamera.
  static double depth(V3 p) => p.dot(toCamera);
}

/// Gaya gambar bersama semua model.
class RenderStyle {
  const RenderStyle({
    this.light = const V3(0.18, 0.5, 0.85),
    this.ambient = 0.55,
    this.diffuse = 0.5,
    this.ink = const Color(0xFF2B1D12),
    this.outlinePx = 1,
    this.supersample = 2,
    this.creaseDepth = 0.35,
  });

  /// Arah ke sumber cahaya (tidak harus satuan): dari atas, condong ke kiri layar,
  /// sehingga atas paling terang, sisi kiri sedang, sisi kanan paling gelap.
  final V3 light;
  final double ambient, diffuse;

  /// Warna garis tinta (#2B1D12) dan tebalnya dalam piksel hasil.
  final Color ink;
  final int outlinePx;

  /// Gambar di resolusi [supersample]× lalu dirata-rata supaya tepi halus.
  final int supersample;

  /// Lompatan kedalaman (satuan dunia) dalam satu part yang tetap diberi garis.
  final double creaseDepth;

  /// Ruang kosong (piksel) di tepi sel supaya outline siluet tidak terpotong.
  int get padPx => outlinePx + 2;
}

/// Kotak piksel yang digambar, relatif ke titik pijak model (0,0,0) di layar.
/// Titik pijak ada di piksel (−[left], −[top]).
class PixelFrame {
  const PixelFrame(this.left, this.top, this.width, this.height);

  /// Kotak piksel bulat terkecil yang memuat [bounds] (satuan dunia layar iso)
  /// ditambah [pad] piksel di tiap sisi untuk outline.
  factory PixelFrame.around(Rect bounds, double pixelsPerUnit, {int pad = 2}) {
    final l = (bounds.left * pixelsPerUnit).floor() - pad;
    final t = (bounds.top * pixelsPerUnit).floor() - pad;
    final r = (bounds.right * pixelsPerUnit).ceil() + pad;
    final b = (bounds.bottom * pixelsPerUnit).ceil() + pad;
    return PixelFrame(l, t, r - l, b - t);
  }

  final int left, top, width, height;

  Offset get anchor => Offset(-left.toDouble(), -top.toDouble());
}

/// Hasil render satu pose: piksel RGBA premultiplied, baris demi baris.
class RasterImage {
  RasterImage(this.width, this.height, this.rgba, this.anchor);

  final int width, height;
  final Uint8List rgba;

  /// Titik pijak (tanah) di dalam gambar, dalam piksel.
  final Offset anchor;

  int alphaAt(int x, int y) => rgba[(y * width + x) * 4 + 3];

  /// Warna di (x, y) setelah dibagi alfa (untuk tes).
  Color colorAt(int x, int y) {
    final i = (y * width + x) * 4;
    final a = rgba[i + 3];
    if (a == 0) return const Color(0x00000000);
    int un(int v) => (v * 255 / a).round().clamp(0, 255);
    return Color.fromARGB(a, un(rgba[i]), un(rgba[i + 1]), un(rgba[i + 2]));
  }
}

/// Batas gambar [model] setelah diputar [yaw], di layar iso (satuan dunia).
Rect projectedBounds(Model model, double yaw) {
  var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
  for (final part in model.parts) {
    for (final tri in part.mesh.tris) {
      for (final v in [tri.a, tri.b, tri.c]) {
        final s = IsoCamera.project(part.point(v).rotZ(yaw));
        l = math.min(l, s.dx);
        t = math.min(t, s.dy);
        r = math.max(r, s.dx);
        b = math.max(b, s.dy);
      }
    }
  }
  return l > r ? Rect.zero : Rect.fromLTRB(l, t, r, b);
}

/// Gambar [model] menghadap heading [yaw] (radian di tanah, 0 = timur,
/// π/2 = selatan) ke kotak [frame] dengan [pixelsPerUnit] piksel per satuan dunia.
RasterImage renderModel(
  Model model, {
  required double yaw,
  required double pixelsPerUnit,
  required PixelFrame frame,
  RenderStyle style = const RenderStyle(),
}) {
  final ss = style.supersample;
  final w = frame.width * ss, h = frame.height * ss;
  final k = pixelsPerUnit * ss;
  final ox = -frame.left * ss.toDouble(), oy = -frame.top * ss.toDouble();
  final n = w * h;
  final depth = Float32List(n)..fillRange(0, n, double.negativeInfinity);
  final ids = Uint16List(n);
  final color = Uint8List(n * 4);

  final light = style.light.normalized();
  final half = (light + IsoCamera.toCamera).normalized();

  for (var pi = 0; pi < model.parts.length; pi++) {
    final part = model.parts[pi];
    final mat = part.material;
    final id = pi + 1;
    final cr = (mat.color.r * 255), cg = (mat.color.g * 255), cb = (mat.color.b * 255);

    for (final tri in part.mesh.tris) {
      final a = part.point(tri.a).rotZ(yaw), b = part.point(tri.b).rotZ(yaw), c = part.point(tri.c).rotZ(yaw);
      final fn = (b - a).cross(c - a);
      if (fn.dot(IsoCamera.toCamera) <= 0) continue; // muka membelakangi kamera

      final pa = IsoCamera.project(a), pb = IsoCamera.project(b), pc = IsoCamera.project(c);
      final ax = ox + pa.dx * k, ay = oy + pa.dy * k;
      final bx = ox + pb.dx * k, by = oy + pb.dy * k;
      final cx = ox + pc.dx * k, cy = oy + pc.dy * k;
      final area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
      if (area.abs() < 1e-9) continue;
      final da = IsoCamera.depth(a), db = IsoCamera.depth(b), dc = IsoCamera.depth(c);

      // Normal per titik (halus) atau satu normal muka (datar).
      final na = mat.smooth ? part.normal(tri.na).rotZ(yaw) : fn.normalized();
      final nb = mat.smooth ? part.normal(tri.nb).rotZ(yaw) : na;
      final nc = mat.smooth ? part.normal(tri.nc).rotZ(yaw) : na;

      var flatR = 0, flatG = 0, flatB = 0;
      if (!mat.smooth) {
        (flatR, flatG, flatB) = _shade(na.x, na.y, na.z, cr, cg, cb, mat.gloss, light, half, style);
      }

      final x0 = math.max(0, math.min(ax, math.min(bx, cx)).floor());
      final x1 = math.min(w - 1, math.max(ax, math.max(bx, cx)).ceil());
      final y0 = math.max(0, math.min(ay, math.min(by, cy)).floor());
      final y1 = math.min(h - 1, math.max(ay, math.max(by, cy)).ceil());
      final inv = 1 / area;
      for (var y = y0; y <= y1; y++) {
        final py = y + 0.5;
        for (var x = x0; x <= x1; x++) {
          final px = x + 0.5;
          // Koordinat barisentrik; tanda area menyamakan arah putar layar.
          final wa = ((bx - px) * (cy - py) - (by - py) * (cx - px)) * inv;
          final wb = ((cx - px) * (ay - py) - (cy - py) * (ax - px)) * inv;
          final wc = 1 - wa - wb;
          if (wa < 0 || wb < 0 || wc < 0) continue;
          final i = y * w + x;
          final d = wa * da + wb * db + wc * dc;
          if (d <= depth[i]) continue;
          depth[i] = d;
          ids[i] = id;
          int r, g, bl;
          if (mat.smooth) {
            final nx = wa * na.x + wb * nb.x + wc * nc.x;
            final ny = wa * na.y + wb * nb.y + wc * nc.y;
            final nz = wa * na.z + wb * nb.z + wc * nc.z;
            final len = math.sqrt(nx * nx + ny * ny + nz * nz);
            (r, g, bl) = _shade(nx / len, ny / len, nz / len, cr, cg, cb, mat.gloss, light, half, style);
          } else {
            r = flatR;
            g = flatG;
            bl = flatB;
          }
          final o = i * 4;
          color[o] = r;
          color[o + 1] = g;
          color[o + 2] = bl;
          color[o + 3] = 255;
        }
      }
    }
  }

  // Setengah piksel ekstra supaya garis tetap pekat walau tidak sejajar grid piksel hasil.
  _outline(color, depth, ids, w, h, style.outlinePx * ss + ss ~/ 2, style);
  return RasterImage(
    frame.width,
    frame.height,
    _downsample(color, w, h, ss),
    frame.anchor,
  );
}

(int, int, int) _shade(
  double nx,
  double ny,
  double nz,
  double r,
  double g,
  double b,
  double gloss,
  V3 light,
  V3 half,
  RenderStyle style,
) {
  final lambert = math.max(0.0, nx * light.x + ny * light.y + nz * light.z);
  final i = style.ambient + style.diffuse * lambert;
  var spec = 0.0;
  if (gloss > 0) {
    final s = math.max(0.0, nx * half.x + ny * half.y + nz * half.z);
    spec = gloss * math.pow(s, 24) * 255;
  }
  int ch(double v) => (v * i + spec).round().clamp(0, 255);
  return (ch(r), ch(g), ch(b));
}

/// Garis tinta: di luar siluet, dan di sisi yang lebih jauh dari batas antar-part
/// atau lompatan kedalaman, supaya bentuk depan tetap utuh.
void _outline(Uint8List color, Float32List depth, Uint16List ids, int w, int h, int t, RenderStyle style) {
  final offsets = <(int, int)>[
    for (var dy = -t; dy <= t; dy++)
      for (var dx = -t; dx <= t; dx++)
        if ((dx != 0 || dy != 0) && dx * dx + dy * dy <= t * t) (dx, dy),
  ];
  final ink = <int>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final id = ids[i];
      final d = depth[i];
      for (final (dx, dy) in offsets) {
        final qx = x + dx, qy = y + dy;
        if (qx < 0 || qy < 0 || qx >= w || qy >= h) continue;
        final q = qy * w + qx;
        final qid = ids[q];
        if (qid == 0) continue;
        final nearer = depth[q] - d;
        if (id == 0 || (qid != id && nearer > 0) || nearer > style.creaseDepth) {
          ink.add(i);
          break;
        }
      }
    }
  }
  final r = (style.ink.r * 255).round(), g = (style.ink.g * 255).round(), b = (style.ink.b * 255).round();
  for (final i in ink) {
    final o = i * 4;
    color[o] = r;
    color[o + 1] = g;
    color[o + 2] = b;
    color[o + 3] = 255;
  }
}

/// Rata-rata tiap blok [ss]×[ss] jadi satu piksel premultiplied.
Uint8List _downsample(Uint8List src, int w, int h, int ss) {
  final ow = w ~/ ss, oh = h ~/ ss;
  final out = Uint8List(ow * oh * 4);
  final count = ss * ss;
  for (var y = 0; y < oh; y++) {
    for (var x = 0; x < ow; x++) {
      var r = 0, g = 0, b = 0, a = 0;
      for (var sy = 0; sy < ss; sy++) {
        var i = ((y * ss + sy) * w + x * ss) * 4;
        for (var sx = 0; sx < ss; sx++, i += 4) {
          final al = src[i + 3];
          r += src[i] * al;
          g += src[i + 1] * al;
          b += src[i + 2] * al;
          a += al;
        }
      }
      final o = (y * ow + x) * 4;
      out[o] = (r / (255 * count)).round();
      out[o + 1] = (g / (255 * count)).round();
      out[o + 2] = (b / (255 * count)).round();
      out[o + 3] = (a / count).round();
    }
  }
  return out;
}
