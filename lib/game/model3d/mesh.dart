import 'dart:math' as math;
import 'dart:ui' show Color, Offset;

/// Model low-poly di kode Dart: bentuk dasar (kotak, silinder, bola, ekstrusi)
/// yang dirakit jadi [Model], lalu dipanggang jadi sprite oleh `raster.dart`.
///
/// Koordinat model = koordinat tanah game dalam satuan dunia: x → timur,
/// y → selatan, z → atas. Titik (0,0,0) = titik pijak di tanah, dan model
/// menghadap +x (heading 0); baker memutarnya ke 16 arah.

/// Vektor 3D kecil (tanpa dependensi), immutable.
class V3 {
  const V3(this.x, this.y, this.z);

  static const zero = V3(0, 0, 0);

  final double x, y, z;

  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double s) => V3(x * s, y * s, z * s);
  V3 operator -() => V3(-x, -y, -z);

  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));

  V3 normalized() {
    final l = length;
    return l == 0 ? this : this * (1 / l);
  }

  /// Kali per komponen (skala tak seragam).
  V3 mul(V3 o) => V3(x * o.x, y * o.y, z * o.z);

  /// Putar mengelilingi sumbu z (atas) sebesar [a] radian, searah heading game.
  V3 rotZ(double a) {
    final c = math.cos(a), s = math.sin(a);
    return V3(x * c - y * s, x * s + y * c, z);
  }

  V3 rotX(double a) {
    final c = math.cos(a), s = math.sin(a);
    return V3(x, y * c - z * s, y * s + z * c);
  }

  V3 rotY(double a) {
    final c = math.cos(a), s = math.sin(a);
    return V3(x * c + z * s, y, -x * s + z * c);
  }

  @override
  String toString() => 'V3($x, $y, $z)';
}

/// Segitiga dengan normal per titik. Urutan titik berlawanan jarum jam bila
/// dilihat dari luar, sehingga `(b − a) × (c − a)` menunjuk keluar.
class Tri {
  const Tri(this.a, this.b, this.c, this.na, this.nb, this.nc);

  /// Segitiga datar: ketiga normalnya = normal muka.
  factory Tri.flat(V3 a, V3 b, V3 c) {
    final n = (b - a).cross(c - a).normalized();
    return Tri(a, b, c, n, n, n);
  }

  final V3 a, b, c;
  final V3 na, nb, nc;

  V3 get faceNormal => (b - a).cross(c - a).normalized();
  V3 get centroid => (a + b + c) * (1 / 3);
}

/// Kumpulan segitiga satu bentuk.
class Mesh {
  const Mesh(this.tris);

  final List<Tri> tris;

  /// Kotak [w]×[d]×[h] (x×y×z), alas di z = 0 dan berpusat di sumbu z.
  factory Mesh.box(double w, double d, double h) {
    final x = w / 2, y = d / 2;
    final tris = <Tri>[];
    void quad(V3 a, V3 b, V3 c, V3 e) => tris
      ..add(Tri.flat(a, b, c))
      ..add(Tri.flat(a, c, e));
    // Tiap muka berlawanan jarum jam dilihat dari luar.
    quad(V3(-x, -y, h), V3(x, -y, h), V3(x, y, h), V3(-x, y, h)); // atas
    quad(V3(-x, -y, 0), V3(-x, y, 0), V3(x, y, 0), V3(x, -y, 0)); // bawah
    quad(V3(x, -y, 0), V3(x, y, 0), V3(x, y, h), V3(x, -y, h)); // +x
    quad(V3(-x, y, 0), V3(-x, -y, 0), V3(-x, -y, h), V3(-x, y, h)); // −x
    quad(V3(x, y, 0), V3(-x, y, 0), V3(-x, y, h), V3(x, y, h)); // +y
    quad(V3(-x, -y, 0), V3(x, -y, 0), V3(x, -y, h), V3(-x, -y, h)); // −y
    return Mesh(tris);
  }

  /// Silinder tegak setinggi [h] dengan jari-jari alas [r] dan atas [rTop]
  /// (default sama; `rTop: 0` = kerucut). Alas di z = 0.
  factory Mesh.cylinder(double r, double h, {double? rTop, int segments = 12}) {
    final rt = rTop ?? r;
    final tris = <Tri>[];
    // Normal sisi miring kerucut: condong ke atas sebanding (r − rTop) / h.
    final slope = h == 0 ? 0.0 : (r - rt) / h;
    V3 ring(int i, double rad, double z) {
      final a = 2 * math.pi * i / segments;
      return V3(math.cos(a) * rad, math.sin(a) * rad, z);
    }

    V3 sideNormal(int i) {
      final a = 2 * math.pi * i / segments;
      return V3(math.cos(a), math.sin(a), slope).normalized();
    }

    final top = V3(0, 0, h);
    for (var i = 0; i < segments; i++) {
      final j = i + 1;
      final b0 = ring(i, r, 0), b1 = ring(j, r, 0);
      final t0 = ring(i, rt, h), t1 = ring(j, rt, h);
      final n0 = sideNormal(i), n1 = sideNormal(j);
      if (r > 0) tris.add(Tri(b0, b1, t1, n0, n1, n1));
      if (rt > 0) tris.add(Tri(b0, t1, t0, n0, n1, n0));
      if (r > 0) tris.add(Tri.flat(V3.zero, b1, b0));
      if (rt > 0) tris.add(Tri.flat(top, t0, t1));
    }
    return Mesh(tris);
  }

  /// Bola/elipsoid berjari-jari [rx]×[ry]×[rz], berpusat di (0,0,0).
  /// [segments] irisan bujur, [rings] irisan lintang.
  factory Mesh.sphere(double rx, {double? ry, double? rz, int segments = 12, int rings = 8}) {
    final yr = ry ?? rx, zr = rz ?? rx;
    V3 unit(int i, int j) {
      final lon = 2 * math.pi * i / segments;
      final lat = math.pi * j / rings - math.pi / 2;
      return V3(math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat));
    }

    final scale = V3(rx, yr, zr);
    // Normal elipsoid = gradien (x/rx², y/ry², z/rz²).
    final inv = V3(1 / rx, 1 / yr, 1 / zr);
    V3 normal(V3 u) => u.mul(inv).normalized();
    final tris = <Tri>[];
    for (var j = 0; j < rings; j++) {
      for (var i = 0; i < segments; i++) {
        final u00 = unit(i, j), u10 = unit(i + 1, j), u01 = unit(i, j + 1), u11 = unit(i + 1, j + 1);
        final p00 = u00.mul(scale), p10 = u10.mul(scale), p01 = u01.mul(scale), p11 = u11.mul(scale);
        if (j > 0) tris.add(Tri(p00, p10, p11, normal(u00), normal(u10), normal(u11)));
        if (j < rings - 1) tris.add(Tri(p00, p11, p01, normal(u00), normal(u11), normal(u01)));
      }
    }
    return Mesh(tris);
  }

  /// Bentuk putar: profil [profile] (dx = jari-jari, dy = tinggi z, urut dari
  /// bawah ke atas) diputar mengelilingi sumbu z. Normal halus per titik profil,
  /// cocok untuk bentuk bulat seperti badan slime. Jari-jari 0 di ujung = tutup.
  factory Mesh.lathe(List<Offset> profile, {int segments = 16}) {
    final n = profile.length;
    // Normal profil di bidang (r, z): tegak lurus garis singgung, menghadap keluar.
    final pn = <Offset>[
      for (var k = 0; k < n; k++)
        () {
          final t = profile[math.min(k + 1, n - 1)] - profile[math.max(k - 1, 0)];
          final l = t.distance;
          return l == 0 ? const Offset(1, 0) : Offset(t.dy / l, -t.dx / l);
        }(),
    ];
    V3 at(int k, int i) {
      final a = 2 * math.pi * i / segments;
      return V3(math.cos(a) * profile[k].dx, math.sin(a) * profile[k].dx, profile[k].dy);
    }

    V3 nAt(int k, int i) {
      final a = 2 * math.pi * i / segments;
      return V3(math.cos(a) * pn[k].dx, math.sin(a) * pn[k].dx, pn[k].dy);
    }

    final tris = <Tri>[];
    for (var k = 0; k + 1 < n; k++) {
      for (var i = 0; i < segments; i++) {
        final j = i + 1;
        if (profile[k].dx > 0) tris.add(Tri(at(k, i), at(k, j), at(k + 1, j), nAt(k, i), nAt(k, j), nAt(k + 1, j)));
        if (profile[k + 1].dx > 0) {
          tris.add(Tri(at(k, i), at(k + 1, j), at(k + 1, i), nAt(k, i), nAt(k + 1, j), nAt(k + 1, i)));
        }
      }
    }
    return Mesh(tris);
  }

  /// Ekstrusi poligon 2D [outline] (bidang xy, boleh cekung, tanpa silang)
  /// setebal [depth] ke arah +z, alas di z = 0. Putar lewat [Part] untuk
  /// membuatnya tegak. Sisi tetap datar per ruas (gaya low-poly).
  factory Mesh.extrude(List<Offset> outline, double depth) {
    final pts = signedArea(outline) < 0 ? outline.reversed.toList() : outline;
    final tris = <Tri>[];
    for (final (i, j, k) in triangulate(pts)) {
      final a = pts[i], b = pts[j], c = pts[k];
      tris
        ..add(Tri.flat(V3(a.dx, a.dy, depth), V3(b.dx, b.dy, depth), V3(c.dx, c.dy, depth)))
        ..add(Tri.flat(V3(a.dx, a.dy, 0), V3(c.dx, c.dy, 0), V3(b.dx, b.dy, 0)));
    }
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      final a0 = V3(a.dx, a.dy, 0), b0 = V3(b.dx, b.dy, 0);
      final a1 = V3(a.dx, a.dy, depth), b1 = V3(b.dx, b.dy, depth);
      tris
        ..add(Tri.flat(a0, b0, b1))
        ..add(Tri.flat(a0, b1, a1));
    }
    return Mesh(tris);
  }
}

/// Luas bertanda poligon; positif = berlawanan jarum jam (sumbu y ke atas).
double signedArea(List<Offset> p) {
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length];
    s += a.dx * b.dy - b.dx * a.dy;
  }
  return s / 2;
}

/// Triangulasi ear clipping untuk poligon sederhana berlawanan jarum jam.
/// Mengembalikan indeks titik per segitiga.
List<(int, int, int)> triangulate(List<Offset> p) {
  final idx = List<int>.generate(p.length, (i) => i);
  final out = <(int, int, int)>[];
  double cross(Offset o, Offset a, Offset b) => (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
  bool inside(Offset q, Offset a, Offset b, Offset c) =>
      cross(a, b, q) >= 0 && cross(b, c, q) >= 0 && cross(c, a, q) >= 0;

  var guard = 0;
  while (idx.length > 3 && guard++ < p.length * p.length) {
    var clipped = false;
    for (var n = 0; n < idx.length; n++) {
      final i = idx[(n + idx.length - 1) % idx.length], j = idx[n], k = idx[(n + 1) % idx.length];
      final a = p[i], b = p[j], c = p[k];
      if (cross(a, b, c) <= 0) continue; // sudut cekung
      final blocked = idx.any((m) => m != i && m != j && m != k && inside(p[m], a, b, c));
      if (blocked) continue;
      out.add((i, j, k));
      idx.removeAt(n);
      clipped = true;
      break;
    }
    if (!clipped) break; // poligon rusak: sisanya dikipas
  }
  for (var n = 1; n + 1 < idx.length; n++) {
    out.add((idx[0], idx[n], idx[n + 1]));
  }
  return out;
}

/// Bahan permukaan. [smooth] = normal diinterpolasi (bulat halus, mis. slime);
/// selain itu tiap muka datar (low-poly). [gloss] 0..1 menambah kilap putih;
/// [shininess] makin besar = titik kilap makin kecil & tajam. [inked] = false: part ini tidak diberi garis tinta di batasnya dengan part
/// lain (mis. pipi merona yang menempel di badan); siluet tetap bergaris.
class Material {
  const Material(this.color, {this.smooth = false, this.gloss = 0, this.shininess = 24, this.inked = true});

  final Color color;
  final bool smooth;
  final double gloss, shininess;
  final bool inked;
}

/// Satu bentuk dalam model: mesh + bahan + transformasi
/// (skala → putar x, y, z → geser).
class Part {
  const Part(
    this.mesh,
    this.material, {
    this.at = V3.zero,
    this.scale = const V3(1, 1, 1),
    this.rotX = 0,
    this.rotY = 0,
    this.rotZ = 0,
  });

  final Mesh mesh;
  final Material material;
  final V3 at;
  final V3 scale;
  final double rotX, rotY, rotZ;

  V3 point(V3 p) => p.mul(scale).rotX(rotX).rotY(rotY).rotZ(rotZ) + at;

  /// Normal ikut skala tak seragam lewat invers-transpos (bagi dengan skala).
  V3 normal(V3 n) => V3(n.x / scale.x, n.y / scale.y, n.z / scale.z).rotX(rotX).rotY(rotY).rotZ(rotZ).normalized();
}

/// Model = beberapa [Part]. Tiap part mendapat garis tinta di batasnya.
class Model {
  const Model(this.parts);

  final List<Part> parts;
}
