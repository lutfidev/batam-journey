import 'dart:math' as math;
import 'dart:ui';

import '../../../ui/palette.dart';
import '../bake.dart';
import '../mesh.dart';
import '../../sprites/sprite_sheet.dart';

/// Bangunan kota isometrik (SPBU, bengkel, rumah, kos, villa, ruko, gedung, pabrik).
///
/// Titik (0,0,0) = tengah tapak di tanah. Muka depan menghadap +x; lebar muka
/// ([BuildingInfo.width]) searah y, kedalaman ([BuildingInfo.depth]) searah x.
/// Dipanggang 4 arah (timur, selatan, barat, utara) supaya tapaknya tetap tegak
/// lurus sumbu tanah seperti kota isometrik klasik, dan atlasnya tidak terlalu besar.

/// Ukuran tapak dan titik penting bangunan, dalam koordinat model (depan = +x).
class BuildingInfo {
  const BuildingInfo({
    required this.width,
    required this.depth,
    this.entrance = 0.8,
    this.blockers,
    this.label,
  });

  /// Lebar muka (searah y) dan kedalaman (searah x).
  final double width, depth;

  /// Jarak titik masuk di depan muka depan (pemain berdiri/parkir di sini).
  final double entrance;

  /// Kotak (bidang xy model) yang tidak bisa dilewati; null = seluruh tapak.
  /// SPBU hanya memblokir kios & tiang papan supaya motor bisa masuk ke pompa.
  final List<Rect>? blockers;

  /// Papan nama di muka depan: pusat (model) dan lebar tulisan, untuk teks 2D.
  final ({V3 at, double width})? label;

  /// Seluruh tapak di bidang xy model.
  Rect get footprint => Rect.fromCenter(center: Offset.zero, width: depth, height: width);
}

const _bakePpu = 24.0;

ModelAsset _asset(Model Function(int frame) build, {int frames = 1}) => ModelAsset(
  pixelsPerUnit: _bakePpu,
  directions: 4,
  animations: [SpriteAnim('diam', frames: frames, fps: 0)],
  build: (_, f) => build(f),
);

// ── Bahan ──────────────────────────────────────────────────────────────────
const _cream = Material(Color(0xFFFBF1DE));
const _glass = Material(Color(0xFF86ADC2), gloss: 0.45, shininess: 20);
const _door = Material(Color(0xFF8E6B4A));
const _shopDark = Material(Color(0xFF4A3829));
const _slab = Material(Color(0xFFC45A3C));
const _concrete = Material(Color(0xFFD9D4CB));
const _metal = Material(Color(0xFFA7AFB8), gloss: 0.4, shininess: 24);
const _darkMetal = Material(Color(0xFF5B6470));
const _white = Material(Color(0xFFFFFFFF));
const _red = Material(BColors.atapMerah);
const _tyre = Material(Color(0xFF2B2B30));

// ── Bentuk bantu ───────────────────────────────────────────────────────────

/// Kotak berpusat di ([x], [y]) dengan alas di [z], berukuran [sx]×[sy]×[sz].
Part _box(double x, double y, double z, double sx, double sy, double sz, Material m) =>
    Part(Mesh.box(sx, sy, sz), m, at: V3(x, y, z));

/// Profil (x, z) diekstrusi selebar [w] searah y, berpusat di [y].
Part _prism(List<Offset> xz, double w, Material m, {double y = 0}) =>
    Part(Mesh.extrude(xz, w), m, at: V3(0, y + w / 2, 0), rotX: math.pi / 2);

/// Panel tipis (jendela/pintu) yang menempel di muka [face] tapak [w]×[d]:
/// 0 = +x (depan), 1 = +y, 2 = −x (belakang), 3 = −y. [u] = geseran ke kanan
/// bila dilihat dari luar, [z] = alas panel. Panel menonjol sedikit dari dinding
/// supaya tidak berimpit (z-fighting) dan mendapat garis tinta.
Part _panel(int face, double w, double d, double u, double z, double pw, double ph, Material m) {
  const t = 0.12, out = 0.06;
  return switch (face) {
    0 => _box(d / 2 + out - t / 2, -u, z, t, pw, ph, m),
    1 => _box(u, w / 2 + out - t / 2, z, pw, t, ph, m),
    2 => _box(-d / 2 - out + t / 2, u, z, t, pw, ph, m),
    _ => _box(-u, -w / 2 - out + t / 2, z, pw, t, ph, m),
  };
}

/// Deretan jendela sama besar di muka [face], berjarak rata sepanjang [span].
List<Part> _windows(int face, double w, double d, int n, double z, double pw, double ph, {double? span, double u0 = 0}) {
  final len = span ?? (face.isEven ? w : d) - 1.6;
  return [for (var i = 0; i < n; i++) _panel(face, w, d, u0 + (n == 1 ? 0 : -len / 2 + len * i / (n - 1)), z, pw, ph, _glass)];
}

/// Atap pelana: bubungan searah y, tritisan [eave] keluar dari dinding. Kemiringan
/// di atas ±40° supaya sisi atap belakang tersembunyi dari kamera iso (kalau
/// landai, sisi itu terlihat sangat miring dan seluruhnya jadi garis tinta).
Part _gable(double w, double d, double z, double rise, Material m, {double eave = 0.5}) =>
    _prism([Offset(-d / 2 - eave, z - 0.15), Offset(d / 2 + eave, z - 0.15), Offset(0, z + rise)], w + eave * 2, m);

/// Atap perisai (limasan): limas terpancung di atas tapak [w]×[d] ditambah tritisan.
Part _hip(double w, double d, double z, double rise, Material m, {double eave = 0.5, double top = 0.3}) {
  final a = d / 2 + eave, b = w / 2 + eave, ta = a * top, tb = b * top, h = rise;
  final tris = <Tri>[];
  void quad(V3 p, V3 q, V3 r, V3 s) => tris
    ..add(Tri.flat(p, q, r))
    ..add(Tri.flat(p, r, s));
  quad(V3(a, -b, 0), V3(a, b, 0), V3(ta, tb, h), V3(ta, -tb, h)); // +x
  quad(V3(a, b, 0), V3(-a, b, 0), V3(-ta, tb, h), V3(ta, tb, h)); // +y
  quad(V3(-a, b, 0), V3(-a, -b, 0), V3(-ta, -tb, h), V3(-ta, tb, h)); // −x
  quad(V3(-a, -b, 0), V3(a, -b, 0), V3(ta, -tb, h), V3(-ta, -tb, h)); // −y
  quad(V3(-ta, -tb, h), V3(ta, -tb, h), V3(ta, tb, h), V3(-ta, tb, h)); // atas
  quad(V3(-a, -b, 0), V3(-a, b, 0), V3(a, b, 0), V3(a, -b, 0)); // bawah
  return Part(Mesh(tris), m, at: V3(0, 0, z - 0.1));
}

// ── SPBU ───────────────────────────────────────────────────────────────────

/// SPBU BensinKu: kanopi merah-putih, dua pulau pompa, kios, dan tiang papan.
const spbuInfo = BuildingInfo(
  width: 15,
  depth: 13,
  entrance: -5.0, // di bawah kanopi, di antara pulau pompa
  blockers: [Rect.fromLTWH(-6.5, -4.6, 3.6, 9.2), Rect.fromLTWH(5.6, 5.3, 0.9, 2.4)],
  label: (at: V3(6.12, 0, 5.25), width: 5),
);

final spbuAsset = _asset((_) {
  const cx = 1.5, top = 5.0;
  return Model([
    // Lantai beton di bawah kanopi.
    _box(cx, 0, 0, 9.6, 13.4, 0.08, _concrete),
    // Pulau pompa + pompa.
    for (final y in const [-2.8, 2.8]) ...[
      _box(cx, y, 0.08, 5.0, 1.1, 0.25, _metal),
      for (final x in const [-1.3, 1.3]) ...[
        _box(cx + x, y, 0.33, 0.8, 0.7, 1.7, const Material(BColors.cream)),
        _box(cx + x + 0.41, y, 1.25, 0.06, 0.5, 0.5, Material(y < 0 ? BColors.kuning : BColors.tosca)),
      ],
    ],
    // Tiang kanopi.
    for (final x in const [-2.6, 2.6])
      for (final y in const [-5.2, 5.2])
        Part(Mesh.cylinder(0.28, top, segments: 8), _white, at: V3(cx + x, y, 0)),
    // Kanopi: pita merah di bawah, pelat putih di atas.
    _box(cx, 0, top, 9.2, 13.2, 0.5, _red),
    _box(cx, 0, top + 0.5, 9.0, 13.0, 0.45, _white),
    // Kios di belakang.
    _box(-4.7, 0, 0, 3.6, 9.2, 3.0, _cream),
    _box(-4.7, 0, 3.0, 4.0, 9.6, 0.35, _red),
    ..._windows(0, 9.2, 3.6, 3, 0.9, 1.8, 1.4, span: 5.6, u0: 0).map((p) => _shift(p, -4.7, 0)),
    _shift(_panel(0, 9.2, 3.6, 3.3, 0, 1.2, 2.2, _glass), -4.7, 0),
    // Tiang papan harga di pojok depan.
    _box(6.05, 6.5, 0, 0.5, 0.5, 4.5, _darkMetal),
    _box(6.05, 6.5, 4.5, 0.6, 2.2, 3.0, _red),
    _box(6.4, 6.5, 4.85, 0.06, 1.6, 1.0, _white),
    _box(6.4, 6.5, 6.05, 0.06, 1.6, 1.0, const Material(BColors.kuning)),
  ]);
});

/// Part yang digeser di bidang xy.
Part _shift(Part p, double dx, double dy) =>
    Part(p.mesh, p.material, at: p.at + V3(dx, dy, 0), scale: p.scale, rotX: p.rotX, rotY: p.rotY, rotZ: p.rotZ);

// ── Bengkel ────────────────────────────────────────────────────────────────

/// Bengkel motor: pintu gulung terbuka, atap datar biru, papan oranye, tumpukan ban.
const bengkelInfo = BuildingInfo(width: 10, depth: 8, entrance: 1.2, label: (at: V3(4.52, 0.6, 3.75), width: 5.2));

final bengkelAsset = _asset((_) {
  const w = 10.0, d = 8.0, h = 4.6;
  return Model([
    _box(0, 0, 0, d, w, h, const Material(Color(0xFFEDE3D3))),
    _box(0.4, 0, h, d + 0.8, w + 0.4, 0.4, const Material(BColors.biruPemain)),
    // Bukaan bengkel (gelap) dengan pintu gulung tergulung di atasnya.
    _panel(0, w, d, -0.6, 0, 6.6, 2.7, const Material(Color(0xFF3A3330))),
    _panel(0, w, d, -0.6, 2.7, 6.6, 0.4, _metal),
    _panel(0, w, d, 3.8, 0.9, 1.4, 1.3, _glass),
    // Papan nama oranye, menonjol di bawah tritisan atap.
    _box(d / 2 + 0.35, 0.6, 3.25, 0.3, 6.2, 1.0, const Material(BColors.oranye)),
    ..._windows(1, w, d, 2, 1.4, 1.5, 1.2),
    ..._windows(3, w, d, 2, 1.4, 1.5, 1.2),
    // Tumpukan ban di samping pintu.
    for (var i = 0; i < 3; i++)
      Part(Mesh.cylinder(0.55, 0.32, segments: 10), _tyre, at: V3(d / 2 + 0.75, w / 2 - 0.9, i * 0.34)),
    // Drum oli.
    Part(Mesh.cylinder(0.42, 1.1, segments: 10), _red, at: V3(d / 2 + 0.7, w / 2 - 2.2, 0)),
  ]);
});

// ── Rumah ──────────────────────────────────────────────────────────────────

/// Warna atap rumah per frame: subsidi, cluster, lalu variasi untuk blok kota.
const rumahRoofs = [BColors.oranye, BColors.atapMerah, Color(0xFF6A8CC7), Color(0xFF5E9E6E), Color(0xFFB07A4F)];

const rumahInfo = BuildingInfo(width: 7.6, depth: 7.0, entrance: 1.0);

final rumahAsset = _asset(frames: rumahRoofs.length, (f) {
  const w = 7.6, d = 7.0, h = 3.2;
  return Model([
    _box(0, 0, 0, d, w, h, _cream),
    _gable(w, d, h, 3.4, Material(rumahRoofs[f])),
    // Pintu, jendela depan, teras.
    _panel(0, w, d, 0.6, 0, 1.1, 2.1, _door),
    _panel(0, w, d, -2.0, 0.9, 1.4, 1.1, _glass),
    _panel(0, w, d, 2.5, 0.9, 1.1, 1.1, _glass),
    _box(d / 2 + 0.35, 0.6, 0, 0.7, 1.8, 0.18, _concrete),
    ..._windows(1, w, d, 2, 0.9, 1.1, 1.1),
    ..._windows(3, w, d, 2, 0.9, 1.1, 1.1),
    ..._windows(2, w, d, 2, 0.9, 1.2, 1.1),
  ]);
});

// ── Kos ────────────────────────────────────────────────────────────────────

/// Kos Bu Ros: dua lantai memanjang, selasar atas berpagar, deretan pintu kamar.
const kosInfo = BuildingInfo(width: 12, depth: 7.5, entrance: 1.2);

final kosAsset = _asset((_) {
  const w = 12.0, d = 7.5, h = 6.4;
  const doors = [-4.2, 0.0, 4.2];
  return Model([
    _box(0, 0, 0, d, w, h, const Material(Color(0xFFF6E2C4))),
    _gable(w, d, h, 3.8, const Material(BColors.oranye)),
    // Selasar lantai 2 + pagar.
    _box(d / 2 + 0.7, 0, 3.0, 1.4, w, 0.25, _concrete),
    _box(d / 2 + 1.35, 0, 3.25, 0.12, w, 0.9, _white),
    for (final u in doors) ...[
      _panel(0, w, d, u, 0, 1.0, 2.1, _door),
      _panel(0, w, d, u + 1.5, 1.0, 1.0, 0.9, _glass),
      _panel(0, w, d, u, 3.25, 1.0, 2.1, _door),
      _panel(0, w, d, u + 1.5, 4.25, 1.0, 0.9, _glass),
    ],
    // Tangga di sisi kanan.
    _prism(const [Offset(2.0, 0), Offset(4.6, 0), Offset(4.6, 0.3), Offset(2.3, 3.0), Offset(2.0, 3.0)], 1.0, _concrete, y: w / 2 + 0.55),
    ..._windows(2, w, d, 4, 1.0, 1.1, 1.0),
    ..._windows(2, w, d, 4, 4.2, 1.1, 1.0),
  ]);
});

// ── Villa ──────────────────────────────────────────────────────────────────

/// Villa tepi laut: lebar, atap limasan tosca, kaca besar, teras kayu.
const villaInfo = BuildingInfo(width: 11, depth: 9, entrance: 1.6);

final villaAsset = _asset((_) {
  const w = 11.0, d = 9.0, h = 3.6;
  return Model([
    _box(0, 0, 0, d, w, h, _white),
    _hip(w, d, h, 2.6, const Material(BColors.tosca)),
    _box(d / 2 + 0.8, 0, 0, 1.6, w - 1.0, 0.3, const Material(Color(0xFFB07A4F))),
    _panel(0, w, d, -2.4, 0.3, 3.6, 2.4, _glass),
    _panel(0, w, d, 1.2, 0.3, 1.2, 2.3, _door),
    _panel(0, w, d, 3.6, 0.9, 1.8, 1.4, _glass),
    ..._windows(1, w, d, 2, 0.9, 1.8, 1.4),
    ..._windows(3, w, d, 2, 0.9, 1.8, 1.4),
    ..._windows(2, w, d, 3, 0.9, 1.6, 1.4),
  ]);
});

// ── Ruko ───────────────────────────────────────────────────────────────────

/// Warna (kanopi, dinding) ruko per frame. Frame 0–3 = usaha kopi, warung,
/// laundry, kurir; sisanya variasi blok kota.
const rukoColors = [
  (BColors.hijauAksi, Color(0xFFF6E8CC)),
  (BColors.atapMerah, Color(0xFFF6D7B0)),
  (BColors.tosca, Color(0xFFFBF5EA)),
  (BColors.kuning, Color(0xFFDDE6EA)),
  (BColors.oranye, Color(0xFFF3E3C3)),
  (Color(0xFF6A8CC7), Color(0xFFF4D4CF)),
];

/// Ruko dua lantai selebar 6,4 unit; berderet rapat tanpa celah di blok kota.
const rukoInfo = BuildingInfo(width: 6.4, depth: 9, entrance: 1.0, label: (at: V3(4.67, 0, 3.92), width: 4.4));

final rukoAsset = _asset(frames: rukoColors.length, (f) {
  const w = 6.4, d = 9.0, h = 7.0;
  final (awning, wall) = rukoColors[f];
  const stripes = 5;
  const sw = (w - 0.3) / stripes;
  return Model([
    _box(0, 0, 0, d, w, h, Material(wall)),
    _box(0, 0, h, d, w, 0.6, _slab),
    // Etalase toko (gelap) dengan kaca, lalu kanopi bergaris.
    _panel(0, w, d, 0, 0, w - 1.0, 2.9, _shopDark),
    _box(d / 2 + 0.08, -0.6, 0.25, 0.06, w - 2.6, 2.2, _glass),
    for (var i = 0; i < stripes; i++)
      _prism(
        [Offset(d / 2, 3.45), Offset(d / 2 + 1.5, 2.95), Offset(d / 2 + 1.5, 2.75), Offset(d / 2, 3.2)],
        sw,
        i.isEven ? Material(awning) : const Material(BColors.cream),
        y: -w / 2 + 0.15 + sw * (i + 0.5),
      ),
    // Papan nama (gelap) di atas kanopi; teks digambar 2D untuk usaha milik pemain.
    _box(d / 2 + 0.08, 0, 3.55, 0.16, w - 1.8, 0.75, const Material(BColors.ink)),
    // Lantai atas: jendela dengan ambang.
    ..._windows(0, w, d, 2, 4.8, 1.5, 1.6, span: 3.0),
    for (final u in const [-1.5, 1.5]) _box(d / 2 + 0.2, -u, 4.62, 0.4, 1.8, 0.14, _concrete),
    // Belakang: pintu, jendela berteralis, dan AC.
    ..._windows(2, w, d, 2, 4.8, 1.2, 1.4, span: 3.0),
    _panel(2, w, d, -1.6, 0, 1.1, 2.2, _door),
    _panel(2, w, d, 1.2, 1.0, 1.6, 1.2, _glass),
    _box(-d / 2 - 0.3, 1.4, 3.0, 0.6, 1.1, 0.7, const Material(Color(0xFFE8ECEF))),
    // Toren air oranye di atap.
    Part(Mesh.cylinder(0.6, 1.3, segments: 10), const Material(BColors.oranye, gloss: 0.3), at: V3(-2.4, -1.2, h + 0.6)),
  ]);
});

// ── Gedung ─────────────────────────────────────────────────────────────────

/// Gedung bertingkat: kantor kaca biru dan apartemen krem berbalkon.
const gedungInfo = BuildingInfo(width: 9, depth: 9, entrance: 1.2);
const _floors = 6;
const _floorH = 3.4;

final gedungAsset = _asset(frames: 2, (f) {
  const w = 9.0, d = 9.0, h = _floors * _floorH;
  final office = f == 0;
  final wall = Material(office ? const Color(0xFFE4E8EE) : const Color(0xFFF3E3C3));
  return Model([
    _box(0, 0, 0, d, w, h, wall),
    // Lobi kaca di lantai dasar.
    _panel(0, w, d, 0, 0, 4.0, 2.6, _glass),
    _box(d / 2 + 0.6, 0, 2.7, 1.2, 5.0, 0.2, _concrete),
    for (var i = 1; i < _floors; i++)
      if (office)
        // Pita kaca melingkar per lantai.
        _box(0, 0, i * _floorH + 0.8, d + 0.12, w + 0.12, 1.7, _glass)
      else ...[
        for (final face in const [0, 1, 2, 3]) ..._windows(face, w, d, 3, i * _floorH + 0.9, 1.3, 1.5),
        _box(d / 2 + 0.35, 0, i * _floorH + 0.2, 0.7, 3.0, 0.15, _concrete),
      ],
    // Atap: dak, tandon air, ruang mesin lift.
    _box(0, 0, h, d + 0.2, w + 0.2, 0.5, office ? _darkMetal : _slab),
    Part(Mesh.cylinder(0.8, 1.5, segments: 10), _metal, at: const V3(-2.2, 2.2, h + 0.5)),
    _box(1.5, -1.5, h + 0.5, 2.4, 2.4, 1.6, _concrete),
  ]);
});

// ── Pabrik ─────────────────────────────────────────────────────────────────

/// Pabrik/gudang kawasan industri: dinding ungu industri, atap gergaji, cerobong.
const pabrikInfo = BuildingInfo(width: 16, depth: 12, entrance: 1.5);

final pabrikAsset = _asset((_) {
  const w = 16.0, d = 12.0, h = 5.5;
  const teeth = 3;
  const tw = d / teeth;
  // Profil gergaji: tiap gigi naik tegak lalu turun miring ke gigi berikutnya.
  final saw = <Offset>[const Offset(-d / 2, h - 0.05)];
  for (var i = 0; i < teeth; i++) {
    final x = -d / 2 + i * tw;
    saw.add(Offset(x, h + 1.8));
    saw.add(Offset(x + tw, h - 0.05));
  }
  return Model([
    _box(0, 0, 0, d, w, h, const Material(BColors.industri)),
    _prism(saw, w, const Material(Color(0xFF8E7FA6))),
    // Pintu bongkar muat & kantor kecil di depan.
    _panel(0, w, d, -3.0, 0, 5.0, 4.0, _metal),
    _box(d / 2 + 1.2, 4.6, 0, 2.4, 4.8, 3.0, _cream),
    _box(d / 2 + 2.45, 4.6, 1.0, 0.1, 3.4, 1.2, _glass),
    ..._windows(1, w, d, 4, 2.6, 1.6, 1.2),
    ..._windows(3, w, d, 4, 2.6, 1.6, 1.2),
    // Cerobong.
    Part(Mesh.cylinder(0.5, 4.5, segments: 10), const Material(Color(0xFFB9B2C4)), at: const V3(-4.0, -5.8, h)),
    _box(-4.0, -5.8, h + 3.6, 1.1, 1.1, 0.4, _red),
  ]);
});
