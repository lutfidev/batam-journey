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
    final m = _PartMatrix(part, yaw);
    for (final tri in part.mesh.tris) {
      for (final v in [tri.a, tri.b, tri.c]) {
        final s = IsoCamera.project(m.point(v));
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

  final nrm = Float32List(n * 3);

  for (var pi = 0; pi < model.parts.length; pi++) {
    final part = model.parts[pi];
    final mat = part.material;
    final id = pi + 1;
    final m = _PartMatrix(part, yaw);

    for (final tri in part.mesh.tris) {
      final a = m.point(tri.a), b = m.point(tri.b), c = m.point(tri.c);
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
      final na = mat.smooth ? m.normal(tri.na) : fn.normalized();
      final nb = mat.smooth ? m.normal(tri.nb) : na;
      final nc = mat.smooth ? m.normal(tri.nc) : na;

      final x0 = math.max(0, math.min(ax, math.min(bx, cx)).floor());
      final x1 = math.min(w - 1, math.max(ax, math.max(bx, cx)).ceil());
      final y0 = math.max(0, math.min(ay, math.min(by, cy)).floor());
      final y1 = math.min(h - 1, math.max(ay, math.max(by, cy)).ceil());
      final inv = 1 / area;
      // Koordinat barisentrik linear di x: hitung di awal baris lalu tambahkan per piksel.
      final dwa = (by - cy) * inv, dwb = (cy - ay) * inv;
      for (var y = y0; y <= y1; y++) {
        final py = y + 0.5;
        final px0 = x0 + 0.5;
        // Tanda area menyamakan arah putar layar.
        var wa = ((bx - px0) * (cy - py) - (by - py) * (cx - px0)) * inv;
        var wb = ((cx - px0) * (ay - py) - (cy - py) * (ax - px0)) * inv;
        for (var x = x0; x <= x1; x++, wa += dwa, wb += dwb) {
          final wc = 1 - wa - wb;
          if (wa < 0 || wb < 0 || wc < 0) continue;
          final i = y * w + x;
          final d = wa * da + wb * db + wc * dc;
          if (d <= depth[i]) continue;
          depth[i] = d;
          ids[i] = id;
          final o = i * 3;
          nrm[o] = wa * na.x + wb * nb.x + wc * nc.x;
          nrm[o + 1] = wa * na.y + wb * nb.y + wc * nc.y;
          nrm[o + 2] = wa * na.z + wb * nb.z + wc * nc.z;
        }
      }
    }
  }

  // Shading sekali per piksel yang terlihat (bukan per piksel yang tertimpa).
  final light = style.light.normalized();
  final half = (light + IsoCamera.toCamera).normalized();
  final shaders = [for (final part in model.parts) _Shader(part.material, light, half, style)];
  for (var i = 0; i < n; i++) {
    final id = ids[i];
    if (id == 0) continue;
    final nx = nrm[i * 3], ny = nrm[i * 3 + 1], nz = nrm[i * 3 + 2];
    final len = math.sqrt(nx * nx + ny * ny + nz * nz);
    final l = len == 0 ? 0.0 : 1 / len;
    shaders[id - 1].shade(color, i * 4, nx * l, ny * l, nz * l);
  }

  // Setengah piksel ekstra supaya garis tetap pekat walau tidak sejajar grid piksel hasil.
  final inked = [false, for (final part in model.parts) part.material.inked];
  _outline(color, depth, ids, inked, w, h, style.outlinePx * ss + ss ~/ 2, style);
  return RasterImage(frame.width, frame.height, _downsample(color, w, h, ss), frame.anchor);
}

/// Transformasi [Part] lalu putaran [yaw], sebagai matriks 3×3 + geseran,
/// supaya sin/cos dihitung sekali per part, bukan per titik.
class _PartMatrix {
  factory _PartMatrix(Part part, double yaw) {
    // Kolom matriks = gambar sumbu satuan setelah putar x, y, z, lalu yaw.
    V3 rot(V3 v) => v.rotX(part.rotX).rotY(part.rotY).rotZ(part.rotZ).rotZ(yaw);
    final ex = rot(const V3(1, 0, 0)), ey = rot(const V3(0, 1, 0)), ez = rot(const V3(0, 0, 1));
    return _PartMatrix._(ex, ey, ez, part.scale, part.at.rotZ(yaw));
  }

  _PartMatrix._(this.ex, this.ey, this.ez, this.s, this.t);

  final V3 ex, ey, ez, s, t;

  V3 point(V3 p) {
    final x = p.x * s.x, y = p.y * s.y, z = p.z * s.z;
    return V3(
      ex.x * x + ey.x * y + ez.x * z + t.x,
      ex.y * x + ey.y * y + ez.y * z + t.y,
      ex.z * x + ey.z * y + ez.z * z + t.z,
    );
  }

  /// Normal ikut skala tak seragam lewat invers-transpos (bagi dengan skala).
  V3 normal(V3 n) {
    final x = n.x / s.x, y = n.y / s.y, z = n.z / s.z;
    return V3(
      ex.x * x + ey.x * y + ez.x * z,
      ex.y * x + ey.y * y + ez.y * z,
      ex.z * x + ey.z * y + ez.z * z,
    ).normalized();
  }
}

/// Cahaya satu bahan: lambert + ambient, ditambah kilap specular.
class _Shader {
  _Shader(Material mat, this.light, this.half, RenderStyle style)
    : r = mat.color.r * 255,
      g = mat.color.g * 255,
      b = mat.color.b * 255,
      gloss = mat.gloss * 255,
      shininess = mat.shininess,
      ambient = style.ambient,
      diffuse = style.diffuse,
      // Di bawah kosinus ini kilapnya < ½ level warna, jadi pow tidak perlu dihitung.
      specMin = mat.gloss > 0 ? math.pow(0.5 / (mat.gloss * 255), 1 / mat.shininess).toDouble() : 2;

  final V3 light, half;
  final double r, g, b, gloss, shininess, ambient, diffuse, specMin;

  /// Tulis warna untuk normal satuan (nx, ny, nz) ke [out] di [o].
  void shade(Uint8List out, int o, double nx, double ny, double nz) {
    final lambert = math.max(0.0, nx * light.x + ny * light.y + nz * light.z);
    final i = ambient + diffuse * lambert;
    var spec = 0.0;
    final s = nx * half.x + ny * half.y + nz * half.z;
    if (s > specMin) spec = gloss * math.pow(s, shininess);
    out[o] = _byte(r * i + spec);
    out[o + 1] = _byte(g * i + spec);
    out[o + 2] = _byte(b * i + spec);
    out[o + 3] = 255;
  }
}

int _byte(double v) => v <= 0 ? 0 : (v >= 255 ? 255 : v.round());

/// Garis tinta: di luar siluet, dan di sisi yang lebih jauh dari batas antar-part
/// atau lompatan kedalaman, supaya bentuk depan tetap utuh. Batas dengan part
/// yang `inked`-nya false tidak bergaris. [inked] diindeks id part (0 = kosong).
void _outline(
  Uint8List color,
  Float32List depth,
  Uint16List ids,
  List<bool> inked,
  int w,
  int h,
  int t,
  RenderStyle style,
) {
  final ox = <int>[], oy = <int>[];
  for (var dy = -t; dy <= t; dy++) {
    for (var dx = -t; dx <= t; dx++) {
      if ((dx != 0 || dy != 0) && dx * dx + dy * dy <= t * t) {
        ox.add(dx);
        oy.add(dy);
      }
    }
  }
  final n = ox.length;
  // Geseran indeks datar per tetangga: jalur cepat tanpa cek batas untuk piksel
  // yang jaraknya ≥ t dari tepi; pita tepi memakai cek batas.
  final delta = Int32List.fromList([for (var k = 0; k < n; k++) oy[k] * w + ox[k]]);
  final crease = style.creaseDepth;

  // Tahap 1: tandai piksel yang bertetangga langsung (kanan/bawah) dengan id lain
  // atau lompatan kedalaman > crease / (2t). Tiap piksel yang perlu tinta pasti
  // punya tanda dalam lingkaran radius t: jalur L dari piksel ke tetangga
  // pemicunya (≤ 2t langkah) tetap di dalam lingkaran dan pasti melewati
  // perubahan semacam itu. Jadi cek penuh di tahap 2 cukup untuk piksel dekat tanda.
  final step = crease / (2 * t);
  final mark = Uint8List(w * h);
  void pair(int i, int q) {
    final id = ids[i];
    if (ids[q] != id || (id != 0 && (depth[q] - depth[i]).abs() > step)) {
      mark[i] = 1;
      mark[q] = 1;
    }
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (x + 1 < w) pair(i, i + 1);
      if (y + 1 < h) pair(i, i + w);
    }
  }
  // Jarak mendatar ke tanda terdekat di baris yang sama (dibatasi t + 1).
  final near = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    var run = t + 1;
    for (var x = 0; x < w; x++) {
      run = mark[row + x] == 1 ? 0 : math.min(run + 1, t + 1);
      near[row + x] = run;
    }
    run = t + 1;
    for (var x = w - 1; x >= 0; x--) {
      run = mark[row + x] == 1 ? 0 : math.min(run + 1, t + 1);
      if (run < near[row + x]) near[row + x] = run;
    }
  }
  final reach = [for (var k = 0; k <= t; k++) math.sqrt(t * t - k * k).floor()];

  // Tahap 2: cek penuh tetangga dalam lingkaran, hanya dekat tanda.
  final ink = <int>[];
  for (var y = 0; y < h; y++) {
    final edgeRow = y < t || y >= h - t;
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      var close = false;
      for (var dy = -t; dy <= t && !close; dy++) {
        final yy = y + dy;
        if (yy >= 0 && yy < h && near[yy * w + x] <= reach[dy.abs()]) close = true;
      }
      if (!close) continue;
      final id = ids[i];
      final edge = edgeRow || x < t || x >= w - t;
      if (id == 0) {
        // Di luar siluet: bertinta bila ada piksel model di dekatnya.
        for (var k = 0; k < n; k++) {
          if (edge) {
            final qx = x + ox[k], qy = y + oy[k];
            if (qx < 0 || qy < 0 || qx >= w || qy >= h) continue;
          }
          if (ids[i + delta[k]] != 0) {
            ink.add(i);
            break;
          }
        }
        continue;
      }
      final d = depth[i];
      final mine = inked[id];
      for (var k = 0; k < n; k++) {
        if (edge) {
          final qx = x + ox[k], qy = y + oy[k];
          if (qx < 0 || qy < 0 || qx >= w || qy >= h) continue;
        }
        final q = i + delta[k];
        final qid = ids[q];
        if (qid == 0) continue;
        final nearer = depth[q] - d;
        if (qid != id) {
          if (mine && inked[qid] && nearer > 0) {
            ink.add(i);
            break;
          }
        } else if (nearer > crease) {
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
  final count = ss * ss, cDiv = 255 * count;
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
      if (a == 0) continue;
      final o = (y * ow + x) * 4;
      // Pembagian bulat (dibulatkan ke terdekat) tanpa double.
      out[o] = (r + cDiv ~/ 2) ~/ cDiv;
      out[o + 1] = (g + cDiv ~/ 2) ~/ cDiv;
      out[o + 2] = (b + cDiv ~/ 2) ~/ cDiv;
      out[o + 3] = (a + count ~/ 2) ~/ count;
    }
  }
  return out;
}
