import 'dart:math' as math;
import 'dart:ui';

import '../map/land_mask.dart';
import '../map/road_graph.dart';
import '../model3d/models/buildings.dart';
import '../model3d/models/props.dart';
import '../sprites/sprite_library.dart';

/// Penempatan kota prosedural: bangunan di sepanjang jalan menurut kepadatan
/// jalan, pohon di lahan kosong, dan lampu di trotoar jalan besar. Semuanya
/// deterministik (benih dari indeks jalan/sel), murni Dart supaya bisa
/// dijalankan di isolate lain dan dites tanpa game.

/// Ukuran chunk kota & tanah: 1 km × 1 km pada skala game.
const double chunkSize = 1000 * worldScale;

/// Jarak bangunan dari tepi aspal (trotoar + halaman).
const double buildingSetback = 2.4;

/// Satu benda kota yang akan digambar.
class PropSpec {
  const PropSpec({
    required this.sprite,
    required this.at,
    this.frame = 0,
    this.dir = 0,
    this.footprint,
    this.blockers = const [],
    this.scale = 1,
  });

  final String sprite;
  final int frame;

  /// Arah atlas (bangunan: 0 = timur … 3 = utara; lampu: 16 arah).
  final int dir;

  /// Titik pijak di tanah.
  final Offset at;

  /// Tapak bangunan di tanah (kotak tegak lurus sumbu), untuk urutan gambar & jarak.
  final Rect? footprint;

  /// Kotak tanah yang tidak bisa dilewati pemain/motor.
  final List<Rect> blockers;
  final double scale;

  /// Kunci urutan gambar: makin besar makin depan (dekat kamera).
  double get depthKey => footprint == null ? at.dx + at.dy : footprint!.center.dx + footprint!.center.dy;
}

/// Vektor satuan arah hadap bangunan 4 arah (0 = timur, 1 = selatan, 2 = barat, 3 = utara).
Offset facingVector(int f) => const [Offset(1, 0), Offset(0, 1), Offset(-1, 0), Offset(0, -1)][f & 3];

/// Arah hadap 4 arah yang paling dekat dengan vektor tanah [v].
int facingOf(Offset v) => v.dx.abs() >= v.dy.abs() ? (v.dx >= 0 ? 0 : 2) : (v.dy >= 0 ? 1 : 3);

/// Titik model (x maju, y kanan) → titik tanah untuk bangunan menghadap [f] di [at].
Offset modelToGround(Offset p, int f, Offset at) => at + switch (f & 3) {
  0 => p,
  1 => Offset(-p.dy, p.dx),
  2 => Offset(-p.dx, -p.dy),
  _ => Offset(p.dy, -p.dx),
};

/// Kotak model [r] → kotak tanah untuk bangunan menghadap [f] di [at].
Rect modelRectToGround(Rect r, int f, Offset at) =>
    Rect.fromPoints(modelToGround(r.topLeft, f, at), modelToGround(r.bottomRight, f, at));

/// Lokasi bangunan: pusat tapak, arah hadap, dan tapaknya di tanah.
class Site {
  const Site(this.center, this.facing, this.info);

  final Offset center;
  final int facing;
  final BuildingInfo info;

  Rect get footprint => modelRectToGround(info.footprint, facing, center);

  /// Titik masuk (tempat pemain berdiri/parkir) di depan muka depan.
  Offset get entrance => modelToGround(Offset(info.depth / 2 + info.entrance, 0), facing, center);

  List<Rect> get blockers => [for (final b in info.blockers ?? [info.footprint]) modelRectToGround(b, facing, center)];
}

/// Jarak terpendek dari ruas [a]–[b] ke kotak [r] (0 bila bersentuhan).
double segmentRectDistance(Offset a, Offset b, Rect r) {
  if (r.contains(a) || r.contains(b) || _segmentHitsRect(a, b, r)) return 0;
  double ptRect(Offset p) {
    final dx = math.max(math.max(r.left - p.dx, 0.0), p.dx - r.right);
    final dy = math.max(math.max(r.top - p.dy, 0.0), p.dy - r.bottom);
    return math.sqrt(dx * dx + dy * dy);
  }

  double ptSeg(Offset p) {
    final ab = b - a;
    final len2 = ab.distanceSquared;
    final t = len2 == 0 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  return [ptRect(a), ptRect(b), ptSeg(r.topLeft), ptSeg(r.topRight), ptSeg(r.bottomLeft), ptSeg(r.bottomRight)]
      .reduce(math.min);
}

bool _segmentHitsRect(Offset a, Offset b, Rect r) {
  // Liang–Barsky: potong ruas dengan kotak.
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

  return clip(-d.dx, a.dx - r.left) &&
      clip(d.dx, r.right - a.dx) &&
      clip(-d.dy, a.dy - r.top) &&
      clip(d.dy, r.bottom - a.dy);
}

/// Jarak tapak [r] ke tepi aspal terdekat (negatif = menimpa aspal).
double roadClearanceOfRect(RoadGraph g, Rect r, {double maxDist = 20}) {
  var best = maxDist;
  for (final s in g.segmentsIn(r.inflate(maxDist))) {
    final d = segmentRectDistance(s.a, s.b, r) - s.edge.width / 2;
    if (d < best) best = d;
  }
  return best;
}

/// Kumpulan kotak terpakai dengan grid spasial, untuk cek tumpang tindih cepat.
class RectIndex {
  RectIndex([this.cell = 20]);

  final double cell;
  final _grid = <int, List<Rect>>{};

  int _key(int cx, int cy) => cx * 100000 + cy;

  void add(Rect r) {
    for (var cx = (r.left / cell).floor(); cx <= (r.right / cell).floor(); cx++) {
      for (var cy = (r.top / cell).floor(); cy <= (r.bottom / cell).floor(); cy++) {
        (_grid[_key(cx, cy)] ??= []).add(r);
      }
    }
  }

  /// Ada kotak yang menimpa [r] (bersentuhan tepi tidak dihitung).
  bool overlaps(Rect r) {
    for (var cx = (r.left / cell).floor(); cx <= (r.right / cell).floor(); cx++) {
      for (var cy = (r.top / cell).floor(); cy <= (r.bottom / cell).floor(); cy++) {
        for (final o in _grid[_key(cx, cy)] ?? const <Rect>[]) {
          if (o.left < r.right - 1e-6 && r.left < o.right - 1e-6 && o.top < r.bottom - 1e-6 && r.top < o.bottom - 1e-6) {
            return true;
          }
        }
      }
    }
    return false;
  }

  bool contains(Offset p) {
    for (final o in _grid[_key((p.dx / cell).floor(), (p.dy / cell).floor())] ?? const <Rect>[]) {
      if (o.contains(p)) return true;
    }
    return false;
  }
}

/// Lokasi untuk bangunan [info] di pinggir jalan terdekat dari [near], di sisi
/// tempat [near] berada. Mencoba geser sepanjang jalan bila tempatnya terpakai
/// ([taken]) atau menimpa jalan lain. Null bila tidak ada jalan di dekatnya.
Site? siteBeside(RoadGraph g, Offset near, BuildingInfo info, {RectIndex? taken, LandMask? mask, double maxDist = 400}) {
  final hit = g.nearest(near, maxDist: maxDist);
  if (hit == null) return null;
  final s = hit.segment;
  final onRoad = s.closestPoint(near);
  final t = (s.b - s.a) / s.length;
  var n = Offset(-t.dy, t.dx);
  final away = near - onRoad;
  if (away.dx * n.dx + away.dy * n.dy < 0) n = -n;
  final step = math.max(info.width, info.depth) + 2;
  Site? fallback;
  for (final k in const [0, 1, -1, 2, -2, 3, -3, 4, -4]) {
    final site = _siteAt(onRoad + t * (k * step), n, s.edge.width, info);
    fallback ??= site;
    if (_fits(g, site, taken, mask)) return site;
  }
  return fallback;
}

/// Bangunan menghadap jalan di titik [p] (di as jalan) pada sisi normal [n],
/// [behind] unit lebih jauh dari jalan daripada baris depan.
Site _siteAt(Offset p, Offset n, double roadWidth, BuildingInfo info, {double behind = 0}) {
  final f = facingOf(-n);
  final hx = (f.isEven ? info.depth : info.width) / 2, hy = (f.isEven ? info.width : info.depth) / 2;
  final support = hx * n.dx.abs() + hy * n.dy.abs();
  return Site(p + n * (roadWidth / 2 + buildingSetback + behind + support), f, info);
}

bool _fits(RoadGraph g, Site site, RectIndex? taken, LandMask? mask) {
  final r = site.footprint;
  if (taken != null && taken.overlaps(r.inflate(0.5))) return false;
  if (mask != null && ![r.topLeft, r.topRight, r.bottomLeft, r.bottomRight, r.center].every(mask.isLand)) return false;
  return roadClearanceOfRect(g, r) >= buildingSetback - 0.6;
}

/// Zona kota per sel, dari kepadatan jalan dan nama kawasan industri.
enum Zone { kota, pinggir, desa, industri }

/// Kawasan industri Batam (kelurahan terdekat).
const industrialPlaces = {'Muka Kuning', 'Tanjung Uncang', 'Kabil', 'Batu Merah', 'Sungai Binti'};

class ZoneMap {
  ZoneMap(this.graph) {
    for (final s in graph.segments) {
      if (s.edge.type.endsWith('_link')) continue;
      final m = (s.a + s.b) / 2;
      final k = _key((m.dx / cell).floor(), (m.dy / cell).floor());
      _len[k] = (_len[k] ?? 0) + s.length;
    }
  }

  final RoadGraph graph;
  static const cell = 100.0;
  final _len = <int, double>{};
  final _zone = <int, Zone>{};

  int _key(int cx, int cy) => cx * 100000 + cy;

  /// Panjang jalan (unit) per 100×100 unit, dirata-rata dengan 8 sel tetangga.
  double density(Offset p) {
    final cx = (p.dx / cell).floor(), cy = (p.dy / cell).floor();
    var sum = 0.0;
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        sum += _len[_key(cx + dx, cy + dy)] ?? 0;
      }
    }
    return sum / 9;
  }

  Zone at(Offset p) {
    final cx = (p.dx / cell).floor(), cy = (p.dy / cell).floor();
    return _zone[_key(cx, cy)] ??= () {
      final c = Offset((cx + 0.5) * cell, (cy + 0.5) * cell);
      final d = density(c);
      if (d >= 60 && industrialPlaces.contains(graph.nearestPlaceName(c))) return Zone.industri;
      if (d >= 150) return Zone.kota;
      if (d >= 70) return Zone.pinggir;
      return Zone.desa;
    }();
  }
}

/// Satu jenis bangunan yang bisa dipilih generator.
class _Kind {
  const _Kind(this.sprite, this.info, this.frames, {this.row = false});

  final String sprite;
  final BuildingInfo info;

  /// Frame yang boleh dipakai (variasi warna).
  final List<int> frames;

  /// Berderet rapat tanpa celah (ruko).
  final bool row;
}

const _ruko = _Kind(SpriteIds.ruko, rukoInfo, [1, 2, 3, 4, 5, 0], row: true);
const _rumah = _Kind(SpriteIds.rumah, rumahInfo, [0, 1, 2, 3, 4]);
const _gedung = _Kind(SpriteIds.gedung, gedungInfo, [0, 1]);
const _pabrik = _Kind(SpriteIds.pabrik, pabrikInfo, [0]);

/// Peluang (kumulatif kasar) tiap jenis per zona; sisanya lahan kosong.
const _mix = {
  Zone.kota: [(_ruko, 0.62), (_gedung, 0.12), (_rumah, 0.1)],
  Zone.pinggir: [(_rumah, 0.45), (_ruko, 0.2)],
  Zone.desa: [(_rumah, 0.22)],
  Zone.industri: [(_pabrik, 0.5), (_ruko, 0.1), (_rumah, 0.05)],
};

/// Bangunan blok kota di sepanjang semua jalan (kecuali jembatan & ramp),
/// menghindari [reserved] (SPBU, bengkel, rumah, ruko usaha) dan laut.
List<PropSpec> generateBuildings(RoadGraph g, LandMask mask, List<Rect> reserved) {
  final zones = ZoneMap(g);
  final taken = RectIndex();
  for (final r in reserved) {
    taken.add(r.inflate(1.5));
  }
  final out = <PropSpec>[];
  for (final e in g.edges) {
    if (e.bridge || e.type.endsWith('_link') || e.pts.length < 2) continue;
    for (final side in const [1.0, -1.0]) {
      final rnd = math.Random(e.index * 2 + (side > 0 ? 1 : 0));
      _Kind? prev;
      var s = 3.0 + rnd.nextDouble() * 4;
      while (s < e.length - 3) {
        final (p, t) = _pointAt(e.pts, s);
        final n = Offset(-t.dy, t.dx) * side;
        final zone = zones.at(p);
        final roll = rnd.nextDouble();
        _Kind? kind;
        var acc = 0.0;
        for (final (k, chance) in _mix[zone]!) {
          acc += chance;
          if (roll < acc) {
            kind = k;
            break;
          }
        }
        // Deretan ruko cenderung berlanjut supaya terlihat seperti blok pertokoan.
        final keepRow = switch (zone) {
          Zone.kota => 0.7,
          Zone.industri || Zone.pinggir => 0.35,
          Zone.desa => 0.0,
        };
        if (prev != null && prev.row && rnd.nextDouble() < keepRow) kind = prev;
        if (kind == null) {
          prev = null;
          s += 6 + rnd.nextDouble() * 8;
          continue;
        }
        final site = _siteAt(p, n, e.width, kind.info);
        if (!_fits(g, site, taken, mask)) {
          prev = null;
          s += 2;
          continue;
        }
        final r = site.footprint;
        void place(Site site, _Kind kind) {
          taken.add(site.footprint);
          out.add(
            PropSpec(
              sprite: kind.sprite,
              frame: kind.frames[rnd.nextInt(kind.frames.length)],
              dir: site.facing,
              at: site.center,
              footprint: site.footprint,
              blockers: site.blockers,
            ),
          );
        }

        place(site, kind);
        // Baris kedua (rumah di belakang deretan depan) supaya dalam blok tidak kosong.
        final backRow = switch (zone) {
          Zone.kota => 0.65,
          Zone.pinggir => 0.35,
          _ => 0.0,
        };
        if (rnd.nextDouble() < backRow) {
          final depth = r.width * n.dx.abs() + r.height * n.dy.abs();
          final back = _siteAt(p, n, e.width, _rumah.info, behind: depth + 2 + rnd.nextDouble() * 2);
          if (_fits(g, back, taken, mask)) place(back, _rumah);
        }
        // Maju sejauh lebar tapak searah jalan; ruko berderet tanpa celah.
        final along = r.width * t.dx.abs() + r.height * t.dy.abs();
        final gap = kind.row && prev == kind ? 0.0 : 1.5 + rnd.nextDouble() * 3;
        s += along + gap;
        prev = kind;
      }
    }
  }
  return out;
}

/// Titik & arah satuan di jarak [s] sepanjang polyline [pts].
(Offset, Offset) _pointAt(List<Offset> pts, double s) {
  for (var i = 0; i + 1 < pts.length; i++) {
    final a = pts[i], b = pts[i + 1];
    final len = (b - a).distance;
    if (len == 0) continue;
    if (s <= len || i + 2 == pts.length) {
      final t = (b - a) / len;
      return (a + t * math.min(s, len), t);
    }
    s -= len;
  }
  return (pts.last, const Offset(1, 0));
}

/// Pohon & lampu jalan di satu chunk ([cx], [cy]); dibuat saat chunk pertama
/// kali terlihat. [blocked] = di dalam tapak bangunan.
List<PropSpec> generateChunkDecor(
  RoadGraph g,
  LandMask mask,
  ZoneMap zones,
  int cx,
  int cy, {
  required bool Function(Rect) nearBuilding,
}) {
  final out = <PropSpec>[];
  final chunk = Rect.fromLTWH(cx * chunkSize, cy * chunkSize, chunkSize, chunkSize);

  // Pohon: per sel 20×20, lebih rimbun di desa, jarang di kota.
  const cell = 20.0;
  final n = (chunkSize / cell).round();
  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      final gx = cx * n + i, gy = cy * n + j;
      final rnd = math.Random((gx * 73856093) ^ (gy * 19349663));
      final c = Offset((gx + 0.5) * cell, (gy + 0.5) * cell);
      if (!mask.isLand(c) && !mask.isLand(c + const Offset(9, 9))) continue;
      final zone = zones.at(c);
      final count = switch (zone) {
        Zone.desa => 2 + rnd.nextInt(4),
        Zone.pinggir => 1 + rnd.nextInt(3),
        Zone.industri => rnd.nextInt(2),
        Zone.kota => rnd.nextInt(2),
      };
      for (var k = 0; k < count; k++) {
        final pos = Offset((gx + rnd.nextDouble()) * cell, (gy + rnd.nextDouble()) * cell);
        final scale = 0.85 + rnd.nextDouble() * 0.45;
        final r = 1.6 * scale;
        final frameRoll = rnd.nextDouble();
        final dir = rnd.nextInt(4);
        if (!mask.isLand(pos) || !mask.isLand(pos + Offset(r, r)) || !mask.isLand(pos - Offset(r, r))) continue;
        if (g.clearance(pos, maxDist: 12) <= r + 2.0) continue;
        if (nearBuilding(Rect.fromCircle(center: pos, radius: r + 0.5))) continue;
        // Dekat pantai lebih banyak kelapa.
        final coast = !mask.isLand(pos + const Offset(15, 0)) || !mask.isLand(pos - const Offset(15, 0)) ||
            !mask.isLand(pos + const Offset(0, 15)) || !mask.isLand(pos - const Offset(0, 15));
        final frame = coast && frameRoll < 0.6
            ? PohonFrame.kelapa
            : frameRoll < 0.4
            ? PohonFrame.bulat
            : frameRoll < 0.72
            ? PohonFrame.rimbun
            : frameRoll < 0.87
            ? PohonFrame.cemara
            : PohonFrame.kelapa;
        out.add(PropSpec(sprite: SpriteIds.pohon, frame: frame, dir: dir, at: pos, scale: scale));
      }
    }
  }

  // Lampu jalan tiap 30 unit di jalan besar, berselang kiri-kanan.
  const spacing = 30.0;
  for (final s in g.segmentsIn(chunk)) {
    final e = s.edge;
    final base = e.type.replaceAll('_link', '');
    if (e.type.endsWith('_link') || !(base == 'trunk' || base == 'primary' || base == 'secondary')) continue;
    final t = (s.b - s.a) / s.length;
    final normal = Offset(-t.dy, t.dx);
    var k = (s.startDist / spacing).ceil();
    while (k * spacing < s.startDist + s.length) {
      final side = k.isEven ? 1.0 : -1.0;
      final p = s.a + t * (k * spacing - s.startDist) + normal * (side * (e.width / 2 + 0.7));
      k++;
      if (!chunk.contains(p) || !mask.isLand(p)) continue;
      // Jangan di simpang (di atas aspal jalan lain) atau di dalam bangunan.
      if (g.clearance(p, maxDist: 12) < 0.4) continue;
      if (nearBuilding(Rect.fromCircle(center: p, radius: 0.4))) continue;
      final toRoad = -normal * side;
      final heading = math.atan2(toRoad.dy, toRoad.dx);
      final dir = (heading / (2 * math.pi / 16)).round() % 16;
      out.add(PropSpec(sprite: SpriteIds.lampuJalan, dir: dir, at: p));
    }
  }
  return out;
}
