import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../ui/palette.dart';
import '../batam_game.dart';
import '../iso.dart';
import '../city/city_gen.dart' show chunkSize;
import 'ground_mesh.dart';
import 'land_mask.dart';
import 'road_graph.dart';

/// Menggambar laut, tanah, dan jalan. Lantai tiap chunk 1×1 km dipecah jadi
/// segitiga sekali saja (dicache sebagai [GroundMesh] per lapis), lalu tiap frame
/// hanya chunk yang terlihat yang digambar. Impeller men-tessellate ulang path &
/// garis tebal setiap frame, jadi segitiga siap pakai jauh lebih ringan. Satu
/// mesh per chunk (bukan ubin kecil) karena di HP biaya utamanya jumlah draw
/// call, bukan segitiga di luar layar.
/// Urutan lapis: laut dangkal → darat → trotoar semua jalan → aspal → marka &
/// zebra cross, digambar lapis demi lapis di semua chunk supaya simpang dan batas
/// chunk menyatu tanpa klip. Lantai digambar di koordinat tanah lewat [isoMatrix];
/// hanya rute GPS yang digambar langsung.
class RoadLayer extends Component with HasGameReference<BatamGame> {
  RoadLayer(this.graph, this.mask) : super(priority: -1000000000);

  final RoadGraph graph;

  /// Mask darat/laut. Dipakai juga oleh pemain, motor, dan kota.
  final LandMask mask;

  static const _curb = 1.2;
  static const _dash = 2.2;
  static const _gap = 1.6;
  static const _markWidth = 0.35;

  static const _shallowColor = Color(0xFF7FCCDA);
  static const _zebraColor = Color(0xFFF4F1EA);

  /// Chunk yang disimpan paling banyak; yang paling lama tidak terlihat dibuang.
  static const maxChunks = 24;

  /// Jumlah lapis per chunk (laut dangkal, darat, trotoar, aspal, marka).
  static const layers = 5;

  /// Kunci chunk → [layers] lapis lantainya; urutan sisip = urutan terakhir dipakai.
  final _chunks = <int, List<GroundMesh>>{};

  late final List<_Crossing> _crossings = _findCrossings(graph);

  final _visibleChunks = <List<GroundMesh>>[];

  @override
  void render(Canvas canvas) {
    // Isi chunk (jalan lebar, ujung bulat) bisa menjorok ±8 unit ke luar chunknya.
    final view = groundRectOf(game.camera.visibleWorldRect).inflate(8);
    _visibleChunks.clear();
    for (var cy = (view.top / chunkSize).floor(); cy <= (view.bottom / chunkSize).floor(); cy++) {
      for (var cx = (view.left / chunkSize).floor(); cx <= (view.right / chunkSize).floor(); cx++) {
        _visibleChunks.add(_chunk(cx, cy));
      }
    }
    canvas.save();
    canvas.transform(isoMatrix);
    drawChunks(canvas, _visibleChunks);
    _renderRoute(canvas);
    canvas.restore();
  }

  /// Gambar [chunks] lapis demi lapis (kanvas sudah di koordinat tanah).
  void drawChunks(Canvas canvas, List<List<GroundMesh>> chunks) {
    for (var l = 0; l < layers; l++) {
      for (final chunk in chunks) {
        chunk[l].draw(canvas);
      }
    }
  }

  List<GroundMesh> _chunk(int cx, int cy) {
    final key = cx * 100000 + cy;
    final cached = _chunks.remove(key);
    if (cached != null) return _chunks[key] = cached;
    if (_chunks.length >= maxChunks) {
      for (final mesh in _chunks.remove(_chunks.keys.first)!) {
        mesh.dispose();
      }
    }
    return _chunks[key] = buildChunk(cx, cy);
  }

  /// Segitiga lantai satu chunk, per lapis.
  List<GroundMesh> buildChunk(int cx, int cy) {
    final rect = Rect.fromLTWH(cx * chunkSize, cy * chunkSize, chunkSize, chunkSize);
    final shallow = TriBuilder(), land = TriBuilder(), curb = TriBuilder(), asphalt = TriBuilder();
    final marks = TriBuilder();
    // Pantai melebar satu sel ke chunk tetangga supaya tepi antialias tidak jadi garis sambungan.
    final cells = rect.inflate(mask.cell);
    _coast(shallow, cells, (s) => s != Surface.deep, _shallowColor);
    _coast(land, cells, (s) => s == Surface.land, BColors.tanah);

    // Tiap potongan jalan dimiliki tepat satu chunk: ruas dipotong di batas chunk,
    // ujung bulat hanya di titik sudut polyline yang ada di chunk ini.
    for (final s in graph.segmentsIn(rect)) {
      final piece = clipToRect(s.a, s.b, rect);
      if (piece == null) continue;
      final (a, b) = piece;
      final curbColor = s.edge.bridge ? BColors.atapMerah : BColors.trotoar;
      final curbWidth = s.edge.width + _curb * 2;
      curb.quadLine(a, b, curbWidth, curbColor);
      asphalt.quadLine(a, b, s.edge.width, BColors.aspal);
      for (final p in [if (_needsJoin(s)) s.a, if (s.index == s.edge.pts.length - 2) s.b]) {
        if (!rect.contains(p)) continue;
        curb.disc(p, curbWidth / 2, curbColor);
        asphalt.disc(p, s.edge.width / 2, BColors.aspal);
      }
      if (!s.edge.type.endsWith('_link')) _addDashes(marks, s, rect);
    }
    for (final x in _crossings) {
      if (rect.contains(x.center)) _addCrossing(marks, x);
    }
    return [
      for (final b in [shallow, land, curb, asphalt, marks]) b.build(),
    ];
  }

  /// Ujung bulat di titik awal ruas [s] perlu: awal jalan, atau belokan > 12°
  /// (di belokan landai celah antar-persegi panjang tidak terlihat).
  static bool _needsJoin(RoadSegment s) {
    if (s.index == 0) return true;
    final prev = s.edge.pts[s.index - 1];
    final d0 = s.a - prev, d1 = s.b - s.a;
    final cross = d0.dx * d1.dy - d0.dy * d1.dx, dot = d0.dx * d1.dx + d0.dy * d1.dy;
    return math.atan2(cross.abs(), dot) > 12 * math.pi / 180;
  }

  /// Zebra cross: belang putih melintang jalan, sejajar arah jalan.
  void _addCrossing(TriBuilder out, _Crossing c) {
    // Belang selebar 0,7 berjarak 1,4 di sepanjang lebar jalan, panjang 2,6 searah jalan.
    const stripe = 0.7, pitch = 1.4, length = 2.6;
    final along = c.dir * (length / 2), across = Offset(-c.dir.dy, c.dir.dx);
    final half = c.width / 2 - 0.5;
    for (var y = -half + stripe / 2; y <= half - stripe / 2 + 1e-6; y += pitch) {
      final m = c.center + across * y;
      out.quadLine(m - along, m + along, stripe, _zebraColor);
    }
  }

  /// Wilayah sel yang memenuhi [inside] sebagai segitiga, dengan marching squares
  /// di antara pusat-pusat sel supaya garis pantai tidak bergerigi kotak.
  void _coast(TriBuilder out, Rect view, bool Function(Surface) inside, Color color) {
    final (c0, r0, c1, r1) = mask.cellRange(view);
    final h = mask.cell / 2;
    final ins = List<bool>.filled(4, false);
    final pts = List<Offset>.filled(4, Offset.zero);
    for (var r = r0; r < r1; r++) {
      var runStart = -1;
      for (var c = c0; c < c1; c++) {
        ins[0] = inside(mask.at(c, r));
        ins[1] = inside(mask.at(c + 1, r));
        ins[2] = inside(mask.at(c + 1, r + 1));
        ins[3] = inside(mask.at(c, r + 1));
        final full = ins[0] && ins[1] && ins[2] && ins[3];
        // Kotak penuh digabung per baris jadi satu persegi panjang.
        if (full) {
          if (runStart < 0) runStart = c;
          continue;
        }
        if (runStart >= 0) {
          out.rect(Rect.fromPoints(mask.centerOf(runStart, r), mask.centerOf(c, r + 1)), color);
          runStart = -1;
        }
        if (!(ins[0] || ins[1] || ins[2] || ins[3])) continue;
        final o = mask.centerOf(c, r);
        pts[0] = o;
        pts[1] = o + Offset(h * 2, 0);
        pts[2] = o + Offset(h * 2, h * 2);
        pts[3] = o + Offset(0, h * 2);
        final poly = <Offset>[];
        for (var i = 0; i < 4; i++) {
          final j = (i + 1) % 4;
          if (ins[i]) poly.add(pts[i]);
          if (ins[i] != ins[j]) poly.add((pts[i] + pts[j]) / 2);
        }
        // Semua kasus marching squares (termasuk pelana) berbentuk cembung.
        out.fan(poly, color);
      }
      if (runStart >= 0) {
        out.rect(Rect.fromPoints(mask.centerOf(runStart, r), mask.centerOf(c1, r + 1)), color);
      }
    }
  }

  final _routeHalo = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = 2.6
    ..color = const Color(0xCCFFFFFF);
  final _routeLine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = 1.6
    ..color = BColors.biruPemain;

  void _renderRoute(Canvas canvas) {
    final route = game.gps.route;
    final dest = game.gps.destination;
    if (route == null || dest == null) return;
    final path = Path()..addPolygon(route.points, false);
    canvas.drawPath(path, _routeHalo);
    canvas.drawPath(path, _routeLine);
    final end = route.points.last;
    canvas.drawCircle(end, 2.4, _routeHalo..style = PaintingStyle.fill);
    canvas.drawCircle(end, 1.8, _routeLine..style = PaintingStyle.fill);
    _routeHalo.style = PaintingStyle.stroke;
    _routeLine.style = PaintingStyle.stroke;
  }

  /// Marka putus-putus ruas [s] yang titik tengahnya ada di [chunk].
  void _addDashes(TriBuilder out, RoadSegment s, Rect chunk) {
    const period = _dash + _gap;
    final len = s.length;
    if (len == 0) return;
    final dir = (s.b - s.a) / len;
    var k = (s.startDist / period).floor();
    while (k * period < s.startDist + len) {
      final from = math.max(k * period, s.startDist) - s.startDist;
      final to = math.min(k * period + _dash, s.startDist + len) - s.startDist;
      final a = s.a + dir * from, b = s.a + dir * to;
      if (to > from && chunk.contains((a + b) / 2)) out.quadLine(a, b, _markWidth, BColors.kuning);
      k++;
    }
  }
}

/// Satu zebra cross: titik tengah di as jalan, arah jalan, dan lebar aspal.
class _Crossing {
  const _Crossing(this.center, this.dir, this.width);

  final Offset center;
  final Offset dir;
  final double width;
}

/// Zebra cross di tiap kaki simpang (≥ 3 jalan bukan ramp) yang melibatkan
/// jalan besar, sedikit sebelum mulut simpang.
List<_Crossing> _findCrossings(RoadGraph graph) {
  final out = <_Crossing>[];
  for (final MapEntry(key: node, value: edges) in graph.adjacency.entries) {
    final legs = edges.where((e) => !e.type.endsWith('_link') && !e.bridge).toList();
    if (legs.length < 3) continue;
    if (!legs.any(
      (e) => e.type.startsWith('trunk') || e.type.startsWith('primary') || e.type.startsWith('secondary'),
    )) {
      continue;
    }
    final at = graph.nodes[node]!;
    final mouth = legs.map((e) => e.width).reduce(math.max) / 2 + 2.5;
    for (final e in legs) {
      // Arah keluar dari simpang di sepanjang kaki ini.
      final pts = e.from == node ? e.pts : e.pts.reversed.toList();
      if (pts.length < 2) continue;
      final d0 = pts[1] - pts[0];
      if (d0.distance < mouth + 2) continue;
      final dir = d0 / d0.distance;
      out.add(_Crossing(at + dir * mouth, dir, e.width));
    }
  }
  return out;
}

extension SeaBlock on BatamGame {
  /// True bila [p] ada di air (mask) dan bukan di jalan/jembatan.
  bool isWaterBlocked(Offset p) => mask.isWater(p) && !graph.isOnRoad(p);

  /// True bila [p] di air atau di dalam bangunan (tidak bisa dilewati).
  bool isBlocked(Offset p) => isWaterBlocked(p) || city.blocks(p);
}
